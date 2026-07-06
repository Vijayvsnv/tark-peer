import asyncio
import logging

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from services import notification_service
from services.supabase_client import supabase_admin

router = APIRouter(prefix="/notify", tags=["notify"])
logger = logging.getLogger(__name__)


class FriendRequestBody(BaseModel):
    receiver_id: str


class FriendAcceptedBody(BaseModel):
    requester_id: str


class MessageBody(BaseModel):
    receiver_id: str
    preview: str


async def _get_user(token: str) -> dict:
    try:
        resp = supabase_admin.auth.get_user(token)
        if not resp or not resp.user:
            raise HTTPException(status_code=401, detail="Invalid token")
        return {"id": str(resp.user.id)}
    except HTTPException:
        raise
    except Exception:
        raise HTTPException(status_code=401, detail="Invalid token")


async def _get_name(user_id: str) -> str:
    try:
        resp = (
            supabase_admin.table("profiles")
            .select("name")
            .eq("id", user_id)
            .single()
            .execute()
        )
        return (resp.data or {}).get("name") or "Someone"
    except Exception:
        return "Someone"


@router.post("/friend-request")
async def notify_friend_request(body: FriendRequestBody, authorization: str = Header(...)):
    """Notify receiver that someone sent them a friend request."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    name = await _get_name(user["id"])

    asyncio.create_task(
        notification_service.send_to_user(
            body.receiver_id,
            title=f"👋 {name} sent you a friend request",
            data={"type": "friend_request", "sender_id": user["id"]},
        )
    )
    return {"status": "ok"}


@router.post("/friend-accepted")
async def notify_friend_accepted(body: FriendAcceptedBody, authorization: str = Header(...)):
    """Notify the original requester that their friend request was accepted."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    name = await _get_name(user["id"])

    asyncio.create_task(
        notification_service.send_to_user(
            body.requester_id,
            title=f"👥 {name} accepted your friend request!",
            data={"type": "friend_accepted", "friend_id": user["id"]},
        )
    )
    return {"status": "ok"}


@router.post("/message")
async def notify_message(body: MessageBody, authorization: str = Header(...)):
    """Notify receiver that they got a new chat message."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    name = await _get_name(user["id"])

    asyncio.create_task(
        notification_service.send_to_user(
            body.receiver_id,
            title=f"💬 New message from {name}",
            data={"type": "message", "sender_id": user["id"]},
        )
    )
    return {"status": "ok"}
