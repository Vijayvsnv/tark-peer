from pydantic import BaseModel
from typing import Optional


class UserProfile(BaseModel):
    id: str
    name: str
    age: Optional[int] = None
    gender: Optional[str] = None
    bio: Optional[str] = None
    avatar_url: Optional[str] = None
    is_premium: bool = False
    total_calls: int = 0


class UpdateProfile(BaseModel):
    name: Optional[str] = None
    age: Optional[int] = None
    gender: Optional[str] = None
    bio: Optional[str] = None


class PartnerInfo(BaseModel):
    name: str
    age: Optional[int] = None
    gender: Optional[str] = None
    avatar_url: Optional[str] = None


class MatchEvent(BaseModel):
    type: str = "matched"
    channel_name: str
    agora_token: str
    agora_uid: int
    agora_app_id: str
    partner: PartnerInfo


class CallEndEvent(BaseModel):
    channel_name: str
    reason: str
