"""Local AI API: FastAPI wrapper around Ollama with Prometheus metrics."""
import logging
import os
import time

import httpx
from fastapi import FastAPI, HTTPException, Request, Response
from prometheus_client import (CONTENT_TYPE_LATEST, Counter, Gauge, Histogram,
                               generate_latest)
from pydantic import BaseModel, Field

OLLAMA_URL = os.getenv("OLLAMA_URL", "http://127.0.0.1:11434").rstrip("/")
MODEL_NAME = os.getenv("MODEL_NAME", "qwen2.5:0.5b")
REQUEST_TIMEOUT = float(os.getenv("REQUEST_TIMEOUT", "120"))

logging.basicConfig(level=os.getenv("LOG_LEVEL", "INFO"),
                    format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("ai-api")

REQUESTS = Counter("ai_api_requests_total", "HTTP requests",
                   ["endpoint", "method", "status"])
LATENCY = Histogram("ai_api_request_duration_seconds", "HTTP request latency",
                    ["endpoint"],
                    buckets=(0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 20, 40, 60, 120))
IN_FLIGHT = Gauge("ai_api_in_flight", "Requests currently being processed")
TOKENS = Counter("ai_generate_tokens_total", "Tokens processed by the model",
                 ["type"])
OLLAMA_ERRORS = Counter("ai_ollama_errors_total", "Errors talking to Ollama",
                        ["reason"])

app = FastAPI(title="Local AI API", version="0.1.0")


class GenerateRequest(BaseModel):
    prompt: str = Field(..., min_length=1, max_length=4000)
    max_tokens: int = Field(128, ge=1, le=1024)
    temperature: float = Field(0.7, ge=0.0, le=2.0)


class GenerateResponse(BaseModel):
    model: str
    response: str
    prompt_tokens: int
    completion_tokens: int
    latency_seconds: float


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    start = time.perf_counter()
    IN_FLIGHT.inc()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        return response
    finally:
        IN_FLIGHT.dec()
        route = request.scope.get("route")
        endpoint = route.path if route else "unmatched"
        if endpoint != "/metrics":
            REQUESTS.labels(endpoint, request.method, str(status)).inc()
            LATENCY.labels(endpoint).observe(time.perf_counter() - start)


@app.get("/live")
async def live():
    """Liveness: the process is up. Does not depend on Ollama."""
    return {"status": "alive"}


@app.get("/health")
async def health():
    """Readiness: Ollama reachable and the model is pulled."""
    try:
        async with httpx.AsyncClient(timeout=5) as client:
            r = await client.get(f"{OLLAMA_URL}/api/tags")
            r.raise_for_status()
            names = [m.get("name", "") for m in r.json().get("models", [])]
    except Exception as exc:
        OLLAMA_ERRORS.labels("health_unreachable").inc()
        raise HTTPException(503, detail=f"ollama unreachable: {exc}")
    wanted = MODEL_NAME if ":" in MODEL_NAME else f"{MODEL_NAME}:latest"
    if wanted not in names:
        raise HTTPException(503, detail=f"model {wanted} not found in ollama")
    return {"status": "ok", "model": MODEL_NAME, "ollama": "reachable"}


@app.post("/generate", response_model=GenerateResponse)
async def generate(req: GenerateRequest):
    start = time.perf_counter()
    payload = {
        "model": MODEL_NAME,
        "prompt": req.prompt,
        "stream": False,
        "options": {"num_predict": req.max_tokens, "temperature": req.temperature},
    }
    try:
        async with httpx.AsyncClient(timeout=REQUEST_TIMEOUT) as client:
            r = await client.post(f"{OLLAMA_URL}/api/generate", json=payload)
            r.raise_for_status()
            data = r.json()
    except httpx.TimeoutException:
        OLLAMA_ERRORS.labels("timeout").inc()
        raise HTTPException(504, detail="ollama timed out")
    except httpx.HTTPStatusError as exc:
        OLLAMA_ERRORS.labels("http_error").inc()
        raise HTTPException(502, detail=f"ollama error: {exc.response.status_code}")
    except httpx.HTTPError as exc:
        OLLAMA_ERRORS.labels("connect").inc()
        raise HTTPException(502, detail=f"ollama unreachable: {exc}")

    p = int(data.get("prompt_eval_count", 0))
    c = int(data.get("eval_count", 0))
    TOKENS.labels("prompt").inc(p)
    TOKENS.labels("completion").inc(c)
    return GenerateResponse(model=MODEL_NAME, response=data.get("response", ""),
                            prompt_tokens=p, completion_tokens=c,
                            latency_seconds=round(time.perf_counter() - start, 3))


@app.get("/metrics")
async def metrics():
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
