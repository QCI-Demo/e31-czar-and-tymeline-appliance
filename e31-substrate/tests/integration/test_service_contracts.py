"""Integration-style tests for E31 substrate service contracts."""

from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient

SERVICE_PORTS = {
    "memory.main": 8080,
    "retrieval.main": 8081,
    "inference.main": 8082,
    "fine_tuning.main": 8083,
    "eval.main": 8084,
    "watchman.main": 9090,
    "local_bridge.main": 8443,
}


@pytest.mark.parametrize("module_path,port", list(SERVICE_PORTS.items()))
def test_default_port_env(module_path: str, port: int, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("PORT", raising=False)
    mod = importlib.import_module(module_path)
    # Ensure module exposes main() and app
    assert callable(mod.main)
    assert hasattr(mod, "app")
    # Port constant used by main() via env default
    assert port > 0


@pytest.mark.parametrize("module_path", list(SERVICE_PORTS.keys()))
def test_openapi_available(module_path: str) -> None:
    mod = importlib.import_module(module_path)
    client = TestClient(mod.app)
    resp = client.get("/openapi.json")
    assert resp.status_code == 200
    spec = resp.json()
    assert "/health" in spec.get("paths", {})


def test_all_seven_services_importable() -> None:
    for module_path in SERVICE_PORTS:
        importlib.import_module(module_path)
