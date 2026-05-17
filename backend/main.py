from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from services import redis_client
from services.supabase_client import supabase_admin
from routers import auth, profile, call, match
from routers.match import active_connections


@asynccontextmanager
async def lifespan(app: FastAPI):
    await redis_client.init_redis()
    # Wipe leftover keys from any previous crash / restart so stale state
    # never blocks the first match after a deploy.
    await redis_client.clear_stale_state()
    yield
    await redis_client.close_redis()


app = FastAPI(title="Tark Peer API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(profile.router)
app.include_router(call.router)
app.include_router(match.router)


@app.get("/health")
async def health():
    return {"status": "ok", "service": "tark-peer"}


@app.get("/stats")
async def get_stats():
    try:
        resp = supabase_admin.table("profiles").select("id", count="exact").execute()
        total = resp.count or 0
    except Exception:
        total = 0
    online = len(active_connections)
    return {
        "total_users": total,
        "online": online,
        "offline": max(0, total - online),
    }
