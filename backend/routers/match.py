import asyncio
import json
from uuid import uuid4
from datetime import datetime, timezone

from fastapi import APIRouter, WebSocket, WebSocketDisconnect, Query
from services.supabase_client import supabase_admin
from services import redis_client
from services.agora_service import generate_token
from core.config import settings

router = APIRouter(tags=["match"])

# user_id -> WebSocket (only live connections)
active_connections: dict[str, WebSocket] = {}
# room_id -> asyncio.Task
call_timers: dict[str, asyncio.Task] = {}

CALL_DURATION = 1800  # 30 minutes


# ── Helpers ──────────────────────────────────────────────────────────────────

async def send_json(ws: WebSocket, data: dict):
    try:
        await ws.send_text(json.dumps(data))
    except Exception:
        pass


async def notify_user(user_id: str, data: dict):
    ws = active_connections.get(user_id)
    if ws:
        await send_json(ws, data)


async def _close_ws(ws: WebSocket):
    try:
        await ws.close(1000)
    except Exception:
        pass


async def _full_room_cleanup(
    room_id: str,
    user_id: str,
    ended_by: str,
    notify_partner_reason: str,
):
    """
    Centralised cleanup for a room.  Safe to call even if some keys are
    already gone (all Redis ops are idempotent).
    """
    partner_id = await redis_client.get_partner(room_id, user_id)

    # Cancel the 30-min timer if still running
    timer = call_timers.pop(room_id, None)
    if timer:
        timer.cancel()

    # Persist end time + duration in call_history
    now = datetime.now(timezone.utc)
    duration_seconds = None
    try:
        row = (
            supabase_admin.table("call_history")
            .select("started_at")
            .eq("room_id", room_id)
            .maybe_single()
            .execute()
        )
        if row.data and row.data.get("started_at"):
            started = datetime.fromisoformat(
                row.data["started_at"].replace("Z", "+00:00")
            )
            duration_seconds = max(0, int((now - started).total_seconds()))
    except Exception:
        pass

    update: dict = {"ended_at": now.isoformat(), "ended_by": ended_by}
    if duration_seconds is not None:
        update["duration_seconds"] = duration_seconds

    try:
        supabase_admin.table("call_history").update(update).eq(
            "room_id", room_id
        ).is_("ended_at", "null").execute()
    except Exception:
        pass

    # Remove Redis state for both users
    await redis_client.delete_user_room(user_id)
    if partner_id:
        await redis_client.delete_user_room(partner_id)
        await redis_client.delete_room_partners(room_id, user_id, partner_id)
        await notify_user(partner_id, {"type": "call_ended", "reason": notify_partner_reason})
    else:
        # Partner key already gone — still clean up our side
        await redis_client.delete_room_partners(room_id, user_id, user_id)


# ── Call-timer task (fires when 30 min elapses) ──────────────────────────────

async def call_timer_task(room_id: str, user_a: str, user_b: str):
    await asyncio.sleep(CALL_DURATION)
    now = datetime.now(timezone.utc)

    try:
        supabase_admin.table("call_history").update(
            {
                "ended_at": now.isoformat(),
                "duration_seconds": CALL_DURATION,
                "ended_by": "timer",
            }
        ).eq("room_id", room_id).is_("ended_at", "null").execute()
    except Exception:
        pass

    await notify_user(user_a, {"type": "call_ended", "reason": "timer"})
    await notify_user(user_b, {"type": "call_ended", "reason": "timer"})

    await redis_client.delete_user_room(user_a)
    await redis_client.delete_user_room(user_b)
    await redis_client.delete_room_partners(room_id, user_a, user_b)
    call_timers.pop(room_id, None)


# ── Matching logic ────────────────────────────────────────────────────────────

async def do_match(user_id: str, ws: WebSocket):
    matched_id = await redis_client.find_match(user_id)

    if not matched_id:
        # Timeout with no partner found; tell client to keep waiting
        if user_id in active_connections:
            await send_json(ws, {"type": "waiting"})
        return

    # Verify the initiating user is still connected
    if user_id not in active_connections:
        await redis_client.add_to_queue(matched_id)
        return

    # Verify the matched user is still connected (they may have disconnected
    # while sitting in the brpop queue)
    if matched_id not in active_connections:
        # Re-queue ourselves and signal that we're still waiting
        await redis_client.add_to_queue(user_id)
        await send_json(ws, {"type": "waiting"})
        return

    channel_name = str(uuid4())

    token_a, uid_a = generate_token(
        channel_name, user_id, settings.agora_app_id, settings.agora_app_certificate
    )
    token_b, uid_b = generate_token(
        channel_name, matched_id, settings.agora_app_id, settings.agora_app_certificate
    )

    try:
        profile_a = (
            supabase_admin.table("profiles")
            .select("name,age,gender,avatar_url")
            .eq("id", user_id)
            .single()
            .execute()
            .data
        )
        profile_b = (
            supabase_admin.table("profiles")
            .select("name,age,gender,avatar_url")
            .eq("id", matched_id)
            .single()
            .execute()
            .data
        )
    except Exception:
        profile_a = {"name": "User"}
        profile_b = {"name": "User"}

    # Store room state before notifying clients
    await redis_client.set_user_room(user_id, channel_name)
    await redis_client.set_user_room(matched_id, channel_name)
    await redis_client.set_partner(channel_name, user_id, matched_id)

    now = datetime.now(timezone.utc)
    try:
        supabase_admin.table("call_history").insert(
            {
                "user_a": user_id,
                "user_b": matched_id,
                "room_id": channel_name,
                "started_at": now.isoformat(),
            }
        ).execute()
    except Exception:
        pass

    # Notify both users
    await send_json(
        ws,
        {
            "type": "matched",
            "channel_name": channel_name,
            "agora_token": token_a,
            "agora_uid": uid_a,
            "agora_app_id": settings.agora_app_id,
            "partner_id": matched_id,
            "partner": {
                "name": profile_b.get("name", "User"),
                "age": profile_b.get("age"),
                "gender": profile_b.get("gender"),
                "avatar_url": profile_b.get("avatar_url"),
            },
        },
    )

    partner_ws = active_connections.get(matched_id)
    if partner_ws:
        await send_json(
            partner_ws,
            {
                "type": "matched",
                "channel_name": channel_name,
                "agora_token": token_b,
                "agora_uid": uid_b,
                "agora_app_id": settings.agora_app_id,
                "partner_id": user_id,
                "partner": {
                    "name": profile_a.get("name", "User"),
                    "age": profile_a.get("age"),
                    "gender": profile_a.get("gender"),
                    "avatar_url": profile_a.get("avatar_url"),
                },
            },
        )

    timer = asyncio.create_task(call_timer_task(channel_name, user_id, matched_id))
    call_timers[channel_name] = timer


# ── WebSocket endpoint ────────────────────────────────────────────────────────

@router.websocket("/ws/match")
async def websocket_match(websocket: WebSocket, token: str = Query(...)):
    # Authenticate before accepting
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            await websocket.close(code=4001)
            return
    except Exception:
        await websocket.close(code=4001)
        return

    user_id = str(response.user.id)
    await websocket.accept()
    active_connections[user_id] = websocket

    await send_json(websocket, {"type": "waiting"})
    await redis_client.add_to_queue(user_id)  # lrem+lpush pipeline; deduped

    match_task = asyncio.create_task(do_match(user_id, websocket))

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue

            msg_type = msg.get("type")

            # ── cancel: user tapped Cancel while waiting ──────────────────────
            if msg_type == "cancel":
                match_task.cancel()
                await redis_client.remove_from_queue(user_id)
                await send_json(websocket, {"type": "call_ended", "reason": "manual"})
                await _close_ws(websocket)
                break

            # ── end_call: user tapped End Call during a live call ─────────────
            elif msg_type == "end_call":
                room_id = await redis_client.get_user_room(user_id)
                if room_id:
                    await _full_room_cleanup(
                        room_id=room_id,
                        user_id=user_id,
                        ended_by="user",
                        notify_partner_reason="partner_left",
                    )
                await send_json(websocket, {"type": "call_ended", "reason": "manual"})
                await _close_ws(websocket)
                break

            # ── ping: keep-alive ───────────────────────────────────────────────
            elif msg_type == "ping":
                await send_json(websocket, {"type": "pong"})

    except WebSocketDisconnect:
        pass

    finally:
        # Cancel any in-flight matching attempt
        match_task.cancel()
        active_connections.pop(user_id, None)

        room_id = await redis_client.get_user_room(user_id)
        if room_id:
            # User disconnected during an active call
            await _full_room_cleanup(
                room_id=room_id,
                user_id=user_id,
                ended_by="disconnect",
                notify_partner_reason="partner_left",
            )
        else:
            # User disconnected while still waiting in queue (or after clean break)
            await redis_client.remove_from_queue(user_id)
