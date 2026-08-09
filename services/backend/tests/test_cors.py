from __future__ import annotations

from django.test import Client, override_settings


@override_settings(CORS_ALLOWED_ORIGINS=["https://app.example"])
def test_api_preflight_allows_only_configured_origin(client: Client) -> None:
    allowed = client.options(
        "/api/v1/auth/guest",
        headers={
            "Origin": "https://app.example",
            "Access-Control-Request-Method": "POST",
            "Access-Control-Request-Headers": "authorization,content-type,x-request-id",
        },
    )
    denied = client.options(
        "/api/v1/auth/guest",
        headers={
            "Origin": "https://attacker.example",
            "Access-Control-Request-Method": "POST",
        },
    )

    assert allowed.status_code == 200
    assert allowed["Access-Control-Allow-Origin"] == "https://app.example"
    assert "authorization" in allowed["Access-Control-Allow-Headers"]
    assert "x-request-id" in allowed["Access-Control-Allow-Headers"]
    assert "Access-Control-Allow-Credentials" not in allowed
    assert "Access-Control-Allow-Origin" not in denied


@override_settings(CORS_ALLOWED_ORIGINS=["https://app.example"])
def test_cors_is_limited_to_api_paths(client: Client) -> None:
    response = client.get("/admin/login/", headers={"Origin": "https://app.example"})

    assert "Access-Control-Allow-Origin" not in response
