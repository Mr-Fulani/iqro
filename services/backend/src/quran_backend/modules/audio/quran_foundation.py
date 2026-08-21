from __future__ import annotations

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from typing import Any
from urllib.parse import urlsplit


class QuranFoundationError(RuntimeError):
    """A safe, credential-free Quran.Foundation integration error."""


@dataclass(frozen=True, slots=True)
class QuranFoundationEnvironment:
    name: str
    oauth_base_url: str
    api_base_url: str


ENVIRONMENTS = {
    "prelive": QuranFoundationEnvironment(
        name="prelive",
        oauth_base_url="https://prelive-oauth2.quran.foundation",
        api_base_url="https://apis-prelive.quran.foundation",
    ),
    "production": QuranFoundationEnvironment(
        name="production",
        oauth_base_url="https://oauth2.quran.foundation",
        api_base_url="https://apis.quran.foundation",
    ),
}

USER_AGENT = "iqro.forum-backend/0.1 (+https://iqro.forum)"
ALLOWED_AUDIO_HOSTS = {"download.quranicaudio.com", "audio.qurancdn.com"}


class QuranFoundationClient:
    def __init__(
        self,
        *,
        client_id: str,
        client_secret: str,
        environment: QuranFoundationEnvironment,
        timeout_seconds: int = 30,
    ) -> None:
        if not client_id or not client_secret:
            raise QuranFoundationError("QF_CLIENT_ID and QF_CLIENT_SECRET are required.")
        self.client_id = client_id
        self._client_secret = client_secret
        self.environment = environment
        self.timeout_seconds = timeout_seconds
        self._access_token: str | None = None

    @classmethod
    def from_environment(cls) -> QuranFoundationClient:
        environment_name = os.getenv("QF_ENV", "prelive")
        environment = ENVIRONMENTS.get(environment_name)
        if environment is None:
            raise QuranFoundationError("QF_ENV must be 'prelive' or 'production'.")
        return cls(
            client_id=os.getenv("QF_CLIENT_ID", ""),
            client_secret=os.getenv("QF_CLIENT_SECRET", ""),
            environment=environment,
        )

    def list_chapter_reciters(self, *, language: str = "en") -> list[dict[str, Any]]:
        payload = self._get_json(
            "/content/api/v4/resources/chapter_reciters",
            query={"language": language},
        )
        reciters = payload.get("reciters")
        if not isinstance(reciters, list):
            raise QuranFoundationError("Quran.Foundation returned an invalid reciter catalog.")
        return [row for row in reciters if isinstance(row, dict)]

    def get_chapter_audio(
        self,
        reciter_id: int,
        chapter_number: int,
    ) -> dict[str, Any]:
        payload = self._get_json(
            f"/content/api/v4/chapter_recitations/{reciter_id}/{chapter_number}",
            query={"segments": "true"},
        )
        audio_file = payload.get("audio_file")
        if not isinstance(audio_file, dict):
            raise QuranFoundationError(
                f"Quran.Foundation returned invalid audio metadata for chapter {chapter_number}."
            )
        return audio_file

    def get_external_audio_size(self, url: str) -> int:
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https"
            or parsed.hostname not in ALLOWED_AUDIO_HOSTS
            or parsed.username is not None
            or parsed.password is not None
        ):
            raise QuranFoundationError("Quran.Foundation returned an unapproved audio origin.")
        request = urllib.request.Request(  # noqa: S310 - validated HTTPS audio origin
            url,
            headers={"Accept": "audio/*", "User-Agent": USER_AGENT},
            method="HEAD",
        )
        try:
            with urllib.request.urlopen(  # noqa: S310 - validated HTTPS audio origin
                request,
                timeout=self.timeout_seconds,
            ) as response:
                final_url = response.geturl()
                content_length = response.headers.get("Content-Length")
        except (urllib.error.HTTPError, OSError, TimeoutError) as exc:
            raise QuranFoundationError("Unable to inspect the external audio asset.") from exc
        final_parsed = urlsplit(final_url)
        if final_parsed.scheme != "https" or final_parsed.hostname not in ALLOWED_AUDIO_HOSTS:
            raise QuranFoundationError(
                "The external audio asset redirected to an unapproved origin."
            )
        try:
            size_bytes = int(content_length or 0)
        except ValueError as exc:
            raise QuranFoundationError("External audio has an invalid Content-Length.") from exc
        if size_bytes <= 0:
            raise QuranFoundationError("External audio is missing Content-Length.")
        return size_bytes

    def _get_json(self, path: str, *, query: dict[str, str]) -> dict[str, Any]:
        token = self._access_token or self._request_token()
        try:
            return self._request_api(path, query=query, token=token)
        except QuranFoundationError as exc:
            if "HTTP 401" not in str(exc):
                raise
        self._access_token = None
        return self._request_api(path, query=query, token=self._request_token())

    def _request_token(self) -> str:
        credentials = base64.b64encode(
            f"{self.client_id}:{self._client_secret}".encode()
        ).decode()
        request = urllib.request.Request(  # noqa: S310 - fixed Quran.Foundation HTTPS origin
            f"{self.environment.oauth_base_url}/oauth2/token",
            data=urllib.parse.urlencode(
                {"grant_type": "client_credentials", "scope": "content"}
            ).encode(),
            headers={
                "Authorization": f"Basic {credentials}",
                "Content-Type": "application/x-www-form-urlencoded",
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
            },
            method="POST",
        )
        payload = self._open_json(request)
        token = payload.get("access_token")
        if not isinstance(token, str) or not token:
            raise QuranFoundationError("Quran.Foundation did not return an access token.")
        self._access_token = token
        return token

    def _request_api(
        self,
        path: str,
        *,
        query: dict[str, str],
        token: str,
    ) -> dict[str, Any]:
        url = f"{self.environment.api_base_url}{path}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(  # noqa: S310 - fixed Quran.Foundation HTTPS origin
            url,
            headers={
                "x-auth-token": token,
                "x-client-id": self.client_id,
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
            },
        )
        return self._open_json(request)

    def _open_json(self, request: urllib.request.Request) -> dict[str, Any]:
        try:
            with urllib.request.urlopen(  # noqa: S310 - fixed HTTPS origins only
                request,
                timeout=self.timeout_seconds,
            ) as response:
                payload = json.load(response)
        except urllib.error.HTTPError as exc:
            raise QuranFoundationError(
                f"Quran.Foundation request failed with HTTP {exc.code}."
            ) from exc
        except (OSError, TimeoutError, json.JSONDecodeError) as exc:
            raise QuranFoundationError("Quran.Foundation request failed.") from exc
        if not isinstance(payload, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid JSON response.")
        return payload
