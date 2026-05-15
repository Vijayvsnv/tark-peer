import redis.asyncio as aioredis
from core.config import settings

redis: aioredis.Redis = None


async def init_redis():
    global redis
    redis = aioredis.from_url(settings.redis_url, decode_responses=True)


async def close_redis():
    if redis:
        await redis.close()


async def add_to_queue(user_id: str):
    await redis.lpush("waiting_queue", user_id)


async def find_match(user_id: str) -> str | None:
    result = await redis.brpop("waiting_queue", timeout=30)
    if not result:
        return None
    _, matched_id = result
    if matched_id == user_id:
        await redis.lpush("waiting_queue", user_id)
        return None
    return matched_id


async def remove_from_queue(user_id: str):
    await redis.lrem("waiting_queue", 0, user_id)


async def set_user_room(user_id: str, room_id: str):
    await redis.set(f"user_room:{user_id}", room_id, ex=300)


async def get_user_room(user_id: str) -> str | None:
    return await redis.get(f"user_room:{user_id}")


async def delete_user_room(user_id: str):
    await redis.delete(f"user_room:{user_id}")


async def set_partner(room_id: str, user_id_a: str, user_id_b: str):
    await redis.set(f"partner:{room_id}:{user_id_a}", user_id_b, ex=300)
    await redis.set(f"partner:{room_id}:{user_id_b}", user_id_a, ex=300)


async def get_partner(room_id: str, user_id: str) -> str | None:
    return await redis.get(f"partner:{room_id}:{user_id}")


async def delete_room_partners(room_id: str, user_id_a: str, user_id_b: str):
    await redis.delete(f"partner:{room_id}:{user_id_a}")
    await redis.delete(f"partner:{room_id}:{user_id_b}")
