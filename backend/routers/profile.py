import logging

from fastapi import APIRouter, HTTPException, Header, Depends
from models.schemas import UpdateProfile
from services import redis_client
from services.supabase_client import supabase_admin
from core.dependencies import get_current_user

router = APIRouter(prefix="/profile", tags=["profile"])
logger = logging.getLogger(__name__)


def auth_header(authorization: str = Header(...)) -> str:
    return authorization.replace("Bearer ", "")


@router.get("/me")
async def get_my_profile(token: str = Depends(auth_header)):
    user = await get_current_user_from_token(token)
    resp = supabase_admin.table("profiles").select("*").eq("id", user["id"]).single().execute()
    if not resp.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return resp.data


@router.put("/me")
async def update_my_profile(data: UpdateProfile, token: str = Depends(auth_header)):
    user = await get_current_user_from_token(token)
    update_data = {k: v for k, v in data.model_dump().items() if v is not None}
    if not update_data:
        raise HTTPException(status_code=400, detail="No fields to update")
    if "age" in update_data and update_data["age"] < 18:
        raise HTTPException(status_code=422, detail="You must be 18 or older to use Tark Peer")
    update_data["updated_at"] = "now()"
    resp = supabase_admin.table("profiles").update(update_data).eq("id", user["id"]).execute()
    return resp.data[0] if resp.data else {}


@router.delete("/me")
async def delete_my_account(token: str = Depends(auth_header)):
    """
    Permanently deletes the caller's account and all associated data.
    Each deletion step is wrapped individually so one failure does not abort
    the rest — partial cleanup is always better than aborting mid-delete.
    """
    user = await get_current_user_from_token(token)
    user_id = user["id"]

    def _try(label: str, fn):
        try:
            fn()
        except Exception as e:
            logger.warning("account deletion step '%s' failed for %s: %r", label, user_id, e)

    _try("messages", lambda: supabase_admin.table("messages").delete().or_(
        f"sender_id.eq.{user_id},receiver_id.eq.{user_id}"
    ).execute())

    _try("friendships", lambda: supabase_admin.table("friendships").delete().or_(
        f"requester_id.eq.{user_id},receiver_id.eq.{user_id}"
    ).execute())

    _try("call_ratings", lambda: supabase_admin.table("call_ratings").delete().or_(
        f"rater_id.eq.{user_id},rated_id.eq.{user_id}"
    ).execute())

    _try("blocks", lambda: supabase_admin.table("blocks").delete().or_(
        f"blocker_id.eq.{user_id},blocked_id.eq.{user_id}"
    ).execute())

    _try("reports_as_reporter", lambda: supabase_admin.table("reports").delete().eq(
        "reporter_id", user_id
    ).execute())

    _try("room_members", lambda: supabase_admin.table("room_members").delete().eq(
        "user_id", user_id
    ).execute())

    _try("user_presence", lambda: supabase_admin.table("user_presence").delete().eq(
        "user_id", user_id
    ).execute())

    _try("profile", lambda: supabase_admin.table("profiles").delete().eq(
        "id", user_id
    ).execute())

    _try("auth_user", lambda: supabase_admin.auth.admin.delete_user(user_id))

    try:
        await redis_client.redis.delete(f"user_room:{user_id}")
        await redis_client.redis.zrem(redis_client.WAITING_QUEUE_KEY, user_id)
        await redis_client.redis.delete(f"blockset:{user_id}")
        await redis_client.redis.delete(f"restricted:{user_id}")
    except Exception as e:
        logger.warning("Redis cleanup failed for %s: %r", user_id, e)

    return {"status": "deleted"}


@router.get("/history")
async def get_call_history(token: str = Depends(auth_header)):
    user = await get_current_user_from_token(token)
    resp = (
        supabase_admin.table("call_history")
        .select("*")
        .or_(f"user_a.eq.{user['id']},user_b.eq.{user['id']}")
        .order("started_at", desc=True)
        .limit(50)
        .execute()
    )
    return resp.data


@router.get("/{user_id}")
async def get_profile(user_id: str, token: str = Depends(auth_header)):
    await get_current_user_from_token(token)
    resp = (
        supabase_admin.table("profiles")
        .select("id,name,age,gender,bio,avatar_url,is_premium")
        .eq("id", user_id)
        .single()
        .execute()
    )
    if not resp.data:
        raise HTTPException(status_code=404, detail="Profile not found")
    return resp.data


async def get_current_user_from_token(token: str) -> dict:
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": str(response.user.id)}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")
