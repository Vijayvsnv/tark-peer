"""
Call lifecycle endpoints.

This is now the single place that ends a call.  Both clients receive the
call_ended event over Supabase Realtime (subscribed on `room:{channel_name}`),
so we never need to know which backend instance is holding which WebSocket.
"""

import logging
from datetime import datetime, timezone

from fastapi import APIRouter, Header, HTTPException

from models.schemas import CallEndEvent
from services import redis_client
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
