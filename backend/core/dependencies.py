from fastapi import HTTPException, Query
from services.supabase_client import supabase_admin


async def get_current_user(token: str = Query(...)) -> dict:
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": str(response.user.id), "email": response.user.email}
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid or expired token")


async def verify_token(token: str) -> dict:
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            return None
        return {"id": str(response.user.id), "email": response.user.email}
    except Exception:
        return None
