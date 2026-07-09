"""
AI Practice Partner endpoints.

Shivani is an on-demand AI English conversation partner.
No Agora, no call_history writes — voice pipeline is fully on-device
(STT + TTS) except the LLM call here.

Redis keys introduced:
    ai_daily:{user_id}:{YYYY-MM-DD IST}   STR   daily session count (TTL 26h)
    ai_session:{session_id}               HASH  {user_id, started_at}  (TTL 900s)
    ai_turns:{session_id}                 STR   turn counter (TTL 900s)
"""

import logging
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from core.config import settings
from services import gemini_service, redis_client
from services.supabase_client import supabase_admin

router = APIRouter(prefix="/ai", tags=["ai"])
logger = logging.getLogger(__name__)

_IST = timezone(timedelta(hours=5, minutes=30))

AI_DAILY_FREE_LIMIT = 2
AI_MAX_CALL_SECONDS = 600   # 10 min
AI_SESSION_TTL = 900        # 15 min hard ceiling
AI_MAX_TURNS = 30
AI_MAX_HISTORY_PAIRS = 8
AI_FALLBACK_REPLY = "Sorry, I missed that. Can you say it again?"


# ── Auth helper (same pattern as other routers) ───────────────────────────────

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


def _today_ist() -> str:
    return datetime.now(_IST).strftime("%Y-%m-%d")


# ── Pydantic models ───────────────────────────────────────────────────────────

class ChatBody(BaseModel):
    session_id: str
    user_text: str
    history: list[dict] = []


class EndBody(BaseModel):
    session_id: str
    transcript: list[dict] = []
    duration_seconds: int = 0


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/start")
async def start_session(authorization: str = Header(...)):
    """Begin an AI practice session. Enforces daily free-tier cap."""
    if not settings.gemini_api_key:
        raise HTTPException(status_code=503, detail="AI partner unavailable")

    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)
    user_id = user["id"]

    daily_key = f"ai_daily:{user_id}:{_today_ist()}"
    count = await redis_client.redis.get(daily_key)
    used = int(count) if count else 0

    if used >= AI_DAILY_FREE_LIMIT:
        raise HTTPException(
            status_code=429,
            detail="daily_limit",
            headers={"X-Limit": str(AI_DAILY_FREE_LIMIT)},
        )

    session_id = str(uuid4())
    started_at = datetime.now(timezone.utc).timestamp()

    pipe = redis_client.redis.pipeline()
    pipe.incr(daily_key)
    pipe.expire(daily_key, 26 * 3600)
    pipe.hset(f"ai_session:{session_id}", mapping={
        "user_id": user_id,
        "started_at": str(started_at),
    })
    pipe.expire(f"ai_session:{session_id}", AI_SESSION_TTL)
    pipe.set(f"ai_turns:{session_id}", "0", ex=AI_SESSION_TTL)
    await pipe.execute()

    return {
        "session_id": session_id,
        "max_seconds": AI_MAX_CALL_SECONDS,
        "partner_name": "Shivani",
    }


@router.get("/quota")
async def get_quota(authorization: str = Header(...)):
    """Return daily AI session usage without incrementing the counter."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)

    daily_key = f"ai_daily:{user['id']}:{_today_ist()}"
    count = await redis_client.redis.get(daily_key)
    used = int(count) if count else 0
    remaining = max(0, AI_DAILY_FREE_LIMIT - used)

    return {"used": used, "limit": AI_DAILY_FREE_LIMIT, "remaining": remaining}


@router.post("/chat")
async def chat(body: ChatBody, authorization: str = Header(...)):
    """Send a user turn; returns Shivani's reply."""
    if not settings.gemini_api_key:
        raise HTTPException(status_code=503, detail="AI partner unavailable")

    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)

    session_data = await redis_client.redis.hgetall(f"ai_session:{body.session_id}")
    if not session_data or session_data.get("user_id") != user["id"]:
        raise HTTPException(status_code=404, detail="Session not found")

    if len(body.user_text) > 500:
        raise HTTPException(status_code=422, detail="user_text too long")

    turns_key = f"ai_turns:{body.session_id}"
    turns = int(await redis_client.redis.get(turns_key) or "0")
    if turns >= AI_MAX_TURNS:
        raise HTTPException(status_code=429, detail="turn_limit")
    await redis_client.redis.incr(turns_key)

    # Trim history server-side to last 8 pairs (16 turns)
    trimmed = body.history[-(AI_MAX_HISTORY_PAIRS * 2):]

    reply = await gemini_service.generate_reply(
        history=trimmed,
        user_text=body.user_text,
    )

    if reply is None:
        return {"reply": AI_FALLBACK_REPLY, "fallback": True}

    return {"reply": reply}


@router.post("/end")
async def end_session(body: EndBody, authorization: str = Header(...)):
    """End the session and optionally return feedback."""
    token = authorization.replace("Bearer ", "")
    user = await _get_user(token)

    session_data = await redis_client.redis.hgetall(f"ai_session:{body.session_id}")
    if not session_data or session_data.get("user_id") != user["id"]:
        raise HTTPException(status_code=404, detail="Session not found")

    pipe = redis_client.redis.pipeline()
    pipe.delete(f"ai_session:{body.session_id}")
    pipe.delete(f"ai_turns:{body.session_id}")
    await pipe.execute()

    if len(body.transcript) < 4:
        return {"feedback": None}

    feedback = await gemini_service.generate_feedback(body.transcript)
    return {"feedback": feedback}
