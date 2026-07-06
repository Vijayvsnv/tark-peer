import asyncio
import json
import logging
import os
from datetime import datetime, timedelta, timezone
from pathlib import Path

import firebase_admin
from firebase_admin import credentials, messaging

from services.supabase_client import supabase_admin

logger = logging.getLogger(__name__)

_SERVICE_ACCOUNT_PATH = Path(__file__).parent.parent / "firebase-service-account.json"


def _init():
    if not firebase_admin._apps:
        # Render pe env var se load karo; local dev mein file se
        sa_json = os.environ.get("FIREBASE_SERVICE_ACCOUNT_JSON")
        if sa_json:
            cred = credentials.Certificate(json.loads(sa_json))
        else:
            cred = credentials.Certificate(str(_SERVICE_ACCOUNT_PATH))
        firebase_admin.initialize_app(cred)


_init()


def _send_sync(token: str, title: str, body: str | None, data: dict) -> None:
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body or None),
        data={k: str(v) for k, v in data.items()},
        token=token,
        android=messaging.AndroidConfig(priority="high"),
    )
    messaging.send(message)


async def send_to_user(user_id: str, title: str, body: str | None = None, data: dict | None = None) -> bool:
    """Fetch FCM token for user_id and send a push notification. Fire-and-forget safe."""
    try:
        resp = (
            supabase_admin.table("profiles")
            .select("fcm_token")
            .eq("id", user_id)
            .single()
            .execute()
        )
        token: str | None = (resp.data or {}).get("fcm_token")
        if not token:
            return False

        loop = asyncio.get_event_loop()
        await loop.run_in_executor(None, _send_sync, token, title, body, data or {})
        return True
    except Exception as exc:
        logger.warning("FCM send failed for %s: %r", user_id, exc)
        return False


def _blast_sync(tokens: list[str], title: str) -> int:
    """Send same notification to many tokens in batches of 500. Returns success count."""
    sent = 0
    for i in range(0, len(tokens), 500):
        batch = tokens[i : i + 500]
        multicast = messaging.MulticastMessage(
            notification=messaging.Notification(title=title),
            android=messaging.AndroidConfig(priority="high"),
            tokens=batch,
        )
        resp = messaging.send_each_for_multicast(multicast)
        sent += resp.success_count
    return sent


async def send_streak_warning_blast() -> int:
    """Notify users who called yesterday but haven't called today — streak at risk."""
    try:
        IST = timezone(timedelta(hours=5, minutes=30))
        now_ist = datetime.now(IST)
        today_start = now_ist.replace(hour=0, minute=0, second=0, microsecond=0)
        yesterday_start = today_start - timedelta(days=1)
        today_utc = today_start.astimezone(timezone.utc).isoformat()
        yesterday_utc = yesterday_start.astimezone(timezone.utc).isoformat()

        # Who called yesterday?
        y = supabase_admin.table("call_history").select("user_a,user_b") \
            .gte("started_at", yesterday_utc).lt("started_at", today_utc).execute()
        yesterday_users: set[str] = set()
        for row in (y.data or []):
            yesterday_users.update([row["user_a"], row["user_b"]])

        if not yesterday_users:
            return 0

        # Who already called today?
        t = supabase_admin.table("call_history").select("user_a,user_b") \
            .gte("started_at", today_utc).execute()
        today_users: set[str] = set()
        for row in (t.data or []):
            today_users.update([row["user_a"], row["user_b"]])

        at_risk = list(yesterday_users - today_users)
        if not at_risk:
            return 0

        token_resp = supabase_admin.table("profiles").select("fcm_token") \
            .in_("id", at_risk).not_.is_("fcm_token", "null").execute()
        tokens = [r["fcm_token"] for r in (token_resp.data or []) if r.get("fcm_token")]
        if not tokens:
            return 0

        loop = asyncio.get_event_loop()
        count = await loop.run_in_executor(
            None, _blast_sync, tokens, "🔥 Your streak will break tonight! Practice now"
        )
        logger.info("Streak warning blast: %d/%d sent", count, len(tokens))
        return count
    except Exception as exc:
        logger.warning("Streak warning blast failed: %r", exc)
        return 0


async def send_peak_hour_blast(title: str) -> int:
    """Send peak hour reminder to every user who has an FCM token."""
    try:
        resp = (
            supabase_admin.table("profiles")
            .select("fcm_token")
            .not_.is_("fcm_token", "null")
            .execute()
        )
        tokens = [r["fcm_token"] for r in (resp.data or []) if r.get("fcm_token")]
        if not tokens:
            return 0

        loop = asyncio.get_event_loop()
        count = await loop.run_in_executor(None, _blast_sync, tokens, title)
        logger.info("Peak hour blast: %d/%d sent", count, len(tokens))
        return count
    except Exception as exc:
        logger.warning("Peak hour blast failed: %r", exc)
        return 0
