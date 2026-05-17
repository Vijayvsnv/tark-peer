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
            .select("name,age,gender,avatar_url")
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


@router.websocket("/ws/match")
async def websocket_match(websocket: WebSocket, token: str = Query(...)):
    """
    Hold a user in the waiting queue and try to pair them on a 1-second tick.

    The WebSocket is short-lived: it lives only until either (a) a partner is
    found, or (b) the client closes / cancels.  The backend keeps NO state
    about the resulting call inside this handler — that's all in Redis and
    delivered via Supabase Realtime.
    """
    user_id = await _authenticate(token)
    if not user_id:
        # 4001 = application-level "unauthorized" close code.
        await websocket.close(code=4001)
        return

    await websocket.accept()

    # Defensive: if this user already has a live room (e.g. they opened the
    # app fresh while still in a call), don't re-queue them; tell the client
    # to bounce to /call.
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

    await redis_client.add_to_queue(user_id)
    await _send_ws(websocket, {"type": "waiting"})

    _active_ws[user_id] = websocket
    matcher = asyncio.create_task(_matcher_loop(user_id, websocket))

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


async def _matcher_loop(user_id: str, websocket: WebSocket):
    """
    Background task per WS connection.  Polls Redis on a fixed cadence trying
    to claim a partner.  When successful, broadcasts the match via Realtime,
    pushes the same payload to our own WS as a fast-path, and exits.
    """
    try:
        while True:
            partner_id = await redis_client.find_partner(user_id)
            if not partner_id:
                await asyncio.sleep(_MATCH_POLL_INTERVAL_S)
                continue

            try:
                payload_me, payload_partner = await _create_match(user_id, partner_id)
            except Exception as e:
                # Anything went wrong building the match — return both users to
                # the queue and retry next tick.
                logger.exception("create_match failed: %r", e)
                await redis_client.add_to_queue(user_id)
                await redis_client.add_to_queue(partner_id)
                await asyncio.sleep(_MATCH_POLL_INTERVAL_S)
                continue

            # Notify both sides via Supabase Realtime (cross-instance safe).
            await asyncio.gather(
                broadcast(f"user:{user_id}", "matched", payload_me),
                broadcast(f"user:{partner_id}", "matched", payload_partner),
            )

            # Fast-path WS delivery for BOTH users (same-pod only).
            # Partner relies on Realtime if on a different pod — that's fine.
            # Deduplication on the Flutter side (_matchReceived flag) handles
            # the case where partner gets both WS + Realtime.
            partner_ws = _active_ws.get(partner_id)
            await asyncio.gather(
                _send_ws(websocket, {"type": "matched", **payload_me}),
                _send_ws(partner_ws, {"type": "matched", **payload_partner})
                if partner_ws else asyncio.sleep(0),
            )
            return

    except asyncio.CancelledError:
        # Caller cancelled — nothing else to do.  Queue removal happens in
        # the WS handler's finally block.
        raise
