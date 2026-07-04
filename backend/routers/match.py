"""
Stateless matchmaker.

Design — what changed vs. the old WebSocket-only matcher:

  * No active_connections dict.  No call_timers dict.  All cross-user signalling
    is broadcast through Supabase Realtime, so it works the same whether we
    have one FastAPI pod or fifty.

  * /ws/match is now ONLY for "I am waiting to be matched" presence.  It owns
    the queue entry and nothing else.  As soon as a partner is found we send
    one "matched" frame, the server closes the socket, and the client moves
    onto the call screen.  Any later signalling (call_ended, etc.) flows over
    Supabase Realtime so disconnecting this WS never tears the room down.

  * No "matching task races a disconnect cleanup" problem — disconnect cleanup
    here does exactly one thing: remove this user_id from the waiting queue.

Match notification path:

  1. Client subscribes to Realtime channel  user:{user_id}  BEFORE opening WS.
  2. Client opens WS to /ws/match.
  3. Backend loops calling find_partner (atomic Lua pop on Redis sorted set).
  4. When find_partner returns a partner, backend builds the room state,
     broadcasts the "matched" event to  user:{me}  AND  user:{partner}  via
     Supabase Realtime, AND sends the same event over our open WS as a
     low-latency fast-path for the matcher caller.
  5. Backend closes WS server-side.  Client navigates to /call.
"""

import asyncio
import json
import logging
from datetime import datetime, timezone
from typing import Optional
from uuid import uuid4

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect

from core.config import settings
from services import redis_client
from services.agora_service import generate_token
from services.supabase_client import supabase_admin
from services.supabase_realtime import broadcast

router = APIRouter(tags=["match"])
logger = logging.getLogger(__name__)

# Per-process WS registry — used ONLY to deliver the "matched" event directly
# to the partner if they happen to be on the same pod.  NOT used for call
# lifecycle.  Stateless design is preserved: Realtime is the authoritative path.
_active_ws: dict[str, WebSocket] = {}


# ── Helpers ──────────────────────────────────────────────────────────────────

async def _authenticate(token: str) -> Optional[str]:
    """Return user_id if token is a valid Supabase JWT, else None."""
    try:
        resp = supabase_admin.auth.get_user(token)
        if not resp or not resp.user:
            return None
        return str(resp.user.id)
    except Exception:
        return None


async def _fetch_profile(user_id: str) -> dict:
    try:
        row = (
            supabase_admin.table("profiles")
            .select("name,age,gender,avatar_url,bio,occupation,sector,country,state,mother_tongue")
            .eq("id", user_id)
            .single()
            .execute()
            .data
        )
        return row or {"name": "User"}
    except Exception:
        return {"name": "User"}


def _build_match_payload(channel_name: str, my_token: str, my_uid: int,
                         partner_id: str, partner_profile: dict) -> dict:
    return {
        "channel_name": channel_name,
        "agora_token": my_token,
        "agora_uid": my_uid,
        "agora_app_id": settings.agora_app_id,
        "partner_id": partner_id,
        "partner": {
            "name": partner_profile.get("name", "User"),
            "age": partner_profile.get("age"),
            "gender": partner_profile.get("gender"),
            "avatar_url": partner_profile.get("avatar_url"),
            "bio": partner_profile.get("bio"),
            "occupation": partner_profile.get("occupation"),
            "sector": partner_profile.get("sector"),
            "country": partner_profile.get("country"),
            "state": partner_profile.get("state"),
            "mother_tongue": partner_profile.get("mother_tongue"),
        },
    }


async def _create_match(user_a: str, user_b: str) -> tuple[dict, dict]:
    """
    Build all state for a fresh call: tokens, Redis room state, call_history
    row, active_rooms timer entry.  Returns the per-side match payloads.

    Idempotent on the Supabase insert (try/except wrapped) and on Redis (TTLs
    overwrite cleanly), so a partial failure does not poison the room.
    """
    channel_name = str(uuid4())
    now = datetime.now(timezone.utc)
    started_at_unix = now.timestamp()
    end_time_unix = started_at_unix + redis_client.CALL_DURATION

    token_a, uid_a = generate_token(
        channel_name, user_a, settings.agora_app_id, settings.agora_app_certificate
    )
    token_b, uid_b = generate_token(
        channel_name, user_b, settings.agora_app_id, settings.agora_app_certificate
    )

    profile_a, profile_b = await asyncio.gather(
        _fetch_profile(user_a), _fetch_profile(user_b)
    )

    # Redis state — partner mapping + per-user room pointer + timer registration.
    await redis_client.set_user_room(user_a, channel_name)
    await redis_client.set_user_room(user_b, channel_name)
    await redis_client.set_room_partners(channel_name, user_a, user_b)
    await redis_client.register_active_room(
        channel_name, user_a, user_b, started_at_unix, end_time_unix
    )

    # Best-effort call_history insert; failure here must not block matching.
    try:
        supabase_admin.table("call_history").insert(
            {
                "user_a": user_a,
                "user_b": user_b,
                "room_id": channel_name,
                "started_at": now.isoformat(),
            }
        ).execute()
    except Exception as e:
        logger.warning("call_history insert failed: %r", e)

    payload_a = _build_match_payload(channel_name, token_a, uid_a, user_b, profile_b)
    payload_b = _build_match_payload(channel_name, token_b, uid_b, user_a, profile_a)
    return payload_a, payload_b


async def _send_ws(ws: WebSocket, data: dict) -> bool:
    try:
        await ws.send_text(json.dumps(data))
        return True
    except Exception:
        return False


# ── WebSocket: queue presence + cancel ───────────────────────────────────────

# Per-process queue-poll interval.  Lower = lower match latency, more Redis
# QPS.  Each user runs a single loop, so total QPS = active_waiters / interval.
_MATCH_POLL_INTERVAL_S = 1.0


def _parse_filter(
    gender: Optional[str],
    age_range: Optional[str],
    min_rating: Optional[float],
    max_rating: Optional[float],
) -> Optional[dict]:
    f = {}
    if gender:       f["gender"] = gender.lower()
    if age_range:    f["age_range"] = age_range
    if min_rating is not None: f["min_rating"] = min_rating
    if max_rating is not None: f["max_rating"] = max_rating
    return f or None


def _partner_matches_filter(profile: dict, f: Optional[dict]) -> bool:
    """Return True if partner profile satisfies the caller's filter."""
    if not f:
        return True

    # Gender
    if "gender" in f:
        pg = (profile.get("gender") or "").lower()
        if pg != f["gender"]:
            return False

    # Age range
    if "age_range" in f:
        age = profile.get("age")
        if age is None:
            return False
        lo, hi = _parse_age_range(f["age_range"])
        if lo is not None and age < lo:
            return False
        if hi is not None and age > hi:
            return False

    # Rating range — new users have avg_rating = 0, treat as unrated → skip filter
    partner_rating = float(profile.get("avg_rating") or 0)
    rating_count   = int(profile.get("rating_count") or 0)
    if rating_count > 0:   # only filter rated users
        if "min_rating" in f and partner_rating < f["min_rating"]:
            return False
        if "max_rating" in f and partner_rating > f["max_rating"]:
            return False

    return True


def _parse_age_range(age_range: str) -> tuple[Optional[int], Optional[int]]:
    if "-" in age_range:
        parts = age_range.split("-")
        try:
            return int(parts[0]), int(parts[1])
        except (ValueError, IndexError):
            return None, None
    if age_range.endswith("+"):
        try:
            return int(age_range[:-1]), None
        except ValueError:
            return None, None
    return None, None


@router.websocket("/ws/match")
async def websocket_match(
    websocket: WebSocket,
    token: str = Query(...),
    gender: Optional[str] = Query(None),
    age_range: Optional[str] = Query(None),
    min_rating: Optional[float] = Query(None),
    max_rating: Optional[float] = Query(None),
):
    """
    Hold a user in the waiting queue and try to pair them on a 1-second tick.

    The WebSocket is short-lived: it lives only until either (a) a partner is
    found, or (b) the client closes / cancels.  The backend keeps NO state
    about the resulting call inside this handler — that's all in Redis and
    delivered via Supabase Realtime.
    """
    user_id = await _authenticate(token)
    if not user_id:
        await websocket.close(code=4001)
        return

    await websocket.accept()

    existing_room = await redis_client.get_user_room(user_id)
    if existing_room:
        await _send_ws(websocket, {
            "type": "already_in_call",
            "channel_name": existing_room,
        })
        try:
            await websocket.close()
        except Exception:
            pass
        return

    user_filter = _parse_filter(gender, age_range, min_rating, max_rating)

    await redis_client.add_to_queue(user_id)
    await _send_ws(websocket, {"type": "waiting"})

    _active_ws[user_id] = websocket
    matcher = asyncio.create_task(_matcher_loop(user_id, websocket, user_filter))

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue

            mtype = msg.get("type")
            if mtype == "cancel":
                break
            elif mtype == "ping":
                await _send_ws(websocket, {"type": "pong"})
            # All other client→server signalling now goes over HTTP / Realtime.
    except WebSocketDisconnect:
        pass
    finally:
        matcher.cancel()
        _active_ws.pop(user_id, None)
        await redis_client.remove_from_queue(user_id)
        try:
            await websocket.close()
        except Exception:
            pass


async def _matcher_loop(user_id: str, websocket: WebSocket, user_filter: Optional[dict] = None):
    """
    Background task per WS connection.  Polls Redis on a fixed cadence trying
    to claim a partner.  Applies filter check before confirming a match —
    incompatible partners are returned to the queue.
    """
    try:
        while True:
            partner_id = await redis_client.find_partner(user_id)
            if not partner_id:
                await asyncio.sleep(_MATCH_POLL_INTERVAL_S)
                continue

            # Filter check — fetch partner profile and verify it meets the
            # caller's preferences.  If not, put partner back and keep looking.
            if user_filter:
                partner_profile = await _fetch_profile(partner_id)
                if not _partner_matches_filter(partner_profile, user_filter):
                    logger.info(
                        "filter skip: %s rejected partner %s (filter=%s)",
                        user_id, partner_id, user_filter,
                    )
                    await redis_client.add_to_queue(partner_id)
                    await asyncio.sleep(_MATCH_POLL_INTERVAL_S)
                    continue

            try:
                payload_me, payload_partner = await _create_match(user_id, partner_id)
            except Exception as e:
                logger.exception("create_match failed: %r", e)
                await redis_client.add_to_queue(user_id)
                await redis_client.add_to_queue(partner_id)
                await asyncio.sleep(_MATCH_POLL_INTERVAL_S)
                continue

            await asyncio.gather(
                broadcast(f"user:{user_id}", "matched", payload_me),
                broadcast(f"user:{partner_id}", "matched", payload_partner),
            )

            partner_ws = _active_ws.get(partner_id)
            await asyncio.gather(
                _send_ws(websocket, {"type": "matched", **payload_me}),
                _send_ws(partner_ws, {"type": "matched", **payload_partner})
                if partner_ws else asyncio.sleep(0),
            )
            return

    except asyncio.CancelledError:
        raise
