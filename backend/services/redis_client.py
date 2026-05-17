import redis.asyncio as aioredis
from core.config import settings

redis: aioredis.Redis = None

# Must be longer than max call duration (1800 s) so keys never expire mid-call
ROOM_TTL = 2100  # 35 minutes
QUEUE_WAIT_TIMEOUT = 30  # brpop timeout in seconds


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
    """
    Called once on startup.  Removes any leftover keys from a previous
    server instance so no stale data blocks future matches.
    """
    await redis.delete("waiting_queue")
    async for key in redis.scan_iter("user_room:*"):
        await redis.delete(key)
    async for key in redis.scan_iter("partner:*"):
        await redis.delete(key)


# ── Queue helpers ────────────────────────────────────────────────────────────

async def add_to_queue(user_id: str):
    """
    Remove any previous copy of this user then push to the left (head).
    Pipeline makes both ops atomic from Redis's perspective.
    """
    async with redis.pipeline(transaction=True) as pipe:
        pipe.lrem("waiting_queue", 0, user_id)
        pipe.lpush("waiting_queue", user_id)
        await pipe.execute()


async def find_match(user_id: str) -> str | None:
    """
    Blocking right-pop with QUEUE_WAIT_TIMEOUT seconds.
    If we pop ourselves (stale entry), push back to the *tail* (rpush)
    so we don't starve other waiters, then signal 'no match yet'.
    """
    result = await redis.brpop("waiting_queue", timeout=QUEUE_WAIT_TIMEOUT)
    if not result:
        return None
    _, matched_id = result
    if matched_id == user_id:
        await redis.rpush("waiting_queue", user_id)
        return None
    return matched_id


async def remove_from_queue(user_id: str):
    await redis.lrem("waiting_queue", 0, user_id)


# ── Room / partner state ─────────────────────────────────────────────────────

async def set_user_room(user_id: str, room_id: str):
    await redis.set(f"user_room:{user_id}", room_id, ex=ROOM_TTL)


async def get_user_room(user_id: str) -> str | None:
    return await redis.get(f"user_room:{user_id}")


async def delete_user_room(user_id: str):
    await redis.delete(f"user_room:{user_id}")


async def set_partner(room_id: str, user_id_a: str, user_id_b: str):
    async with redis.pipeline(transaction=True) as pipe:
        pipe.set(f"partner:{room_id}:{user_id_a}", user_id_b, ex=ROOM_TTL)
        pipe.set(f"partner:{room_id}:{user_id_b}", user_id_a, ex=ROOM_TTL)
        await pipe.execute()


async def get_partner(room_id: str, user_id: str) -> str | None:
    return await redis.get(f"partner:{room_id}:{user_id}")


async def delete_room_partners(room_id: str, user_id_a: str, user_id_b: str):
    async with redis.pipeline(transaction=True) as pipe:
        pipe.delete(f"partner:{room_id}:{user_id_a}")
        pipe.delete(f"partner:{room_id}:{user_id_b}")
        await pipe.execute()
