"""
FastAPI entry point.

Lifespan responsibilities:
  * boot Redis
  * scrub leftover keys from any previous process
  * launch the call-expiry scanner (closes calls that exceed CALL_DURATION,
    even if every client crashed and nobody called /call/end)
"""

import asyncio
import logging
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import auth, call, match, profile
from services import redis_client
from services.supabase_client import supabase_admin
from services.supabase_realtime import broadcast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# How often the expiry scanner wakes up.  15 s gives <= 15 s overrun on
# call duration in the worst case, which is fine for a 30-min ceiling.
_EXPIRY_SCAN_INTERVAL_S = 15


async def _expire_one_room(channel_name: str):
    """
    Single-room cleanup: broadcast the call_ended event, close call_history,
    drop Redis state.  Safe to call even if some pieces are already missing.
    """
    info = await redis_client.get_call_info(channel_name) or {}
    user_a = info.get("user_a") or ""
    user_b = info.get("user_b") or ""

    # Broadcast first; if Realtime is down we still try to clean state below.
    await broadcast(
        f"room:{channel_name}",
        "call_ended",
        {"reason": "timer"},
    )

    now_iso = datetime.now(timezone.utc).isoformat()
    try:
        supabase_admin.table("call_history").update(
            {
                "ended_at": now_iso,
                "ended_by": "timer",
                "duration_seconds": redis_client.CALL_DURATION,
            }
        ).eq("room_id", channel_name).is_("ended_at", "null").execute()
    except Exception as e:
        logger.warning("call_history close (timer) failed: %r", e)

    if user_a:
        await redis_client.delete_user_room(user_a)
    if user_b:
        await redis_client.delete_user_room(user_b)
    await redis_client.delete_room_partners(channel_name, user_a, user_b)
    await redis_client.deregister_active_room(channel_name)


async def call_expiry_scanner():
    """
    Forever-loop: every _EXPIRY_SCAN_INTERVAL_S, atomically claim every room
    whose end_time has passed and expire it.  Atomic claim means it's safe
    to run this loop on every backend instance — only one instance will get
    each room.
    """
    while True:
        try:
            now = time.time()
            expired = await redis_client.claim_expired_rooms(now)
            if expired:
                logger.info("expiry scanner: closing %d room(s)", len(expired))
                # Expire in parallel — they don't depend on each other.
                await asyncio.gather(
                    *[_expire_one_room(ch) for ch in expired],
                    return_exceptions=True,
                )
        except Exception as e:
            logger.warning("expiry scanner tick failed: %r", e)
        await asyncio.sleep(_EXPIRY_SCAN_INTERVAL_S)


@asynccontextmanager
async def lifespan(app: FastAPI):
    await redis_client.init_redis()
    await redis_client.clear_stale_state()
    scanner = asyncio.create_task(call_expiry_scanner())
    try:
        yield
    finally:
        scanner.cancel()
        try:
            await scanner
        except (asyncio.CancelledError, Exception):
            pass
        await redis_client.close_redis()


app = FastAPI(title="Tark Peer API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(profile.router)
app.include_router(call.router)
app.include_router(match.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "tark-peer"}


@app.get("/stats")
async def get_stats():
    """
    Rough live counters.

    `online` is now read from Redis (waiters + active room participants), not
    from a per-process in-memory dict, so it gives a consistent answer no
    matter how many backend instances are running.
    """
    try:
        resp = supabase_admin.table("profiles").select("id", count="exact").execute()
        total = resp.count or 0
    except Exception:
        total = 0

    try:
        waiting = await redis_client.redis.zcard(redis_client.WAITING_QUEUE_KEY)
    except Exception:
        waiting = 0
    try:
        in_call = await redis_client.redis.zcard(redis_client.ACTIVE_ROOMS_KEY)
    except Exception:
        in_call = 0

    online = int(waiting) + int(in_call) * 2  # each active room = 2 users
    return {
        "total_users": total,
        "online": online,
        "waiting": int(waiting),
        "active_calls": int(in_call),
        "offline": max(0, total - online),
    }
