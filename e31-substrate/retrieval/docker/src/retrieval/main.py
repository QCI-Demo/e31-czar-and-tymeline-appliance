"""E31 Retrieval Service entrypoint."""

import os

import uvicorn
from fastapi import FastAPI

app = FastAPI(title="E31 Retrieval Service", version="1.0.0")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "retrieval"}


def main() -> None:
    port = int(os.environ.get("PORT", "8081"))
    uvicorn.run(app, host="0.0.0.0", port=port)


if __name__ == "__main__":
    main()
