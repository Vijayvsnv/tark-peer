from pydantic import BaseModel, Field
from typing import Optional, Literal


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
    name: Optional[str] = Field(None, min_length=1, max_length=100)
    age: Optional[int] = Field(None, ge=13, le=150)
    gender: Optional[Literal["male", "female", "other"]] = None
    bio: Optional[str] = Field(None, max_length=500)


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


class DirectCallBody(BaseModel):
    receiver_id: str = Field(..., min_length=1)


class CallEndEvent(BaseModel):
    channel_name: str = Field(..., min_length=1, max_length=200)
    reason: str = Field(..., min_length=1, max_length=50)


class CallRateEvent(BaseModel):
    channel_name: str = Field(..., min_length=1, max_length=200)
    rated_user_id: str = Field(..., min_length=1)
    stars: int = Field(..., ge=1, le=5)
