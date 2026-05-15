from fastapi import APIRouter, HTTPException, Header, Depends
from models.schemas import UpdateProfile
from services.supabase_client import supabase_admin
from core.dependencies import get_current_user

router = APIRouter(prefix="/profile", tags=["profile"])


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
    update_data["updated_at"] = "now()"
    resp = supabase_admin.table("profiles").update(update_data).eq("id", user["id"]).execute()
    return resp.data[0] if resp.data else {}


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
