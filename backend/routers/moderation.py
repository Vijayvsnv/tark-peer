"""
Moderation endpoints.

POST /report — submit a report against another user.
  * Rate-limited: 10 reports per user per hour.
  * Auto-restriction: if >= 5 distinct reporters in the last 7 days, the
    reported user gets a 72-hour Redis restriction that blocks them from
    joining the matchmaking queue.
"""

import logging
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Header, HTTPException
from pydantic import BaseModel

from services import redis_client
from services.supabase_client import supabase_admin

router = APIRouter(tags=["moderation"])
logger = logging.getLogger(__name__)

_VALID_REASONS = frozenset({
    "abusive_language",
    "harassment",
    "not_speaking_english",
    "spam_or_scam",
    "inappropriate_content",
    "other",
})

_RESTRICTION_THRESHOLD = 5       # distinct reporters in 7 days
_RESTRICTION_TTL = 72 * 3600     # 72 hours in seconds


class ReportBody(BaseModel):
    reported_id: str
    room_id: Optional[str] = None
    reason: str
    details: Optional[str] = None


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


@router.post("/report")
async def report_user(body: ReportBody, authorization: str = Header(...)):
    token = authorization.replace("Bearer ", "", 1)
    user = await _get_user(token)
    user_id = user["id"]

    if body.reason not in _VALID_REASONS:
        raise HTTPException(
            status_code=422,
            detail=f"Invalid reason. Allowed: {', '.join(sorted(_VALID_REASONS))}",
        )
    if body.reported_id == user_id:
        raise HTTPException(status_code=422, detail="Cannot report yourself")

    if not await redis_client.check_rate_limit(f"report:{user_id}", 10, 3600):
        raise HTTPException(status_code=429, detail="Too many reports. Please try again later.")

    try:
        supabase_admin.table("reports").insert({
            "reporter_id": user_id,
            "reported_id": body.reported_id,
            "room_id": body.room_id,
            "reason": body.reason,
            "details": body.details,
        }).execute()
    except Exception as e:
        logger.error("report insert failed: %r", e)
        raise HTTPException(status_code=500, detail="Failed to submit report")

    # Auto-restriction check: count distinct reporters in last 7 days
    try:
        seven_days_ago = (datetime.now(timezone.utc) - timedelta(days=7)).isoformat()
        resp = (
            supabase_admin.table("reports")
            .select("reporter_id")
            .eq("reported_id", body.reported_id)
            .gte("created_at", seven_days_ago)
            .execute()
        )
        distinct = len({row["reporter_id"] for row in (resp.data or [])})
        if distinct >= _RESTRICTION_THRESHOLD:
            await redis_client.redis.set(
                f"restricted:{body.reported_id}",
                "1",
                ex=_RESTRICTION_TTL,
            )
            logger.info(
                "auto-restricted %s (%d distinct reporters in 7d)",
                body.reported_id,
                distinct,
            )
    except Exception as e:
        logger.warning("auto-restriction check failed: %r", e)

    return {"status": "submitted"}
