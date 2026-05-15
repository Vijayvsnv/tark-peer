import hashlib
import time
from agora_token_builder import RtcTokenBuilder

ROLE_PUBLISHER = 1


def get_uid_from_user_id(user_id: str) -> int:
    return int(hashlib.md5(user_id.encode()).hexdigest()[:8], 16) % 100000000


def generate_token(channel_name: str, user_id: str, app_id: str, app_certificate: str) -> tuple[str, int]:
    uid = get_uid_from_user_id(user_id)
    expire_time = int(time.time()) + 3600
    token = RtcTokenBuilder.buildTokenWithUid(
        app_id, app_certificate, channel_name, uid, ROLE_PUBLISHER, expire_time
    )
    return token, uid
