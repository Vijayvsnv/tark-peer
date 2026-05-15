from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager

from services import redis_client
from routers import auth, profile, call, match


@asynccontextmanager
async def lifespan(app: FastAPI):
    await redis_client.init_redis()
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
