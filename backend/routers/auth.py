from fastapi import APIRouter, HTTPException, Header
from services.supabase_client import supabase_admin

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/verify")
async def verify_token(authorization: str = Header(...)):
    token = authorization.replace("Bearer ", "")
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        user = response.user
        profile_resp = supabase_admin.table("profiles").select("*").eq("id", str(user.id)).single().execute()
        return {"user": {"id": str(user.id), "email": user.email}, "profile": profile_resp.data}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=401, detail=str(e))
