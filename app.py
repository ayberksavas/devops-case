import json
import logging
import os
import time
import uuid
from datetime import UTC, datetime

from flask import Flask, g, jsonify, request
from prometheus_client import (
    CONTENT_TYPE_LATEST,
    REGISTRY,
    CollectorRegistry,
    Counter,
    Histogram,
    generate_latest,
    multiprocess,
)


class JsonFormatter(logging.Formatter):
    _LOG_EXTRA_FIELDS = ("request_id", "method", "path", "status", "duration_ms")

    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.fromtimestamp(record.created, tz=UTC)
        payload = {
            "timestamp": ts.isoformat(timespec="milliseconds").replace("+00:00", "Z"),
            "level": record.levelname,
            "msg": record.getMessage(),
        }
        for attr in self._LOG_EXTRA_FIELDS:
            if hasattr(record, attr):
                payload[attr] = getattr(record, attr)
        if record.exc_info:
            payload["exc_info"] = self.formatException(record.exc_info)
        return json.dumps(payload)


def _configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.setFormatter(JsonFormatter())
    root = logging.getLogger()
    root.handlers.clear()
    root.addHandler(handler)
    root.setLevel(os.environ.get("LOG_LEVEL", "INFO").upper())


_configure_logging()
logger = logging.getLogger("app")


app = Flask(__name__)

BUILD_SHA = os.environ.get("BUILD_SHA", "dev")
PORT = int(os.environ.get("PORT", "8080"))


REQUESTS_TOTAL = Counter(
    "http_requests_total",
    "Total HTTP requests handled by the service.",
    ["method", "path", "status"],
)
REQUEST_DURATION_SECONDS = Histogram(
    "http_request_duration_seconds",
    "HTTP request duration in seconds.",
    ["method", "path"],
)


def _route_label() -> str:
    # Label on the matched URL rule, not request.path, so cardinality stays bounded
    # if someone hits an unknown URL with arbitrary query/path noise.
    if request.url_rule is not None:
        return request.url_rule.rule
    return "unmatched"


@app.before_request
def _before_request() -> None:
    g.start_time = time.perf_counter()
    g.request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex


@app.after_request
def _after_request(response):
    duration = time.perf_counter() - getattr(g, "start_time", time.perf_counter())
    route = _route_label()
    # Exclude the scrape endpoint so a Prometheus pull doesn't bias its own series.
    if route != "/metrics":
        REQUESTS_TOTAL.labels(request.method, route, response.status_code).inc()
        REQUEST_DURATION_SECONDS.labels(request.method, route).observe(duration)
    response.headers["X-Request-ID"] = g.request_id
    logger.info(
        "request",
        extra={
            "request_id": g.request_id,
            "method": request.method,
            "path": route,
            "status": response.status_code,
            "duration_ms": round(duration * 1000, 2),
        },
    )
    return response


@app.get("/ping")
def ping():
    return "pong\n", 200, {"Content-Type": "text/plain; charset=utf-8"}


@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.get("/version")
def version():
    return jsonify(sha=BUILD_SHA), 200


@app.get("/metrics")
def metrics():
    # Under gunicorn with multiple workers, prometheus_client writes per-worker
    # mmap files into PROMETHEUS_MULTIPROC_DIR. The scrape must aggregate them.
    if "PROMETHEUS_MULTIPROC_DIR" in os.environ:
        registry = CollectorRegistry()
        multiprocess.MultiProcessCollector(registry)
    else:
        registry = REGISTRY
    return generate_latest(registry), 200, {"Content-Type": CONTENT_TYPE_LATEST}


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
