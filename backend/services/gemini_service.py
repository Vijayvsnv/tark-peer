import json
import logging

import httpx

from core.config import settings

logger = logging.getLogger(__name__)

_GEMINI_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

_SHIVANI_SYSTEM_PROMPT = (
    "You are Shivani, a friendly 24-year-old AI English practice partner on the Tark Peer app. "
    "You are talking by VOICE, so keep every reply SHORT: 1–3 sentences, under 35 words. "
    "Never use emojis, markdown, lists, or stage directions — plain speakable text only. "
    "Your job: help Indian learners practice spoken English. Be warm, encouraging, curious. "
    "Ask one simple follow-up question in most replies to keep them talking. "
    "Match the user's level — simple words for beginners. "
    "If the user speaks Hindi or Hinglish, gently respond in English and encourage them: "
    "acknowledge what they said, then say it in simple English and invite them to try. "
    "You are an AI and you say so plainly if asked: 'I'm Shivani, Tark Peer's AI practice partner'. "
    "Never claim to be human, never invent a personal life beyond light small-talk framing, "
    "never share phone numbers or social media handles. "
    "Refuse romantic, sexual, or abusive directions politely and steer back to practice topics. "
    "If the user seems distressed, be kind and suggest talking to someone they trust. "
    "Good default topics: daily routine, movies, food, cricket, college or job, hometown, hobbies, simple debates."
)

_FEEDBACK_PROMPT = (
    "You are an English language coach. The following is a voice conversation transcript between "
    "an AI practice partner (Shivani) and a learner. "
    "Respond with ONLY valid JSON, no markdown fences, no extra text. "
    "Format: {\"corrections\": [{\"you_said\": \"...\", \"better\": \"...\", \"why\": \"...\"}], "
    "\"strengths\": [\"...\"], \"score\": 7} "
    "Rules: max 3 corrections (only real grammar/vocabulary errors), max 3 strengths, "
    "score is 1–10 for overall spoken English quality."
)


async def generate_reply(
    history: list[dict],
    user_text: str,
    max_output_tokens: int = 120,
) -> str | None:
    if not settings.gemini_api_key:
        return None
    try:
        contents = []
        for turn in history:
            role = turn.get("role", "user")
            gemini_role = "model" if role == "model" else "user"
            contents.append({"role": gemini_role, "parts": [{"text": turn.get("text", "")}]})
        contents.append({"role": "user", "parts": [{"text": user_text}]})

        payload = {
            "system_instruction": {"parts": [{"text": _SHIVANI_SYSTEM_PROMPT}]},
            "contents": contents,
            "generationConfig": {
                "temperature": 0.8,
                "maxOutputTokens": max_output_tokens,
            },
        }
        url = f"{_GEMINI_BASE}/{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
        async with httpx.AsyncClient(timeout=12.0) as client:
            resp = await client.post(url, json=payload)
        if resp.status_code != 200:
            logger.warning("Gemini non-200: %d %s", resp.status_code, resp.text[:200])
            return None
        data = resp.json()
        candidates = data.get("candidates") or []
        if not candidates:
            return None
        parts = candidates[0].get("content", {}).get("parts") or []
        if not parts:
            return None
        return parts[0].get("text", "").strip() or None
    except Exception as exc:
        logger.warning("generate_reply error: %r", exc)
        return None


async def generate_feedback(transcript: list[dict]) -> dict | None:
    if not settings.gemini_api_key:
        return None
    try:
        lines = []
        for turn in transcript:
            role = "Shivani" if turn.get("role") == "model" else "Learner"
            lines.append(f"{role}: {turn.get('text', '')}")
        transcript_text = "\n".join(lines)

        payload = {
            "system_instruction": {"parts": [{"text": _FEEDBACK_PROMPT}]},
            "contents": [{"role": "user", "parts": [{"text": transcript_text}]}],
            "generationConfig": {
                "temperature": 0.3,
                "maxOutputTokens": 400,
            },
        }
        url = f"{_GEMINI_BASE}/{settings.gemini_model}:generateContent?key={settings.gemini_api_key}"
        async with httpx.AsyncClient(timeout=12.0) as client:
            resp = await client.post(url, json=payload)
        if resp.status_code != 200:
            logger.warning("Gemini feedback non-200: %d", resp.status_code)
            return None
        data = resp.json()
        candidates = data.get("candidates") or []
        if not candidates:
            return None
        parts = candidates[0].get("content", {}).get("parts") or []
        if not parts:
            return None
        raw = parts[0].get("text", "").strip()
        # Strip markdown fences if present
        if raw.startswith("```"):
            raw = raw.split("```")[1]
            if raw.startswith("json"):
                raw = raw[4:]
        raw = raw.strip()
        result = json.loads(raw)
        # Validate shape
        if not isinstance(result, dict):
            return None
        result.setdefault("corrections", [])
        result.setdefault("strengths", [])
        result.setdefault("score", 5)
        result["corrections"] = result["corrections"][:3]
        result["strengths"] = result["strengths"][:3]
        return result
    except Exception as exc:
        logger.warning("generate_feedback error: %r", exc)
        return None
