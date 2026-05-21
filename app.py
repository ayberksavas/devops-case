import os

from flask import Flask, jsonify

app = Flask(__name__)

BUILD_SHA = os.environ.get("BUILD_SHA", "dev")
PORT = int(os.environ.get("PORT", "8080"))


@app.get("/ping")
def ping():
    return "pong\n", 200, {"Content-Type": "text/plain; charset=utf-8"}


@app.get("/healthz")
def healthz():
    return jsonify(status="ok"), 200


@app.get("/version")
def version():
    return jsonify(sha=BUILD_SHA), 200


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=PORT)
