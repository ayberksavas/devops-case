"""Gunicorn config.

Two responsibilities:
  1. Run the multiprocess cleanup for prometheus_client. Each worker writes
     metric counters to its own mmap file under PROMETHEUS_MULTIPROC_DIR; when
     a worker exits, that file must be marked dead so the next scrape stops
     counting a gone PID's series as live.
  2. Disable gunicorn's plain-text access log. The Flask after_request hook
     emits a structured JSON line per request, which is what /var/log consumers
     should see.
"""
import os

bind = f"0.0.0.0:{os.environ.get('PORT', '8080')}"
workers = int(os.environ.get("WEB_CONCURRENCY", "2"))
accesslog = None


def child_exit(server, worker):  # noqa: ARG001 — gunicorn-required signature
    if "PROMETHEUS_MULTIPROC_DIR" in os.environ:
        from prometheus_client import multiprocess

        multiprocess.mark_process_dead(worker.pid)
