from fastapi import APIRouter, HTTPException, Header
from datetime import datetime, timezone
from services.supabase_client import supabase_admin
from services import redis_client
from models.schemas import CallEndEvent

router = APIRouter(prefix="/call", tags=["call"])


async def get_user(token: str) -> dict:
    try:
        response = supabase_admin.auth.get_user(token)
        if not response or not response.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": str(response.user.id)}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


@router.post("/end")
async def end_call(data: CallEndEvent, authorization: str = Header(...)):
    token = authorization.replace("Bearer ", "")
    user = await get_user(token)
    user_id = user["id"]

    partner_id = await redis_client.get_partner(data.channel_name, user_id)

    now = datetime.now(timezone.utc)
    supabase_admin.table("call_history").update({
        "ended_at": now.isoformat(),
        "ended_by": f"user_a" if partner_id else "disconnect",
    }).eq("room_id", data.channel_name).is_("ended_at", "null").execute()

    await redis_client.delete_user_room(user_id)
    if partner_id:
        await redis_client.delete_user_room(partner_id)
    await redis_client.delete_room_partners(data.channel_name, user_id, partner_id or "")

    return {"status": "ok"}
