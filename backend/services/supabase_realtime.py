"""
Server-side Supabase Realtime broadcast helper.

Lets the FastAPI backend push events to any client that is subscribed to a
named channel, without holding a long-lived WebSocket on our own server.
This is what makes the matchmaker / call lifecycle multi-instance ready:
any backend pod can publish; Supabase fans out to the right subscribers.

Usage:
    await broadcast("user:abc", "matched", {"channel_name": "..."})
    await broadcast("room:xyz", "call_ended", {"reason": "timer"})
"""

import logging
from typing import Any

import httpx

from core.config import settings

logger = logging.getLogger(__name__)

# Supabase Realtime accepts up to 100 messages per request; keep timeouts short
# so a slow broadcast can never wedge the matcher loop.
_BROADCAST_TIMEOUT_S = 5.0


async def broadcast(topic: str, event: str, payload: dict[str, Any]) -> bool:
    """
    Publish a single broadcast message to a Realtime topic.

    Returns True on 2xx, False otherwise (errors are swallowed and logged —
    a failed broadcast must never crash the caller).
    """
    url = f"{settings.supabase_url}/realtime/v1/api/broadcast"
    headers = {
        "apikey": settings.supabase_service_key,
        "Authorization": f"Bearer {settings.supabase_service_key}",
        "Content-Type": "application/json",
    }
    body = {
        "messages": [
            {
                "topic": topic,
                "event": event,
                "payload": payload,
                "private": False,
            }
        ]
    }

    try:
        async with httpx.AsyncClient(timeout=_BROADCAST_TIMEOUT_S) as client:
            resp = await client.post(url, headers=headers, json=body)
        if 200 <= resp.status_code < 300:
            return True
        logger.warning(
            "Realtime broadcast non-2xx: topic=%s event=%s status=%d body=%s",
            topic, event, resp.status_code, resp.text[:200],
        )
        return False
    except Exception as e:
        logger.warning("Realtime broadcast failed: topic=%s event=%s err=%r", topic, event, e)
        return False
