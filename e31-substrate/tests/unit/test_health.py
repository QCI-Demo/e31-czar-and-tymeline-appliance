"""Unit tests for E31 substrate service health endpoints."""

from __future__ import annotations

import importlib

import pytest
from fastapi.testclient import TestClient

SERVICES = [
    ("memory", "memory.main"),
    ("retrieval", "retrieval.main"),
    ("inference", "inference.main"),
    ("fine_tuning", "fine_tuning.main"),
    ("eval", "eval.main"),
    ("watchman", "watchman.main"),
    ("local_bridge", "local_bridge.main"),
]


@pytest.mark.parametrize("expected_name,module_path", SERVICES)
def test_health_endpoint(expected_name: str, module_path: str) -> None:
    mod = importlib.import_module(module_path)
    client = TestClient(mod.app)
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    # service field uses hyphenated names for fine-tuning / local-bridge
    assert "service" in body


@pytest.mark.parametrize("expected_name,module_path", SERVICES)
def test_app_metadata(expected_name: str, module_path: str) -> None:
    mod = importlib.import_module(module_path)
    assert mod.app.title.startswith("E31")
    assert mod.app.version == "1.0.0"
