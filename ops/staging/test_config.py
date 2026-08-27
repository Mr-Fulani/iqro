from __future__ import annotations

import base64
import json
import os
import tempfile
from pathlib import Path

from ops.staging.configure_email import _resend_replacements
from ops.staging.configure_media import _replace_values, build_cors
from ops.staging.configure_web_push import generate_vapid_keys
from ops.staging.init import NOT_CONFIGURED, SECRET_KEYS, _render, build_overrides
from ops.staging.preflight import load_env, validate

TEMPLATE = """\
APP_VERSION=0.1.0
SITE_URL=https://example.com
LEGAL_ENTITY_NAME=replace-me
LEGAL_CONTACT_EMAIL=replace-me@example.com
SECURITY_CONTACT_EMAIL=replace-me@example.com
LEGAL_POSTAL_ADDRESS=replace-me
LEGAL_JURISDICTION=replace-me
LEGAL_EFFECTIVE_DATE=2026-01-01
DJANGO_SECRET_KEY=replace-me
DJANGO_ALLOWED_HOSTS=example.com
DJANGO_CSRF_TRUSTED_ORIGINS=https://example.com
DJANGO_CORS_ALLOWED_ORIGINS=https://example.com
DJANGO_NUM_PROXIES=1
DJANGO_SECURE_SSL_REDIRECT=true
DATABASE_NAME=quran
DATABASE_USER=quran
DATABASE_PASSWORD=replace-me
DATABASE_CONN_MAX_AGE=0
PUBLIC_MEDIA_BASE_URL=https://media.example.com/
PUBLIC_AUDIO_BASE_URL=https://media.example.com/
MEDIA_OBJECT_STORAGE_ENDPOINT_URL=https://replace-me.r2.cloudflarestorage.com/
MEDIA_OBJECT_STORAGE_BUCKET=replace-me
MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID=replace-me
MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY=replace-me
MEDIA_CDN_REQUIRED_ORIGINS=https://example.com
GATEWAY_BIND_ADDRESS=127.0.0.1
""" + "\n".join(
    f"{key}=replace-me"
    for key in SECRET_KEYS
    if key not in {"DATABASE_PASSWORD", "DJANGO_SECRET_KEY"}
)


def _overrides(*, media_ready: bool) -> dict[str, str]:
    return build_overrides(
        template=TEMPLATE,
        host="staging.example.test",
        media_host="media.staging.example.test",
        acme_email="ops@example.test",
        extra_origins=["https://telegram-staging.example.test"],
        r2_account_id="abc123" if media_ready else "",
        r2_bucket="quran-staging" if media_ready else "",
        r2_access_key_id="staging-access" if media_ready else "",
        r2_secret_access_key="staging-secret" if media_ready else "",
    )


def test_generated_config_passes_basic_preflight_with_media_warning() -> None:
    values = _overrides(media_ready=False)

    errors, warnings = validate(values, require_media=False)

    assert errors == []
    assert len(warnings) == 1
    assert "R2 is not configured" in warnings[0]
    assert len({values[key] for key in SECRET_KEYS}) == len(SECRET_KEYS)


def test_generated_config_passes_strict_media_preflight() -> None:
    values = _overrides(media_ready=True)

    errors, warnings = validate(values, require_media=True)

    assert errors == []
    assert warnings == []
    assert values["RESTORE_CHECK_DATABASE"] == "quran_restore_check_staging"


def test_strict_preflight_rejects_unconfigured_media() -> None:
    errors, _ = validate(_overrides(media_ready=False), require_media=True)

    assert any("R2 is not configured" in error for error in errors)


def test_render_and_load_do_not_duplicate_overrides(tmp_path: Path) -> None:
    output = tmp_path / "staging.env"
    output.write_text(_render(TEMPLATE, _overrides(media_ready=True)), encoding="utf-8")
    os.chmod(output, 0o600)

    values, parse_errors = load_env(output)

    assert parse_errors == []
    assert values["STAGING_HOST"] == "staging.example.test"
    assert output.read_text(encoding="utf-8").count("SITE_URL=") == 1


def test_media_configuration_and_cors_are_derived_from_staging_origins() -> None:
    rendered = _render(TEMPLATE, _overrides(media_ready=False))
    updated = _replace_values(
        rendered,
        {
            "MEDIA_OBJECT_STORAGE_ENDPOINT_URL": (
                "https://0123456789abcdef0123456789abcdef.r2.cloudflarestorage.com/"
            ),
            "MEDIA_OBJECT_STORAGE_BUCKET": "quran-staging",
            "MEDIA_OBJECT_STORAGE_ACCESS_KEY_ID": "access-key",
            "MEDIA_OBJECT_STORAGE_SECRET_ACCESS_KEY": "secret-key",
        },
    )
    assert NOT_CONFIGURED not in updated

    policy = json.loads(
        build_cors(
            ["https://staging.example.test", "https://telegram-staging.example.test"]
        )
    )
    assert policy[0]["AllowedMethods"] == ["GET", "HEAD"]
    assert policy[0]["AllowedHeaders"] == ["Range"]
    assert policy[0]["AllowedOrigins"] == [
        "https://staging.example.test",
        "https://telegram-staging.example.test",
    ]


def test_resend_configuration_enables_external_smtp_without_exposing_the_key() -> None:
    values = _overrides(media_ready=True)
    values.update(
        _resend_replacements(
            from_email="login@auth.iqro.forum",
            api_key="re_abcdefghijklmnopqrstuvwxyz123456",
        )
    )

    errors, warnings = validate(values, require_media=True)

    assert errors == []
    assert warnings == []
    assert values["STAGING_EMAIL_DELIVERY_MODE"] == "smtp"
    assert values["DJANGO_EMAIL_HOST"] == "smtp.resend.com"
    assert values["DJANGO_DEFAULT_FROM_EMAIL"] == "IQRO <login@auth.iqro.forum>"
    assert values["FEEDBACK_NOTIFICATION_EMAIL"] == "ops@example.test"


def test_generated_vapid_keys_enable_web_push_preflight() -> None:
    public_key, private_key = generate_vapid_keys()
    values = _overrides(media_ready=True)
    values.update(
        {
            "WEB_PUSH_ENABLED": "true",
            "WEB_PUSH_VAPID_PUBLIC_KEY": public_key,
            "WEB_PUSH_VAPID_PRIVATE_KEY": private_key,
        }
    )

    errors, warnings = validate(values, require_media=True)
    public_raw = base64.urlsafe_b64decode(public_key + "==")
    private_der = base64.urlsafe_b64decode(private_key + "==")

    assert errors == []
    assert warnings == []
    assert len(public_raw) == 65
    assert public_raw[0] == 4
    assert private_der.startswith(b"0")


def main() -> int:
    test_generated_config_passes_basic_preflight_with_media_warning()
    test_generated_config_passes_strict_media_preflight()
    test_strict_preflight_rejects_unconfigured_media()
    test_media_configuration_and_cors_are_derived_from_staging_origins()
    test_resend_configuration_enables_external_smtp_without_exposing_the_key()
    test_generated_vapid_keys_enable_web_push_preflight()
    with tempfile.TemporaryDirectory(prefix="quran-staging-test-") as directory:
        test_render_and_load_do_not_duplicate_overrides(Path(directory))
    print("OK: staging configuration self-tests passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
