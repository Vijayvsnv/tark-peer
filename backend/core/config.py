from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    supabase_url: str
    supabase_anon_key: str
    supabase_service_key: str
    agora_app_id: str
    agora_app_certificate: str
    redis_url: str = "redis://localhost:6379"
    jwt_secret: str
    gemini_api_key: str = ""
    gemini_model: str = "gemini-2.0-flash"

    class Config:
        env_file = ".env"


settings = Settings()
