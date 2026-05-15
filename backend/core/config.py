from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_anon_key: str
    supabase_service_key: str
    agora_app_id: str
    agora_app_certificate: str
    redis_url: str = "redis://localhost:6379"
    jwt_secret: str

    class Config:
        env_file = ".env"


settings = Settings()
