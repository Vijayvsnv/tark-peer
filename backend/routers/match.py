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

# Track active WebSocket connections: user_id -> WebSocket
active_connections: dict[str, WebSocket] = {}
# Track active call timers: room_id -> asyncio.Task
call_timers: dict[str, asyncio.Task] = {}

CALL_DURATION = 180


async def send_json(ws: WebSocket, data: dict):
    try:
        await ws.send_text(json.dumps(data))
    except Exception:
        pass


async def notify_user(user_id: str, data: dict):
    ws = active_connections.get(user_id)
    if ws:
        await send_json(ws, data)


async def call_timer_task(room_id: str, user_a: str, user_b: str):
    await asyncio.sleep(CALL_DURATION)
    now = datetime.now(timezone.utc)
    try:
        supabase_admin.table("call_history").update({
            "ended_at": now.isoformat(),
            "duration_seconds": CALL_DURATION,
            "ended_by": "timer",
        }).eq("room_id", room_id).is_("ended_at", "null").execute()
    except Exception:
        pass

    supabase_admin.table("profiles").rpc("increment_calls", {"uid": user_a}).execute() if False else None

    await notify_user(user_a, {"type": "call_ended", "reason": "timer"})
    await notify_user(user_b, {"type": "call_ended", "reason": "timer"})

    await redis_client.delete_user_room(user_a)
    await redis_client.delete_user_room(user_b)
    await redis_client.delete_room_partners(room_id, user_a, user_b)
    call_timers.pop(room_id, None)


async def do_match(user_id: str, ws: WebSocket):
    matched_id = await redis_client.find_match(user_id)

    if not matched_id:
        if user_id in active_connections:
            await send_json(ws, {"type": "waiting"})
        return

    if user_id not in active_connections:
        await redis_client.add_to_queue(matched_id)
        return

    channel_name = str(uuid4())

    token_a, uid_a = generate_token(channel_name, user_id, settings.agora_app_id, settings.agora_app_certificate)
    token_b, uid_b = generate_token(channel_name, matched_id, settings.agora_app_id, settings.agora_app_certificate)

    try:
        profile_a = supabase_admin.table("profiles").select("name,age,gender,avatar_url").eq("id", user_id).single().execute().data
        profile_b = supabase_admin.table("profiles").select("name,age,gender,avatar_url").eq("id", matched_id).single().execute().data
    except Exception:
        profile_a = {"name": "User"}
        profile_b = {"name": "User"}

    await redis_client.set_user_room(user_id, channel_name)
    await redis_client.set_user_room(matched_id, channel_name)
    await redis_client.set_partner(channel_name, user_id, matched_id)

    now = datetime.now(timezone.utc)
    try:
        supabase_admin.table("call_history").insert({
            "user_a": user_id,
            "user_b": matched_id,
            "room_id": channel_name,
            "started_at": now.isoformat(),
        }).execute()
    except Exception:
        pass

    await send_json(ws, {
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
    })

    partner_ws = active_connections.get(matched_id)
    if partner_ws:
        await send_json(partner_ws, {
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
        })

    timer = asyncio.create_task(call_timer_task(channel_name, user_id, matched_id))
    call_timers[channel_name] = timer


@router.websocket("/ws/match")
async def websocket_match(websocket: WebSocket, token: str = Query(...)):
    response = supabase_admin.auth.get_user(token)
    if not response or not response.user:
        await websocket.close(code=4001)
        return

    user_id = str(response.user.id)
    await websocket.accept()
    active_connections[user_id] = websocket

    await send_json(websocket, {"type": "waiting"})
    await redis_client.add_to_queue(user_id)

    match_task = asyncio.create_task(do_match(user_id, websocket))

    try:
        while True:
            raw = await websocket.receive_text()
            try:
                msg = json.loads(raw)
            except Exception:
                continue

            msg_type = msg.get("type")

            if msg_type == "cancel":
                match_task.cancel()
                await redis_client.remove_from_queue(user_id)
                await send_json(websocket, {"type": "call_ended", "reason": "manual"})
                break

            elif msg_type == "end_call":
                room_id = await redis_client.get_user_room(user_id)
                if room_id:
                    partner_id = await redis_client.get_partner(room_id, user_id)
                    timer = call_timers.pop(room_id, None)
                    if timer:
                        timer.cancel()

                    now = datetime.now(timezone.utc)
                    try:
                        supabase_admin.table("call_history").update({
                            "ended_at": now.isoformat(),
                            "ended_by": "user_a",
                        }).eq("room_id", room_id).is_("ended_at", "null").execute()
                    except Exception:
                        pass

                    await redis_client.delete_user_room(user_id)
                    if partner_id:
                        await redis_client.delete_user_room(partner_id)
                        await redis_client.delete_room_partners(room_id, user_id, partner_id)
                        await notify_user(partner_id, {"type": "call_ended", "reason": "partner_left"})

                await send_json(websocket, {"type": "call_ended", "reason": "manual"})
                break

            elif msg_type == "ping":
                await send_json(websocket, {"type": "pong"})

    except WebSocketDisconnect:
        pass
    finally:
        match_task.cancel()
        active_connections.pop(user_id, None)

        room_id = await redis_client.get_user_room(user_id)
        if room_id:
            partner_id = await redis_client.get_partner(room_id, user_id)
            timer = call_timers.pop(room_id, None)
            if timer:
                timer.cancel()

            now = datetime.now(timezone.utc)
            try:
                supabase_admin.table("call_history").update({
                    "ended_at": now.isoformat(),
                    "ended_by": "disconnect",
                }).eq("room_id", room_id).is_("ended_at", "null").execute()
            except Exception:
                pass

            await redis_client.delete_user_room(user_id)
            if partner_id:
                await redis_client.delete_user_room(partner_id)
                await redis_client.delete_room_partners(room_id, user_id, partner_id)
                await notify_user(partner_id, {"type": "call_ended", "reason": "partner_left"})
        else:
            await redis_client.remove_from_queue(user_id)
