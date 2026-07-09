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
from datetime import datetime, timedelta, timezone

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from routers import ai_partner, auth, call, match, moderation, notify, profile, room
from services import redis_client
from services.supabase_client import supabase_admin
from services.supabase_realtime import broadcast

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# How often the expiry scanner wakes up.  15 s gives <= 15 s overrun on
# call duration in the worst case, which is fine for a 30-min ceiling.
_EXPIRY_SCAN_INTERVAL_S = 15

# Room expiry scanner interval: 5 minutes is granular enough for 2-hour rooms.
_ROOM_EXPIRY_SCAN_INTERVAL_S = 300


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


_IST = timezone(timedelta(hours=5, minutes=30))


async def peak_hour_notifier():
    """Every day at 7:30 PM and 8:00 PM IST, blast a reminder to all users."""
    from services import notification_service

    # (hour, minute, title)
    _SLOTS = [
        (19, 30, "⏰ Peak hours start in 30 mins! Get ready to practice"),
        (20,  0, "🌟 Peak hours are live! Find a partner now"),
    ]

    while True:
        now_ist = datetime.now(_IST)
        # Find the next upcoming slot
        next_target = None
        next_title = None
        for hour, minute, title in _SLOTS:
            candidate = now_ist.replace(hour=hour, minute=minute, second=0, microsecond=0)
            if now_ist >= candidate:
                candidate += timedelta(days=1)
            if next_target is None or candidate < next_target:
                next_target = candidate
                next_title = title

        wait = (next_target - now_ist).total_seconds()
        logger.info("Peak hour notifier: next blast '%s' in %.0f s", next_title, wait)
        await asyncio.sleep(wait)
        await notification_service.send_peak_hour_blast(next_title)


async def streak_warning_notifier():
    """Every day at 6:00 PM IST, warn users whose streak is about to break."""
    from services import notification_service
    while True:
        now_ist = datetime.now(_IST)
        target = now_ist.replace(hour=18, minute=0, second=0, microsecond=0)
        if now_ist >= target:
            target += timedelta(days=1)
        wait = (target - now_ist).total_seconds()
        logger.info("Streak warning notifier: next run in %.0f s", wait)
        await asyncio.sleep(wait)
        await notification_service.send_streak_warning_blast()


async def message_cleanup():
    """Deletes expired messages every hour."""
    while True:
        await asyncio.sleep(3600)
        try:
            supabase_admin.rpc("delete_expired_messages").execute()
            logger.info("message cleanup: expired messages deleted")
        except Exception as e:
            logger.warning("message cleanup failed: %r", e)


async def room_expiry_scanner():
    """
    Forever-loop: every _ROOM_EXPIRY_SCAN_INTERVAL_S, find rooms whose
    expires_at has passed and close them.  Safe to run on multiple backend
    instances because the Supabase UPDATE is gated on status != 'ended'.
    """
    while True:
        await asyncio.sleep(_ROOM_EXPIRY_SCAN_INTERVAL_S)
        try:
            await room.expire_old_rooms()
        except Exception as e:
            logger.warning("room expiry scanner tick failed: %r", e)


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
    msg_cleaner = asyncio.create_task(message_cleanup())
    room_expiry = asyncio.create_task(room_expiry_scanner())
    peak_notifier = asyncio.create_task(peak_hour_notifier())
    streak_notifier = asyncio.create_task(streak_warning_notifier())
    try:
        yield
    finally:
        scanner.cancel()
        msg_cleaner.cancel()
        room_expiry.cancel()
        peak_notifier.cancel()
        streak_notifier.cancel()
        try:
            await asyncio.gather(scanner, msg_cleaner, room_expiry, peak_notifier, streak_notifier, return_exceptions=True)
        except (asyncio.CancelledError, Exception):
            pass
        await redis_client.close_redis()


app = FastAPI(title="Tark Peer API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

app.include_router(auth.router)
app.include_router(profile.router)
app.include_router(call.router)
app.include_router(match.router)
app.include_router(room.router)
app.include_router(notify.router)
app.include_router(moderation.router)
app.include_router(ai_partner.router)


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
