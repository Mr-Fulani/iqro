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

from django.conf import settings


class QuranFoundationError(RuntimeError):
    """A safe, credential-free Quran.Foundation integration error."""


@dataclass(frozen=True, slots=True)
class QuranFoundationEnvironment:
    name: str
    oauth_base_url: str
    api_base_url: str


@dataclass(frozen=True, slots=True)
class QuranFoundationSyncResult:
    next_sync_token: str
    sync_until_sequence: int
    mutations: tuple[dict[str, Any], ...]


@dataclass(frozen=True, slots=True)
class QuranFoundationMushafSyncResult:
    next_sync_token: str
    sync_until_sequence: int
    mutations: tuple[dict[str, Any], ...]


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
AYAH_AUDIO_BASE_URL = "https://verses.quran.foundation"
ALLOWED_AYAH_AUDIO_HOSTS = {
    "mirrors.quranicaudio.com",
    "verses.quran.foundation",
}


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
        environment_name = settings.QURAN_QF_ENV
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

    def list_ayah_recitations(self, *, language: str = "en") -> list[dict[str, Any]]:
        payload = self._get_json(
            "/content/api/v4/resources/recitations",
            query={"language": language},
        )
        recitations = payload.get("recitations")
        if not isinstance(recitations, list):
            raise QuranFoundationError("Quran.Foundation returned an invalid recitation catalog.")
        return [row for row in recitations if isinstance(row, dict)]

    def get_ayah_recitation_audio(self, recitation_id: int) -> dict[str, Any]:
        if recitation_id <= 0:
            raise QuranFoundationError("Ayah recitation IDs must be positive.")
        payload = self._get_json(
            f"/content/api/v4/quran/recitations/{recitation_id}",
            query={},
        )
        audio_files = payload.get("audio_files")
        meta = payload.get("meta")
        if not isinstance(audio_files, list) or not isinstance(meta, dict):
            raise QuranFoundationError(
                "Quran.Foundation returned invalid ayah recitation metadata."
            )
        if not all(isinstance(row, dict) for row in audio_files):
            raise QuranFoundationError("Quran.Foundation returned an invalid ayah audio file.")
        return {"audio_files": audio_files, "meta": meta}

    def normalize_ayah_audio_url(self, value: object) -> str:
        if not isinstance(value, str) or not value.strip():
            raise QuranFoundationError("Quran.Foundation returned an invalid ayah audio URL.")
        raw_url = value.strip()
        parsed = urlsplit(raw_url)
        if parsed.netloc and not parsed.scheme:
            candidate = f"https:{raw_url}"
        elif parsed.scheme or parsed.netloc:
            candidate = raw_url
        else:
            if parsed.query or parsed.fragment:
                raise QuranFoundationError(
                    "Quran.Foundation returned an invalid relative ayah audio URL."
                )
            path_parts = [part for part in parsed.path.split("/") if part]
            if not path_parts or any(part in {".", ".."} for part in path_parts):
                raise QuranFoundationError(
                    "Quran.Foundation returned an unsafe relative ayah audio URL."
                )
            candidate = f"{AYAH_AUDIO_BASE_URL}/{'/'.join(path_parts)}"
        final = urlsplit(candidate)
        if (
            final.scheme != "https"
            or final.hostname not in ALLOWED_AYAH_AUDIO_HOSTS
            or final.username is not None
            or final.password is not None
            or final.query
            or final.fragment
            or not final.path.lower().endswith(".mp3")
        ):
            raise QuranFoundationError("Quran.Foundation returned an unapproved ayah audio URL.")
        return candidate

    def sync_recitation_content(
        self,
        resource_id: int,
        *,
        sync_token: str = "",
    ) -> QuranFoundationSyncResult:
        if resource_id <= 0:
            raise QuranFoundationError("Content Sync resource IDs must be positive.")
        query = {
            "resources": f"recitations:{resource_id}",
            "per_page": "100",
        }
        if sync_token:
            query["sync_token"] = sync_token
        else:
            query["bootstrap"] = "true"

        mutations: list[dict[str, Any]] = []
        final_token = ""
        sync_until_sequence = 0
        for _ in range(100):
            payload = self._get_json("/content/api/v4/resources/sync", query=query)
            page_sequence, page_mutations, has_more, next_page_url, next_token = (
                self._parse_sync_page(payload, resource_id)
            )
            if sync_until_sequence and page_sequence != sync_until_sequence:
                raise QuranFoundationError("Quran.Foundation changed sequence during sync paging.")
            sync_until_sequence = page_sequence
            mutations.extend(page_mutations)
            if not has_more:
                final_token = next_token
                break
            query = self._sync_cursor_query(next_page_url)
        else:
            raise QuranFoundationError("Quran.Foundation sync exceeded the page safety limit.")

        mutations.sort(key=lambda row: int(row["sequence"]))
        return QuranFoundationSyncResult(
            next_sync_token=final_token,
            sync_until_sequence=sync_until_sequence,
            mutations=tuple(mutations),
        )

    def sync_mushaf_catalog(
        self,
        *,
        sync_token: str = "",
    ) -> QuranFoundationMushafSyncResult:
        query = {
            "resources": "mushafs:*",
            "per_page": "100",
        }
        if sync_token:
            query["sync_token"] = sync_token
        else:
            query["bootstrap"] = "true"

        mutations: list[dict[str, Any]] = []
        final_token = ""
        sync_until_sequence = 0
        for _ in range(100):
            payload = self._get_json("/content/api/v4/resources/sync", query=query)
            page_sequence, page_mutations, has_more, next_page_url, next_token = (
                self._parse_mushaf_sync_page(payload)
            )
            if sync_until_sequence and page_sequence != sync_until_sequence:
                raise QuranFoundationError("Quran.Foundation changed sequence during sync paging.")
            sync_until_sequence = page_sequence
            mutations.extend(page_mutations)
            if not has_more:
                final_token = next_token
                break
            query = self._sync_cursor_query(next_page_url)
        else:
            raise QuranFoundationError("Quran.Foundation sync exceeded the page safety limit.")

        mutations.sort(key=lambda row: int(row["sequence"]))
        return QuranFoundationMushafSyncResult(
            next_sync_token=final_token,
            sync_until_sequence=sync_until_sequence,
            mutations=tuple(mutations),
        )

    def get_mushaf_snapshot(self, resource_id: int) -> dict[str, Any]:
        if resource_id <= 0:
            raise QuranFoundationError("Quran.Foundation Mushaf IDs must be positive.")
        payload = self._get_json(
            f"/content/api/v4/resources/snapshots/mushafs/{resource_id}",
            query={},
        )
        if payload.get("resource_group") != "mushafs":
            raise QuranFoundationError("Quran.Foundation returned the wrong snapshot group.")
        try:
            returned_id = int(payload.get("resource_id", 0))
            sync_sequence = int(payload.get("sync_sequence", -1))
        except (TypeError, ValueError) as exc:
            raise QuranFoundationError(
                "Quran.Foundation returned an invalid Mushaf snapshot."
            ) from exc
        if (
            returned_id != resource_id
            or sync_sequence < 0
            or not isinstance(payload.get("records"), list)
        ):
            raise QuranFoundationError("Quran.Foundation returned an invalid Mushaf snapshot.")
        return payload

    def _parse_mushaf_sync_page(
        self,
        payload: dict[str, Any],
    ) -> tuple[int, list[dict[str, Any]], bool, object, str]:
        sync = payload.get("sync")
        if not isinstance(sync, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid sync page.")
        try:
            page_sequence = int(sync["sync_until_sequence"])
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationError(
                "Quran.Foundation returned an invalid sync sequence."
            ) from exc
        raw_mutations = sync.get("mutations")
        if not isinstance(raw_mutations, list):
            raise QuranFoundationError("Quran.Foundation returned invalid sync mutations.")
        mutations = [self._validate_mushaf_mutation(mutation) for mutation in raw_mutations]
        has_more = sync.get("has_more")
        if not isinstance(has_more, bool):
            raise QuranFoundationError("Quran.Foundation returned invalid sync pagination.")
        next_token = sync.get("next_sync_token")
        if not has_more and (not isinstance(next_token, str) or not next_token):
            raise QuranFoundationError("Quran.Foundation omitted the final sync token.")
        return page_sequence, mutations, has_more, sync.get("next_page_url"), str(next_token or "")

    def _parse_sync_page(
        self,
        payload: dict[str, Any],
        resource_id: int,
    ) -> tuple[int, list[dict[str, Any]], bool, object, str]:
        sync = payload.get("sync")
        if not isinstance(sync, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid sync page.")
        try:
            page_sequence = int(sync["sync_until_sequence"])
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationError(
                "Quran.Foundation returned an invalid sync sequence."
            ) from exc
        raw_mutations = sync.get("mutations")
        if not isinstance(raw_mutations, list):
            raise QuranFoundationError("Quran.Foundation returned invalid sync mutations.")
        mutations: list[dict[str, Any]] = []
        for mutation in raw_mutations:
            parsed = self._validate_recitation_mutation(mutation, resource_id)
            snapshot_url = parsed.get("snapshot_url")
            if snapshot_url:
                parsed["snapshot"] = self._get_recitation_snapshot(
                    str(snapshot_url),
                    resource_id,
                )
            mutations.append(parsed)
        has_more = sync.get("has_more")
        if not isinstance(has_more, bool):
            raise QuranFoundationError("Quran.Foundation returned invalid sync pagination.")
        next_token = sync.get("next_sync_token")
        if not has_more and (not isinstance(next_token, str) or not next_token):
            raise QuranFoundationError("Quran.Foundation omitted the final sync token.")
        return page_sequence, mutations, has_more, sync.get("next_page_url"), str(next_token or "")

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
        return self._get_external_audio_size(url, allowed_hosts=ALLOWED_AUDIO_HOSTS)

    def get_external_ayah_audio_size(self, url: str) -> int:
        return self._get_external_audio_size(url, allowed_hosts=ALLOWED_AYAH_AUDIO_HOSTS)

    def _get_external_audio_size(self, url: str, *, allowed_hosts: set[str]) -> int:
        parsed = urlsplit(url)
        if (
            parsed.scheme != "https"
            or parsed.hostname not in allowed_hosts
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
        if final_parsed.scheme != "https" or final_parsed.hostname not in allowed_hosts:
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

    def _get_recitation_snapshot(self, snapshot_url: str, resource_id: int) -> dict[str, Any]:
        parsed = urllib.parse.urlsplit(snapshot_url)
        expected_path = f"/api/v4/resources/snapshots/recitations/{resource_id}"
        if (
            parsed.scheme
            or parsed.netloc
            or parsed.path != expected_path
            or parsed.query
            or parsed.fragment
        ):
            raise QuranFoundationError("Quran.Foundation returned an invalid snapshot URL.")
        payload = self._get_json(f"/content{expected_path}", query={})
        if payload.get("resource_group") != "recitations":
            raise QuranFoundationError("Quran.Foundation returned the wrong snapshot group.")
        try:
            returned_id = int(payload.get("resource_id", 0))
        except (TypeError, ValueError) as exc:
            raise QuranFoundationError("Quran.Foundation returned an invalid snapshot ID.") from exc
        if returned_id != resource_id or not isinstance(payload.get("records"), list):
            raise QuranFoundationError("Quran.Foundation returned an invalid recitation snapshot.")
        return payload

    @staticmethod
    def _sync_cursor_query(next_page_url: object) -> dict[str, str]:
        if not isinstance(next_page_url, str):
            raise QuranFoundationError("Quran.Foundation omitted the next sync page.")
        parsed = urllib.parse.urlsplit(next_page_url)
        if (
            parsed.scheme
            or parsed.netloc
            or parsed.path != "/api/v4/resources/sync"
            or parsed.fragment
        ):
            raise QuranFoundationError("Quran.Foundation returned an invalid next sync URL.")
        try:
            values = urllib.parse.parse_qs(parsed.query, strict_parsing=True)
        except ValueError as exc:
            raise QuranFoundationError("Quran.Foundation returned an invalid sync cursor.") from exc
        cursor_values = values.get("cursor", [])
        if len(cursor_values) != 1 or not cursor_values[0]:
            raise QuranFoundationError("Quran.Foundation returned an invalid sync cursor.")
        return {"cursor": cursor_values[0]}

    @staticmethod
    def _validate_recitation_mutation(
        mutation: object,
        resource_id: int,
    ) -> dict[str, Any]:
        if not isinstance(mutation, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid sync mutation.")
        try:
            sequence = int(mutation["sequence"])
            returned_id = int(mutation["resource_id"])
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationError(
                "Quran.Foundation returned an invalid sync mutation identity."
            ) from exc
        mutation_type = mutation.get("type")
        allowed_types = {
            "RESOURCE_CREATE",
            "RESOURCE_INVALIDATE",
            "RESOURCE_DELETE",
            "RESOURCE_UPDATE",
            "ROW_CREATE",
            "ROW_UPDATE",
            "ROW_DELETE",
        }
        if (
            sequence < 0
            or returned_id != resource_id
            or mutation.get("resource_group") != "recitations"
            or mutation_type not in allowed_types
        ):
            raise QuranFoundationError("Quran.Foundation returned an unrelated sync mutation.")
        snapshot_url = mutation.get("snapshot_url")
        if snapshot_url is not None and not isinstance(snapshot_url, str):
            raise QuranFoundationError("Quran.Foundation returned an invalid snapshot reference.")
        return dict(mutation)

    @staticmethod
    def _validate_mushaf_mutation(mutation: object) -> dict[str, Any]:
        if not isinstance(mutation, dict):
            raise QuranFoundationError("Quran.Foundation returned an invalid sync mutation.")
        try:
            sequence = int(mutation["sequence"])
            resource_id = int(mutation["resource_id"])
        except (KeyError, TypeError, ValueError) as exc:
            raise QuranFoundationError(
                "Quran.Foundation returned an invalid Mushaf mutation identity."
            ) from exc
        allowed_types = {
            "RESOURCE_CREATE",
            "RESOURCE_INVALIDATE",
            "RESOURCE_DELETE",
            "RESOURCE_UPDATE",
            "ROW_CREATE",
            "ROW_UPDATE",
            "ROW_DELETE",
        }
        mutation_type = mutation.get("type")
        if (
            sequence < 0
            or resource_id <= 0
            or mutation.get("resource_group") != "mushafs"
            or mutation_type not in allowed_types
        ):
            raise QuranFoundationError("Quran.Foundation returned an unrelated Mushaf mutation.")
        snapshot_url = mutation.get("snapshot_url")
        if snapshot_url is not None:
            expected_path = f"/api/v4/resources/snapshots/mushafs/{resource_id}"
            if snapshot_url != expected_path:
                raise QuranFoundationError(
                    "Quran.Foundation returned an invalid Mushaf snapshot reference."
                )
        return dict(mutation)

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
        credentials = base64.b64encode(f"{self.client_id}:{self._client_secret}".encode()).decode()
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
