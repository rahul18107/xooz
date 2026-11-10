from fastapi import FastAPI
from contextlib import asynccontextmanager
import asyncio
from src.routes.audio import router as audio_router
from src.routes.digest import router as digest_router
from src.routes.transcripts import router as transcripts_router
from src.routes.tasks import router as tasks_router
from src.routes.chat import router as chat_router
from src.routes.search import router as search_router
from src.routes.activity import router as activity_router
from src.routes.profile import router as profile_router
from src.routes.devices import router as devices_router

@asynccontextmanager
async def lifespan(app: FastAPI):
    async def recap_loop():
        from src.services.recap_scheduler import run_scheduled_recaps_once
        while True:
            try:
                await asyncio.to_thread(run_scheduled_recaps_once)
            except Exception as exc:
                print(f"scheduled recap scan failed: {exc}")
            await asyncio.sleep(15 * 60)

    task = asyncio.create_task(recap_loop())
    try:
        yield
    finally:
        task.cancel()
        try:
            await task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="Xooz API",
    description="Backend for Xooz — your AI conversation digest",
    version="1.1.0",
    lifespan=lifespan,
)

app.include_router(audio_router, prefix="/api/v1")
app.include_router(digest_router, prefix="/api/v1")
app.include_router(transcripts_router, prefix="/api/v1")
app.include_router(tasks_router, prefix="/api/v1")
app.include_router(chat_router, prefix="/api/v1")
app.include_router(search_router, prefix="/api/v1")
app.include_router(activity_router, prefix="/api/v1")
app.include_router(profile_router, prefix="/api/v1")
app.include_router(devices_router, prefix="/api/v1")

@app.get("/")
def root():
    return {"status": "Xooz backend is running"}

@app.get("/health")
def health():
    return {"status": "ok"}

# Some local tooling probes this endpoint expecting an OpenAI-compatible server.
# It's not used by the Xooz app; return a minimal valid response to avoid 404 noise.
@app.get("/v1/models")
def list_models():
    return {
        "object": "list",
        "data": [
            {
                "id": "xooz",
                "object": "model",
                "owned_by": "xooz-server",
            }
        ],
    }
