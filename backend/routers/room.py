"""
Room feature endpoints.

Rooms allow 2–10 users to join a shared voice channel either publicly
(discoverable) or privately (code-only). Each room has a 2-hour TTL.

Endpoints
---------
POST /room/create  — Create a new room, get Agora token for slot 1.
POST /room/join    — Join by 6-char code, get Agora token for next free slot.
POST /room/leave   — Leave a room; ends the room when last member leaves.
GET  /room/public  — List open, non-full public rooms.
GET  /room/{code}  — Fetch room details + member list (by code).

Background task
---------------
expire_old_rooms() — called periodically by main.py to close expired rooms.
"""

import logging
import secrets
import string
from datetime import datetime, timedelta, timezone
from typing import Annotated, Literal, Optional

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel, Field

from core.config import settings
from services.agora_service import generate_token
from services.supabase_client import supabase_admin
from services.supabase_realtime import broadcast

router = APIRouter(prefix="/room", tags=["room"])
logger = logging.getLogger(__name__)

_CODE_ALPHABET = string.ascii_uppercase + string.digits  # A-Z 0-9
_CODE_LENGTH = 6
_CODE_MAX_RETRIES = 10
_ROOM_TTL_HOURS = 2


# ---------------------------------------------------------------------------
# Pydantic models
# ---------------------------------------------------------------------------


class RoomCreateBody(BaseModel):
    name: str = Field(..., min_length=1, max_length=50)
    type: Literal["private", "public"]
    max_members: Literal[2, 4, 6, 8, 10]


class RoomJoinBody(BaseModel):
    code: str = Field(..., min_length=6, max_length=6)


class RoomLeaveBody(BaseModel):
    room_id: str = Field(..., min_length=1)


# ---------------------------------------------------------------------------
# Auth helper (mirrors call.py)
# ---------------------------------------------------------------------------


async def _get_user(token: str) -> dict:
    try:
        resp = supabase_admin.auth.get_user(token)
        if not resp or not resp.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": str(resp.user.id)}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _now_utc() -> datetime:
    return datetime.now(timezone.utc)


def _now_iso() -> str:
    return _now_utc().isoformat()


def _check_user_active_room(user_id: str) -> Optional[str]:
    """
    Return the room_id if the user is already in an active room, else None.
    Raises HTTPException(500) on unexpected DB errors.
    """
    try:
        resp = (
            supabase_admin.table("room_members")
            .select("room_id")
            .eq("user_id", user_id)
            .eq("is_active", True)
            .limit(1)
            .execute()
        )
        if resp.data:
            return resp.data[0]["room_id"]
        return None
    except Exception as exc:
        logger.warning("active-room check failed for %s: %r", user_id, exc)
        raise HTTPException(status_code=500, detail="Room membership check failed")


def _generate_unique_code() -> str:
    """
    Generate a 6-char A-Z0-9 code not already in use by a non-ended room.
    Raises HTTPException(500) if no unique code found after _CODE_MAX_RETRIES.
    """
    for attempt in range(_CODE_MAX_RETRIES):
        code = "".join(secrets.choice(_CODE_ALPHABET) for _ in range(_CODE_LENGTH))
        try:
            resp = (
                supabase_admin.table("rooms")
                .select("id")
                .eq("code", code)
                .neq("status", "ended")
                .limit(1)
                .execute()
            )
            if not resp.data:
                return code
        except Exception as exc:
            logger.warning("code uniqueness check failed (attempt %d): %r", attempt, exc)
    raise HTTPException(status_code=500, detail="Could not generate a unique room code")


async def _fetch_members_with_profiles(room_id: str) -> list[dict]:
    """
    Fetch active room_members for *room_id*, batch-fetch their profiles,
    merge, and return a list sorted by slot_number.
    """
    try:
        members_resp = (
            supabase_admin.table("room_members")
            .select("slot_number, user_id, agora_uid")
            .eq("room_id", room_id)
            .eq("is_active", True)
            .execute()
        )
    except Exception as exc:
        logger.warning("fetch members failed for room %s: %r", room_id, exc)
        return []

    members = members_resp.data or []
    if not members:
        return []

    user_ids = [m["user_id"] for m in members]

    try:
        profiles_resp = (
            supabase_admin.table("profiles")
            .select("id, name, avatar_url, country")
            .in_("id", user_ids)
            .execute()
        )
        profiles_by_id: dict[str, dict] = {
            p["id"]: p for p in (profiles_resp.data or [])
        }
    except Exception as exc:
        logger.warning("fetch profiles batch failed for room %s: %r", room_id, exc)
        profiles_by_id = {}

    merged = []
    for m in members:
        profile = profiles_by_id.get(m["user_id"], {})
        merged.append(
            {
                "user_id": m["user_id"],
                "slot_number": m["slot_number"],
                "agora_uid": m["agora_uid"],
                "name": profile.get("name", "User"),
                "avatar_url": profile.get("avatar_url"),
                "country": profile.get("country"),
            }
        )

    merged.sort(key=lambda x: x["slot_number"])
    return merged


def _find_free_slot(active_members: list[dict], max_members: int) -> int:
    """
    Return the lowest slot number (1-indexed) not already taken.
    Raises HTTPException(409) if all slots are occupied.
    """
    taken = {m["slot_number"] for m in active_members}
    for slot in range(1, max_members + 1):
        if slot not in taken:
            return slot
    raise HTTPException(status_code=409, detail="Room is full")


def _build_room_response(
    room: dict,
    my_slot: int,
    agora_token: str,
    agora_uid: int,
    members: list[dict],
) -> dict:
    return {
        "room_id": room["id"],
        "code": room["code"],
        "name": room["name"],
        "type": room["type"],
        "max_members": room["max_members"],
        "my_slot": my_slot,
        "agora_token": agora_token,
        "agora_uid": agora_uid,
        "agora_app_id": settings.agora_app_id,
        "expires_at": room["expires_at"],
        "members": members,
    }


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/create")
async def create_room(body: RoomCreateBody, authorization: str = Header(...)):
    """
    Create a new room. The caller becomes slot 1 (host).
    Returns Agora credentials and the initial member list.
    """
    token = authorization.replace("Bearer ", "", 1)
    user = await _get_user(token)
    user_id = user["id"]

    # Guard: user must not already be in a live room.
    existing = _check_user_active_room(user_id)
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You are already in an active room. Leave it before creating a new one.",
        )

    # Unique room code.
    code = _generate_unique_code()

    # Agora token for this user.
    channel_name = f"room_{code}"
    agora_token, agora_uid = generate_token(
        channel_name, user_id, settings.agora_app_id, settings.agora_app_certificate
    )

    expires_at = (_now_utc() + timedelta(hours=_ROOM_TTL_HOURS)).isoformat()

    # Insert room row.
    try:
        room_resp = (
            supabase_admin.table("rooms")
            .insert(
                {
                    "code": code,
                    "name": body.name,
                    "type": body.type,
                    "max_members": body.max_members,
                    "status": "active",
                    "host_id": user_id,
                    "expires_at": expires_at,
                }
            )
            .execute()
        )
        room = room_resp.data[0]
    except Exception as exc:
        logger.error("room insert failed: %r", exc)
        raise HTTPException(status_code=500, detail="Failed to create room")

    room_id = room["id"]

    # Insert creator as member in slot 1.
    try:
        supabase_admin.table("room_members").insert(
            {
                "room_id": room_id,
                "user_id": user_id,
                "slot_number": 1,
                "agora_uid": agora_uid,
                "is_active": True,
            }
        ).execute()
    except Exception as exc:
        logger.error("room_members insert (creator) failed: %r", exc)
        # Best-effort cleanup: mark room as ended.
        try:
            supabase_admin.table("rooms").update({"status": "ended"}).eq(
                "id", room_id
            ).execute()
        except Exception:
            pass
        raise HTTPException(status_code=500, detail="Failed to add creator to room")

    members = await _fetch_members_with_profiles(room_id)
    return _build_room_response(room, 1, agora_token, agora_uid, members)


@router.post("/join")
async def join_room(body: RoomJoinBody, authorization: str = Header(...)):
    """
    Join an existing room by its 6-char code.
    Assigns the lowest free slot and returns Agora credentials.
    """
    token = authorization.replace("Bearer ", "", 1)
    user = await _get_user(token)
    user_id = user["id"]

    # Guard: user must not already be in a live room.
    existing = _check_user_active_room(user_id)
    if existing:
        raise HTTPException(
            status_code=409,
            detail="You are already in an active room. Leave it before joining another.",
        )

    code = body.code.upper()

    # Fetch the room.
    try:
        room_resp = (
            supabase_admin.table("rooms")
            .select("*")
            .eq("code", code)
            .in_("status", ["waiting", "active"])
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.warning("room fetch (join) failed for code %s: %r", code, exc)
        raise HTTPException(status_code=500, detail="Room lookup failed")

    if not room_resp.data:
        raise HTTPException(status_code=404, detail="Room not found or no longer active")

    room = room_resp.data[0]
    room_id = room["id"]

    # Expiry check.
    expires_at_str: str = room.get("expires_at", "")
    if expires_at_str:
        try:
            expires_dt = datetime.fromisoformat(expires_at_str)
            if expires_dt.tzinfo is None:
                expires_dt = expires_dt.replace(tzinfo=timezone.utc)
            if _now_utc() >= expires_dt:
                raise HTTPException(status_code=410, detail="Room has expired")
        except HTTPException:
            raise
        except Exception:
            pass  # malformed timestamp — let it through

    # Fetch current active members to find a free slot.
    try:
        members_resp = (
            supabase_admin.table("room_members")
            .select("slot_number, user_id, agora_uid")
            .eq("room_id", room_id)
            .eq("is_active", True)
            .execute()
        )
        active_members: list[dict] = members_resp.data or []
    except Exception as exc:
        logger.warning("member fetch (join) failed for room %s: %r", room_id, exc)
        raise HTTPException(status_code=500, detail="Failed to fetch room members")

    # Check if user is already an active member (re-join / duplicate request).
    already_in = next((m for m in active_members if m["user_id"] == user_id), None)
    if already_in:
        # Re-issue token and return current state.
        channel_name = f"room_{code}"
        agora_token, agora_uid = generate_token(
            channel_name, user_id, settings.agora_app_id, settings.agora_app_certificate
        )
        members = await _fetch_members_with_profiles(room_id)
        return _build_room_response(
            room, already_in["slot_number"], agora_token, already_in["agora_uid"], members
        )

    slot = _find_free_slot(active_members, room["max_members"])

    channel_name = f"room_{code}"
    agora_token, agora_uid = generate_token(
        channel_name, user_id, settings.agora_app_id, settings.agora_app_certificate
    )

    # Insert new membership.
    try:
        supabase_admin.table("room_members").insert(
            {
                "room_id": room_id,
                "user_id": user_id,
                "slot_number": slot,
                "agora_uid": agora_uid,
                "is_active": True,
            }
        ).execute()
    except Exception as exc:
        logger.error("room_members insert (join) failed: %r", exc)
        raise HTTPException(status_code=500, detail="Failed to join room")

    # Transition room from 'waiting' to 'active' if it was still waiting.
    if room["status"] == "waiting":
        try:
            updated = (
                supabase_admin.table("rooms")
                .update({"status": "active"})
                .eq("id", room_id)
                .eq("status", "waiting")  # guard against concurrent join
                .execute()
            )
            if updated.data:
                room = updated.data[0]
        except Exception as exc:
            logger.warning("room status → active failed for %s: %r", room_id, exc)

    # Broadcast the join event to existing members.
    await broadcast(
        f"room:{room_id}",
        "member_joined",
        {"user_id": user_id, "slot_number": slot},
    )

    members = await _fetch_members_with_profiles(room_id)
    return _build_room_response(room, slot, agora_token, agora_uid, members)


@router.post("/leave")
async def leave_room(body: RoomLeaveBody, authorization: str = Header(...)):
    """
    Leave a room. Ends the room when no active members remain.
    """
    token = authorization.replace("Bearer ", "", 1)
    user = await _get_user(token)
    user_id = user["id"]
    room_id = body.room_id

    now_iso = _now_iso()

    # Deactivate this user's membership.
    try:
        supabase_admin.table("room_members").update(
            {"is_active": False, "left_at": now_iso}
        ).eq("room_id", room_id).eq("user_id", user_id).eq(
            "is_active", True
        ).execute()
    except Exception as exc:
        logger.warning(
            "room_members deactivate failed (room=%s, user=%s): %r",
            room_id, user_id, exc,
        )
        # Non-fatal — proceed with broadcast and room-end check.

    # Check remaining active members.
    try:
        remaining_resp = (
            supabase_admin.table("room_members")
            .select("user_id", count="exact")
            .eq("room_id", room_id)
            .eq("is_active", True)
            .execute()
        )
        remaining_count: int = remaining_resp.count or 0
    except Exception as exc:
        logger.warning(
            "remaining-member check failed (room=%s): %r", room_id, exc
        )
        remaining_count = -1  # unknown — don't end the room speculatively

    if remaining_count == 0:
        # No one left — end the room.
        try:
            supabase_admin.table("rooms").update(
                {"status": "ended"}
            ).eq("id", room_id).neq("status", "ended").execute()
        except Exception as exc:
            logger.warning("room end failed (room=%s): %r", room_id, exc)

        await broadcast(
            f"room:{room_id}",
            "room_ended",
            {"reason": "empty"},
        )
    else:
        # Room still has members — just notify them someone left.
        await broadcast(
            f"room:{room_id}",
            "member_left",
            {"user_id": user_id},
        )

    return {"status": "ok"}


@router.get("/public")
async def list_public_rooms(authorization: str = Header(...)):
    """
    Return open, non-full public rooms ordered by creation time (newest first).
    Full rooms are hidden from the list.
    """
    token = authorization.replace("Bearer ", "", 1)
    await _get_user(token)  # auth gate only; we don't need the user identity here

    try:
        rooms_resp = (
            supabase_admin.table("rooms")
            .select("id, code, name, max_members, created_at")
            .eq("type", "public")
            .in_("status", ["waiting", "active"])
            .order("created_at", desc=True)
            .limit(30)
            .execute()
        )
    except Exception as exc:
        logger.warning("public rooms fetch failed: %r", exc)
        raise HTTPException(status_code=500, detail="Failed to fetch public rooms")

    rooms: list[dict] = rooms_resp.data or []
    if not rooms:
        return []

    room_ids = [r["id"] for r in rooms]

    # Batch-fetch active member counts.
    try:
        counts_resp = (
            supabase_admin.table("room_members")
            .select("room_id", count="exact")
            .in_("room_id", room_ids)
            .eq("is_active", True)
            .execute()
        )
        # supabase-py returns all rows but not grouped counts — tally manually.
        count_by_room: dict[str, int] = {}
        for row in counts_resp.data or []:
            rid = row["room_id"]
            count_by_room[rid] = count_by_room.get(rid, 0) + 1
    except Exception as exc:
        logger.warning("member count batch fetch failed: %r", exc)
        count_by_room = {}

    result = []
    for room in rooms:
        rid = room["id"]
        member_count = count_by_room.get(rid, 0)
        if member_count < room["max_members"]:
            result.append(
                {
                    "room_id": rid,
                    "code": room["code"],
                    "name": room["name"],
                    "max_members": room["max_members"],
                    "member_count": member_count,
                }
            )

    return result


@router.get("/{code}")
async def get_room(code: str, authorization: str = Header(...)):
    """
    Fetch room details and the current active member list by room code.
    """
    token = authorization.replace("Bearer ", "", 1)
    await _get_user(token)

    code = code.upper()

    try:
        room_resp = (
            supabase_admin.table("rooms")
            .select("*")
            .eq("code", code)
            .limit(1)
            .execute()
        )
    except Exception as exc:
        logger.warning("room get by code failed (%s): %r", code, exc)
        raise HTTPException(status_code=500, detail="Room lookup failed")

    if not room_resp.data:
        raise HTTPException(status_code=404, detail="Room not found")

    room = room_resp.data[0]
    members = await _fetch_members_with_profiles(room["id"])

    return {
        "room_id": room["id"],
        "code": room["code"],
        "name": room["name"],
        "type": room["type"],
        "max_members": room["max_members"],
        "status": room["status"],
        "expires_at": room.get("expires_at"),
        "created_at": room.get("created_at"),
        "members": members,
    }


# ---------------------------------------------------------------------------
# Background task: expire old rooms
# ---------------------------------------------------------------------------


async def expire_old_rooms() -> None:
    """
    Find rooms whose expires_at has passed and status is not yet 'ended',
    mark them ended, and broadcast a room_ended event to all subscribers.

    Intended to be called periodically by the main.py background scanner.
    """
    now_iso = _now_iso()
    try:
        expired_resp = (
            supabase_admin.table("rooms")
            .select("id")
            .lt("expires_at", now_iso)
            .neq("status", "ended")
            .execute()
        )
    except Exception as exc:
        logger.warning("expire_old_rooms: fetch failed: %r", exc)
        return

    expired_rooms: list[dict] = expired_resp.data or []
    if not expired_rooms:
        return

    logger.info("expire_old_rooms: expiring %d room(s)", len(expired_rooms))

    for room in expired_rooms:
        room_id: str = room["id"]
        try:
            supabase_admin.table("rooms").update(
                {"status": "ended"}
            ).eq("id", room_id).neq("status", "ended").execute()
        except Exception as exc:
            logger.warning(
                "expire_old_rooms: update failed for room %s: %r", room_id, exc
            )

        # Best-effort broadcast — failure must never crash the scanner.
        await broadcast(
            f"room:{room_id}",
            "room_ended",
            {"reason": "expired"},
        )
