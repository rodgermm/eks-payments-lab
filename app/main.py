"""Minimal payments API used to demo scaling, canaries and idempotency.

Interview points:
- Idempotency-Key header: a retried request never charges twice.
  (Lab uses an in-memory dict; in prod use DynamoDB conditional writes or
  Postgres with a UNIQUE constraint so it works across replicas.)
- /metrics exposes Prometheus counters used by KEDA and Argo Rollouts analysis.
- FAIL_RATE env var injects 5xx errors to demonstrate an automatic rollback.
"""
import os
import random
import time
import uuid

from fastapi import FastAPI, Header, HTTPException, Request, Response
from prometheus_client import Counter, Histogram, make_asgi_app
from pydantic import BaseModel, Field

FAIL_RATE = float(os.getenv("FAIL_RATE", "0"))

app = FastAPI(title="payments")
app.mount("/metrics", make_asgi_app())

REQUESTS = Counter("http_requests_total", "HTTP requests", ["path", "method", "status"])
LATENCY = Histogram("http_request_duration_seconds", "Request latency", ["path"])

_payments: dict[str, dict] = {}  # idempotency_key -> payment record


class PaymentRequest(BaseModel):
    amount_cents: int = Field(gt=0)
    currency: str = Field(min_length=3, max_length=3)
    merchant_id: str


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    if request.url.path == "/metrics" or request.url.path.startswith("/metrics/"):
        return await call_next(request)
    start = time.perf_counter()
    status = 500
    try:
        response: Response = await call_next(request)
        status = response.status_code
        return response
    finally:
        LATENCY.labels(request.url.path).observe(time.perf_counter() - start)
        REQUESTS.labels(request.url.path, request.method, str(status)).inc()


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.post("/payments", status_code=201)
def create_payment(
    body: PaymentRequest,
    response: Response,
    idempotency_key: str = Header(..., alias="Idempotency-Key"),
):
    if random.random() < FAIL_RATE:
        raise HTTPException(status_code=503, detail="injected failure")

    existing = _payments.get(idempotency_key)
    if existing:
        if existing["request"] != body.model_dump():
            raise HTTPException(status_code=422, detail="Idempotency-Key reused with different payload")
        response.status_code = 200
        response.headers["Idempotent-Replay"] = "true"
        return existing["payment"]

    payment = {
        "id": str(uuid.uuid4()),
        "status": "authorized",
        **body.model_dump(),
    }
    _payments[idempotency_key] = {"request": body.model_dump(), "payment": payment}
    return payment
