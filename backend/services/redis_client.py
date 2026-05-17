"""
Redis layer for matchmaking + call lifecycle.

All state required to scale horizontally lives here.  The backend processes
themselves are stateless; any number of FastAPI instances can read/write the
same Redis and reach a consistent decision.

Keys / structures:

    waiting_queue              ZSET   user_id -> score = unix_ts (insertion time)
    user_room:{user_id}        STR    channel_name (TTL = ROOM_TTL)
    partner:{ch}:{user_id}     STR    partner_user_id (TTL = ROOM_TTL)
    call_info:{ch}             HASH   {user_a, user_b, started_at, end_time}
    active_rooms               ZSET   channel_name -> score = end_time (unix ts)

`waiting_queue` uses a sorted set so each entry is identified by user_id;
duplicates are impossible and we can atomically drop stale entries by score
(insertion timestamp older than QUEUE_TTL seconds).

`find_partner` is implemented as a single Lua script so two concurrent
callers can never both claim the same partner.
"""

import time
from typing import Optional

import redis.asyncio as aioredis

from core.config import settings

redis: aioredis.Redis = None  # set by init_redis()

# ── TTLs ──────────────────────────────────────────────────────────────────────

CALL_DURATION = 1800              # 30 min — max call length
ROOM_TTL = CALL_DURATION + 300    # 35 min — Redis safety net on call state
QUEUE_TTL = 60                    # 60 s — drop waiters that stop heartbeating

WAITING_QUEUE_KEY = "waiting_queue"
ACTIVE_ROOMS_KEY = "active_rooms"


# ── Connection lifecycle ─────────────────────────────────────────────────────

async def init_redis():
    global redis
    redis = aioredis.from_url(
        settings.redis_url,
        decode_responses=True,
        socket_connect_timeout=5,
    )


async def close_redis():
    if redis:
        await redis.close()


async def clear_stale_state():
    """Wipe transient state at process start. Safe to run any time."""
    await redis.delete(WAITING_QUEUE_KEY, ACTIVE_ROOMS_KEY)
    async for key in redis.scan_iter("user_room:*"):
        await redis.delete(key)
    async for key in redis.scan_iter("partner:*"):
        await redis.delete(key)
    async for key in redis.scan_iter("call_info:*"):
        await redis.delete(key)


# ── Queue: add / remove ──────────────────────────────────────────────────────

async def add_to_queue(user_id: str):
    """Register user as waiting. Score is insertion time so we can age out
    entries from clients that disappeared without saying goodbye."""
    await redis.zadd(WAITING_QUEUE_KEY, {user_id: time.time()})


async def remove_from_queue(user_id: str):
    await redis.zrem(WAITING_QUEUE_KEY, user_id)


async def is_in_queue(user_id: str) -> bool:
    return (await redis.zscore(WAITING_QUEUE_KEY, user_id)) is not None


# ── Atomic find_partner (Lua) ────────────────────────────────────────────────
#
# Removes stale waiters, finds the oldest entry that isn't us, atomically
# removes BOTH that entry and us, and returns the partner id.  Returns nil
# if no eligible partner exists.
#
# Running this as a script is the only way to guarantee that two simultaneous
# callers never pop the same partner from different FastAPI instances.

_FIND_PARTNER_LUA = """
local me = ARGV[1]
local stale_before = tonumber(ARGV[2])

-- Drop entries older than (now - QUEUE_TTL); clients are expected to refresh.
redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', stale_before)

local entries = redis.call('ZRANGE', KEYS[1], 0, -1)
for _, entry in ipairs(entries) do
    if entry ~= me then
        redis.call('ZREM', KEYS[1], entry)
        redis.call('ZREM', KEYS[1], me)
        return entry
    end
end
return nil
"""

_find_partner_sha: Optional[str] = None


async def _load_scripts():
    """Pre-load Lua scripts so we can EVALSHA instead of re-uploading on hot path."""
    global _find_partner_sha
    _find_partner_sha = await redis.script_load(_FIND_PARTNER_LUA)


async def find_partner(user_id: str) -> Optional[str]:
    """Atomically pair `user_id` with another waiter, removing both from queue.
    Returns the partner's user_id, or None if nobody else is waiting."""
    if _find_partner_sha is None:
        await _load_scripts()
    stale_before = time.time() - QUEUE_TTL
    try:
        result = await redis.evalsha(
            _find_partner_sha, 1, WAITING_QUEUE_KEY, user_id, str(stale_before)
        )
    except aioredis.ResponseError:
        # Script was flushed (e.g. SCRIPT FLUSH on Redis restart) — reload + retry.
        await _load_scripts()
        result = await redis.evalsha(
            _find_partner_sha, 1, WAITING_QUEUE_KEY, user_id, str(stale_before)
        )
    return result  # str or None (decode_responses=True)


# ── Room / partner state ─────────────────────────────────────────────────────

async def set_user_room(user_id: str, channel_name: str):
    await redis.set(f"user_room:{user_id}", channel_name, ex=ROOM_TTL)


async def get_user_room(user_id: str) -> Optional[str]:
    return await redis.get(f"user_room:{user_id}")


async def delete_user_room(user_id: str):
    await redis.delete(f"user_room:{user_id}")


async def set_room_partners(channel_name: str, user_a: str, user_b: str):
    async with redis.pipeline(transaction=True) as pipe:
        pipe.set(f"partner:{channel_name}:{user_a}", user_b, ex=ROOM_TTL)
        pipe.set(f"partner:{channel_name}:{user_b}", user_a, ex=ROOM_TTL)
        await pipe.execute()


async def get_partner(channel_name: str, user_id: str) -> Optional[str]:
    return await redis.get(f"partner:{channel_name}:{user_id}")


async def delete_room_partners(channel_name: str, user_a: str, user_b: str):
    async with redis.pipeline(transaction=True) as pipe:
        if user_a:
            pipe.delete(f"partner:{channel_name}:{user_a}")
        if user_b:
            pipe.delete(f"partner:{channel_name}:{user_b}")
        await pipe.execute()


# ── Active rooms tracking (used by call_expiry_scanner) ──────────────────────

async def register_active_room(
    channel_name: str, user_a: str, user_b: str, started_at: float, end_time: float
):
    """
    Record a freshly created call so the expiry scanner can clean it up at
    end_time even if every client disappears.
    """
    async with redis.pipeline(transaction=True) as pipe:
        pipe.hset(
            f"call_info:{channel_name}",
            mapping={
                "user_a": user_a,
                "user_b": user_b,
                "started_at": str(started_at),
                "end_time": str(end_time),
            },
        )
        pipe.expire(f"call_info:{channel_name}", ROOM_TTL)
        pipe.zadd(ACTIVE_ROOMS_KEY, {channel_name: end_time})
        await pipe.execute()


async def deregister_active_room(channel_name: str):
    """Call ended cleanly — drop the call_info hash and active_rooms entry."""
    async with redis.pipeline(transaction=True) as pipe:
        pipe.delete(f"call_info:{channel_name}")
        pipe.zrem(ACTIVE_ROOMS_KEY, channel_name)
        await pipe.execute()


async def get_call_info(channel_name: str) -> Optional[dict]:
    info = await redis.hgetall(f"call_info:{channel_name}")
    return info or None


# Lua: atomically claim all rooms whose end_time has passed.  Returns the list
# of channel_names and removes them from active_rooms in one shot so two
# scanner instances never both broadcast call_ended for the same room.
_CLAIM_EXPIRED_LUA = """
local now = tonumber(ARGV[1])
local expired = redis.call('ZRANGEBYSCORE', KEYS[1], '-inf', now)
if #expired > 0 then
    redis.call('ZREMRANGEBYSCORE', KEYS[1], '-inf', now)
end
return expired
"""

_claim_expired_sha: Optional[str] = None


async def claim_expired_rooms(now: float) -> list[str]:
    """
    Atomically pull and remove every active_room whose end_time <= now.
    Caller is then responsible for broadcasting call_ended and cleaning state.
    """
    global _claim_expired_sha
    if _claim_expired_sha is None:
        _claim_expired_sha = await redis.script_load(_CLAIM_EXPIRED_LUA)
    try:
        result = await redis.evalsha(
            _claim_expired_sha, 1, ACTIVE_ROOMS_KEY, str(now)
        )
    except aioredis.ResponseError:
        _claim_expired_sha = await redis.script_load(_CLAIM_EXPIRED_LUA)
        result = await redis.evalsha(
            _claim_expired_sha, 1, ACTIVE_ROOMS_KEY, str(now)
        )
    return list(result) if result else []
