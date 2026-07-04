"""
Call lifecycle endpoints.

This is now the single place that ends a call.  Both clients receive the
call_ended event over Supabase Realtime (subscribed on `room:{channel_name}`),
so we never need to know which backend instance is holding which WebSocket.
"""

import asyncio
import logging
from datetime import datetime, timezone
from uuid import uuid4

from fastapi import APIRouter, Header, HTTPException

from core.config import settings
from models.schemas import CallEndEvent, CallRateEvent, DirectCallBody
from services import redis_client
from services.agora_service import generate_token
from services.supabase_client import supabase_admin
from services.supabase_realtime import broadcast

router = APIRouter(prefix="/call", tags=["call"])
logger = logging.getLogger(__name__)


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


@router.post("/end")
async def end_call(data: CallEndEvent, authorization: str = Header(...)):
    """
    End a call.  Safe to call multiple times — every Redis op is idempotent
    and the call_history UPDATE is gated on `ended_at IS NULL`.
    """
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    user_id = user["id"]
    channel_name = data.channel_name

    # Look up partner BEFORE we delete the partner mapping.
    partner_id = await redis_client.get_partner(channel_name, user_id)

    # Compute duration from call_info (Redis) so we don't need an extra
    # Supabase round-trip just to read started_at.
    duration_seconds = None
    info = await redis_client.get_call_info(channel_name)
    if info and "started_at" in info:
        try:
            started_unix = float(info["started_at"])
            duration_seconds = max(
                0, int(datetime.now(timezone.utc).timestamp() - started_unix)
            )
        except (TypeError, ValueError):
            pass

    # Determine ended_by from DB constraint values: user_a / user_b / timer / disconnect
    if data.reason == "timer":
        ended_by = "timer"
    elif data.reason == "disconnect":
        ended_by = "disconnect"
    else:
        # "manual" or anything else — map to user_a or user_b based on who called
        ended_by = "user_a" if info and user_id == info.get("user_a") else "user_b"

    now_iso = datetime.now(timezone.utc).isoformat()
    update: dict = {"ended_at": now_iso, "ended_by": ended_by}
    if duration_seconds is not None:
        update["duration_seconds"] = duration_seconds
    try:
        supabase_admin.table("call_history").update(update).eq(
            "room_id", channel_name
        ).is_("ended_at", "null").execute()
    except Exception as e:
        logger.warning("call_history close failed: %r", e)

    # Tear down Redis state.
    await redis_client.delete_user_room(user_id)
    if partner_id:
        await redis_client.delete_user_room(partner_id)
    await redis_client.delete_room_partners(channel_name, user_id, partner_id or "")
    await redis_client.deregister_active_room(channel_name)

    # Tell anyone subscribed to this room that the call is over.  Both clients
    # are on room:{channel_name}, so a single broadcast notifies both.
    await broadcast(
        f"room:{channel_name}",
        "call_ended",
        {"reason": data.reason or "user", "ended_by": user_id},
    )

    return {"status": "ok"}


@router.post("/direct")
async def direct_call(body: DirectCallBody, authorization: str = Header(...)):
    """Initiate a direct call to a friend who is online."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    caller_id = user["id"]

    channel_name = str(uuid4())
    token_c, uid_c = generate_token(channel_name, caller_id, settings.agora_app_id, settings.agora_app_certificate)
    token_r, uid_r = generate_token(channel_name, body.receiver_id, settings.agora_app_id, settings.agora_app_certificate)

    try:
        profile = (
            supabase_admin.table("profiles")
            .select("name,age,gender,avatar_url,bio,occupation,sector,country,state,mother_tongue")
            .eq("id", caller_id)
            .single()
            .execute()
            .data
        ) or {"name": "User"}
    except Exception:
        profile = {"name": "User"}

    # Broadcast incoming call to receiver's personal channel
    await broadcast(
        f"direct:{body.receiver_id}",
        "incoming_call",
        {
            "channel_name": channel_name,
            "agora_token": token_r,
            "agora_uid": uid_r,
            "agora_app_id": settings.agora_app_id,
            "partner_id": caller_id,
            "partner": profile,
        },
    )

    return {
        "channel_name": channel_name,
        "agora_token": token_c,
        "agora_uid": uid_c,
        "agora_app_id": settings.agora_app_id,
    }


@router.post("/rate")
async def rate_call(data: CallRateEvent, authorization: str = Header(...)):
    """
    Record a 1-5 star rating for the partner after a call.
    Idempotent per (room_id, rater_id) via unique constraint — an UPSERT
    lets the user change their mind before leaving the screen.
    """
    if not (1 <= data.stars <= 5):
        raise HTTPException(status_code=400, detail="Stars must be 1-5")
    if not data.rated_user_id or not data.channel_name:
        raise HTTPException(status_code=400, detail="Missing fields")

    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    rater_id = user["id"]

    if rater_id == data.rated_user_id:
        raise HTTPException(status_code=400, detail="Cannot rate yourself")

    try:
        supabase_admin.table("call_ratings").upsert(
            {
                "room_id": data.channel_name,
                "rater_id": rater_id,
                "rated_id": data.rated_user_id,
                "stars": data.stars,
            },
            on_conflict="room_id,rater_id",
        ).execute()
    except Exception as e:
        logger.warning("rating insert failed: %r", e)
        raise HTTPException(status_code=500, detail="Rating save failed")

    return {"status": "ok"}
