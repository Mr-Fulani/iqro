# Russian operator strings are asserted verbatim.
# ruff: noqa: RUF001
from __future__ import annotations

import json
import shutil
import subprocess
import uuid
from datetime import timedelta
from pathlib import Path
from typing import Any

import pytest
from django.contrib.auth.models import Group
from django.core.exceptions import PermissionDenied
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import Client, override_settings
from django.utils import timezone
from rest_framework.test import APIClient

from quran_backend.modules.accounts.lifecycle import finalize_due_account_deletions
from quran_backend.modules.accounts.merge import merge_guest_into_account
from quran_backend.modules.accounts.models import (
    AuthIdentity,
    IdentityProvider,
    User,
    UserStatus,
)
from quran_backend.modules.announcements import services as announcement_services
from quran_backend.modules.announcements import tasks as announcement_tasks
from quran_backend.modules.announcements.media import upload_announcement_image
from quran_backend.modules.announcements.models import (
    Announcement,
    AnnouncementDailyStat,
    AnnouncementKind,
    AnnouncementPriority,
    AnnouncementReceipt,
    AnnouncementSettings,
    AnnouncementStatus,
    AnnouncementStep,
    AnnouncementTranslation,
)
from quran_backend.modules.announcements.services import (
    AnnouncementNotReadyError,
    archive,
    duplicate,
    publish,
    readiness,
    set_receipt,
    withdraw,
)
from quran_backend.modules.audio.models import Reciter
from quran_backend.modules.core.object_storage import ImmutableObjectSpec, StoredObject

FFMPEG = shutil.which("ffmpeg") or "ffmpeg"
FFPROBE = shutil.which("ffprobe") or "ffprobe"
needs_ffmpeg = pytest.mark.skipif(
    shutil.which("ffmpeg") is None or shutil.which("ffprobe") is None,
    reason="ffmpeg is not installed",
)

TEXTS = {
    "ru": ("Новый чтец: Хани ар-Рифаи", "Полное чтение Корана, 114 сур.", "Послушать"),
    "en": ("New reciter: Hani ar-Rifai", "The whole Quran, 114 surahs.", "Listen"),
    "ar": ("قارئ جديد: هاني الرفاعي", "تلاوة كاملة للقرآن: 114 سورة.", "استمع"),
}


@pytest.fixture
def recorded_changes(monkeypatch: pytest.MonkeyPatch) -> list[str]:
    actions: list[str] = []

    def record(*, action: str) -> None:
        actions.append(action)

    monkeypatch.setattr(announcement_services, "enqueue_announcements_change", record)
    monkeypatch.setattr(announcement_tasks, "enqueue_announcements_change", record)
    return actions


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="owner@example.test",
        password="temporary-strong-password",
        status=UserStatus.ACTIVE,
        is_staff=True,
        is_superuser=True,
    )


@pytest.fixture
def editor(db: None) -> User:
    user = User.objects.create_user(
        email="editor@example.test",
        password="temporary-strong-password",
        status=UserStatus.ACTIVE,
        is_staff=True,
    )
    user.groups.add(Group.objects.get(name="Редактор объявлений"))
    return User.objects.get(pk=user.pk)


@pytest.fixture
def reciter(db: None) -> Reciter:
    return Reciter.objects.create(
        code="qf-99-hani-ar-rifai",
        name_ar="هاني الرفاعي",
        name_en="Hani ar-Rifai",
        name_ru="Хани ар-Рифаи",
        portrait_object_key="audio/reciter-portraits/hani/portrait.webp",
    )


def _announcement(
    *,
    languages: tuple[str, ...] = ("ru", "en", "ar"),
    **overrides: Any,
) -> Announcement:
    values: dict[str, Any] = {
        "kind": AnnouncementKind.GENERAL,
        "starts_at": timezone.now() - timedelta(hours=1),
    }
    values.update(overrides)
    announcement = Announcement.objects.create(**values)
    for code in languages:
        title, summary, cta = TEXTS[code]
        AnnouncementTranslation.objects.create(
            announcement=announcement,
            language=code,
            title=title,
            summary=summary,
            cta_label=cta,
            image_alt=title,
        )
    return announcement


def _reciter_announcement(reciter: Reciter, **overrides: Any) -> Announcement:
    return _announcement(
        kind=AnnouncementKind.RECITER,
        action_type="reciter",
        action_reciter=reciter.pk,
        **overrides,
    )


def _publish(announcement: Announcement, user: User) -> Announcement:
    return publish(announcement, user, thumbnail=lambda key: f"announcements/thumbs/{key[-8:]}")


def _active(client: APIClient, **params: str) -> dict[str, Any]:
    query = {"platform": "web", "locale": "ru", **params}
    response = client.get("/api/v1/announcements/active", query)
    assert response.status_code == 200, response.content
    return dict(response.json())


# Moderation


@pytest.mark.django_db
def test_publishing_fills_window_languages_and_portrait_thumbnail(
    owner: User,
    reciter: Reciter,
    recorded_changes: list[str],
) -> None:
    announcement = _reciter_announcement(reciter)
    thumbnails: list[str] = []

    def thumbnail(key: str) -> str:
        thumbnails.append(key)
        return "announcements/thumbs/hani.jpg"

    published = publish(announcement, owner, thumbnail=thumbnail)

    assert published.status == AnnouncementStatus.PUBLISHED
    assert published.reviewed_by == owner
    assert published.audience_languages == ["ru", "en", "ar"]
    assert published.ends_at == published.starts_at + timedelta(days=14)
    assert published.thumb_object_key == "announcements/thumbs/hani.jpg"
    assert thumbnails == [reciter.portrait_object_key]
    assert recorded_changes == ["published"]


@pytest.mark.django_db
def test_thumbnail_failure_does_not_block_publication(owner: User, reciter: Reciter) -> None:
    def broken(_key: str) -> str:
        raise OSError("CDN is down")

    published = publish(_reciter_announcement(reciter), owner, thumbnail=broken)

    assert published.status == AnnouncementStatus.PUBLISHED
    assert published.thumb_object_key == ""


@pytest.mark.django_db
def test_readiness_lists_missing_texts_and_requested_languages(reciter: Reciter) -> None:
    announcement = _reciter_announcement(reciter, audience_languages=["ru", "tr"])
    AnnouncementTranslation.objects.filter(announcement=announcement, language="ru").update(
        cta_label="", image_alt=""
    )

    report = readiness(announcement)

    assert not report.ready
    assert "Türkçe: заполните заголовок и «Кратко»." in report.problems
    assert "Русский: заполните текст кнопки." in report.problems
    assert "Русский: опишите картинку для экранного диктора." in report.problems


@pytest.mark.django_db
def test_unfilled_languages_are_left_out_with_a_note() -> None:
    report = readiness(_announcement(languages=("ru",)))

    assert report.ready
    assert report.languages == ["ru"]
    assert "Türkçe не заполнен — эта аудитория объявление не увидит." in report.notes


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("overrides", "problem"),
    [
        (
            {"kind": AnnouncementKind.FUNDRAISING, "channel_bubble": True},
            "Сбор средств не показывается пузырём и окном.",
        ),
        (
            {"channel_modal": True, "channel_bubble": False},
            "Окно с шагами — только для высокого приоритета.",
        ),
        (
            {"channel_modal": True, "priority": AnnouncementPriority.HIGH},
            "Для окна с шагами добавьте шаги.",
        ),
        ({"channel_web_push": True}, "Push — только для высокого приоритета."),
        (
            {"priority": AnnouncementPriority.CRITICAL},
            "Критический приоритет — только для обязательного обновления.",
        ),
        ({"action_type": "screen", "action_slug": "nowhere"}, "Раздел должен быть одним из"),
        (
            {"action_type": "external", "action_url": "https://example.com/pay"},
            "Внешняя ссылка: только HTTPS и только разрешённые сайты.",
        ),
        ({"needs_religious_review": True}, "Нужна подпись проверяющего религиозные тексты."),
    ],
)
def test_channel_and_action_rules_block_publication(
    owner: User,
    overrides: dict[str, Any],
    problem: str,
) -> None:
    announcement = _announcement(**overrides)

    with pytest.raises(AnnouncementNotReadyError) as error:
        publish(announcement, owner)

    assert any(item.startswith(problem) for item in error.value.problems)
    announcement.refresh_from_db()
    assert announcement.status == AnnouncementStatus.DRAFT


@pytest.mark.django_db
def test_steps_must_match_between_languages() -> None:
    announcement = _announcement(languages=("ru", "en"))
    AnnouncementTranslation.objects.filter(language="ru").update(
        steps=[{"title": "Откройте «Намаз»", "text": ""}]
    )
    AnnouncementStep.objects.create(announcement=announcement, order=2, image_object_key="a/b.jpg")

    problems = readiness(announcement).problems

    assert "Число шагов должно совпадать на всех языках." in problems
    assert "Есть иллюстрация для шага, которого нет в текстах." in problems


@pytest.mark.django_db
def test_editor_publishes_ordinary_announcements_but_not_sensitive_ones(
    editor: User,
) -> None:
    assert _publish(_announcement(), editor).status == AnnouncementStatus.PUBLISHED

    fundraising = _announcement(kind=AnnouncementKind.FUNDRAISING, channel_bubble=False)
    with pytest.raises(PermissionDenied):
        _publish(fundraising, editor)

    plain_user = User.objects.create_user(email="nobody@example.test", status=UserStatus.ACTIVE)
    with pytest.raises(PermissionDenied):
        _publish(_announcement(), plain_user)


@pytest.mark.django_db
def test_religious_review_is_signed_by_a_reviewer(owner: User) -> None:
    reviewer = User.objects.create_user(email="scholar@example.test", status=UserStatus.ACTIVE)
    reviewer.groups.add(Group.objects.get(name="Проверяющий религиозные тексты"))
    reviewer = User.objects.get(pk=reviewer.pk)
    announcement = _announcement(needs_religious_review=True)

    announcement_services.sign_religious_review(announcement, reviewer)
    announcement.refresh_from_db()

    assert announcement.religious_reviewed_by == reviewer
    assert _publish(announcement, owner).status == AnnouncementStatus.PUBLISHED


@pytest.mark.django_db
def test_withdraw_archive_and_duplicate(owner: User, recorded_changes: list[str]) -> None:
    announcement = _publish(_announcement(pinned=True), owner)
    AnnouncementStep.objects.create(announcement=announcement, order=1, image_object_key="a/1.jpg")

    with pytest.raises(AnnouncementNotReadyError):
        _publish(announcement, owner)
    withdraw(announcement, owner)
    archive(announcement, owner)
    copy = duplicate(announcement, owner)

    announcement.refresh_from_db()
    assert announcement.status == AnnouncementStatus.ARCHIVED
    assert announcement.withdrawn_at is not None
    assert recorded_changes == ["published", "withdrawn"]
    assert copy.status == AnnouncementStatus.DRAFT
    assert copy.reviewed_by is None
    assert copy.pinned is True
    assert copy.translations.count() == 3
    assert copy.step_images.count() == 1


# Public API


@pytest.mark.django_db
def test_active_announcement_payload(api_client: APIClient, owner: User, reciter: Reciter) -> None:
    announcement = _publish(_reciter_announcement(reciter), owner)

    body = _active(api_client)

    assert body["enabled"] is True
    [item] = body["results"]
    assert item["id"] == str(announcement.id)
    assert item["title"] == "Новый чтец: Хани ар-Рифаи"
    assert item["surfaces"] == {"bubble": True, "home_card": True, "modal": False}
    assert item["bubble"] == {"icon": "portrait", "frequency": "daily", "max_impressions": 5}
    assert item["image"]["url"].endswith("/audio/reciter-portraits/hani/portrait.webp")
    assert item["image"]["thumb_url"].endswith("announcements/thumbs/ait.webp")
    assert item["action"] == {
        "type": "reciter",
        "label": "Послушать",
        "web_path": f"/ru/audio?reciter={reciter.id}&play=1",
        "app_route": f"/audio/reciter/{reciter.id}?play=1",
        "external_url": None,
    }
    arabic = _active(api_client, locale="ar")["results"][0]
    assert arabic["action"]["web_path"].startswith("/ar/audio")
    assert arabic["action"]["label"] == "استمع"


@pytest.mark.django_db
def test_active_response_is_public_and_revalidatable(api_client: APIClient, owner: User) -> None:
    _publish(_announcement(), owner)

    first = api_client.get("/api/v1/announcements/active", {"platform": "web", "locale": "ru"})
    second = api_client.get(
        "/api/v1/announcements/active",
        {"platform": "web", "locale": "ru"},
        HTTP_IF_NONE_MATCH=first["ETag"],
    )

    assert first["Cache-Control"].startswith("public")
    assert second.status_code == 304


@pytest.mark.django_db
def test_active_filters_window_language_platform_and_version(
    api_client: APIClient,
    owner: User,
) -> None:
    now = timezone.now()
    visible = _publish(_announcement(), owner)
    _publish(_announcement(starts_at=now + timedelta(hours=1)), owner)
    _publish(
        _announcement(starts_at=now - timedelta(days=3), ends_at=now - timedelta(days=1)),
        owner,
    )
    _publish(_announcement(audience_platforms=["android"]), owner)
    app_only_new = _publish(
        _announcement(audience_platforms=["android", "ios"], app_version_min="1.2"),
        owner,
    )
    _publish(_announcement(channel_bubble=False, channel_home_card=False), owner)
    _announcement()

    def ids(**params: str) -> list[str]:
        return [item["id"] for item in _active(api_client, **params)["results"]]

    assert ids() == [str(visible.id)]
    assert ids(locale="tr") == []
    assert str(app_only_new.id) not in ids(platform="android", app_version="1.1.9")
    assert str(app_only_new.id) in ids(platform="ios", app_version="1.2.0")


@pytest.mark.django_db
def test_fundraising_is_shown_on_the_site_only(api_client: APIClient, owner: User) -> None:
    _publish(_announcement(kind=AnnouncementKind.FUNDRAISING, channel_bubble=False), owner)

    assert len(_active(api_client)["results"]) == 1
    assert _active(api_client, platform="android")["results"] == []
    assert _active(api_client, platform="ios")["results"] == []


@pytest.mark.django_db
def test_switch_hides_every_announcement(api_client: APIClient, owner: User) -> None:
    announcement = _publish(_announcement(), owner)
    AnnouncementSettings.objects.create(is_enabled=False)

    body = _active(api_client)
    feed = api_client.get("/api/v1/announcements", {"platform": "web", "locale": "ru"}).json()
    detail = api_client.get(
        f"/api/v1/announcements/{announcement.id}", {"platform": "web", "locale": "ru"}
    )

    assert body == {"enabled": False, "results": []}
    assert feed["results"] == []
    assert detail.status_code == 404


@pytest.mark.django_db
def test_feed_pins_first_pages_with_a_cursor_and_filters_kind(
    api_client: APIClient,
    owner: User,
) -> None:
    now = timezone.now()
    regular = [
        _publish(_announcement(starts_at=now - timedelta(hours=index + 1)), owner)
        for index in range(22)
    ]
    pinned = _publish(_announcement(starts_at=now - timedelta(days=30), pinned=True), owner)
    reciter_news = _publish(
        _announcement(kind=AnnouncementKind.CONTENT, starts_at=now - timedelta(days=40)),
        owner,
    )
    withdrawn = _publish(_announcement(), owner)
    withdraw(withdrawn, owner)
    _announcement()

    first = api_client.get("/api/v1/announcements", {"platform": "web", "locale": "ru"}).json()
    second = api_client.get(
        "/api/v1/announcements",
        {"platform": "web", "locale": "ru", "cursor": first["next_cursor"]},
    ).json()
    content = api_client.get(
        "/api/v1/announcements",
        {"platform": "web", "locale": "ru", "kind": "content"},
    ).json()

    first_ids = [item["id"] for item in first["results"]]
    second_ids = [item["id"] for item in second["results"]]
    assert first_ids[0] == str(pinned.id)
    assert first_ids[1:] == [str(item.id) for item in regular[:20]]
    assert second_ids == [*(str(item.id) for item in regular[20:]), str(reciter_news.id)]
    assert second["next_cursor"] is None
    assert str(withdrawn.id) not in first_ids + second_ids
    assert [item["id"] for item in content["results"]] == [str(reciter_news.id)]


@pytest.mark.django_db
def test_feed_rejects_a_forged_cursor(api_client: APIClient) -> None:
    response = api_client.get(
        "/api/v1/announcements",
        {"platform": "web", "locale": "ru", "cursor": "not-a-cursor"},
    )

    assert response.status_code == 400


@pytest.mark.django_db
def test_detail_shows_only_published_started_announcements(
    api_client: APIClient,
    owner: User,
) -> None:
    published = _publish(_announcement(), owner)
    draft = _announcement()
    query = {"platform": "android", "locale": "en"}

    assert api_client.get(f"/api/v1/announcements/{published.id}", query).status_code == 200
    assert api_client.get(f"/api/v1/announcements/{draft.id}", query).status_code == 404
    assert api_client.get(f"/api/v1/announcements/{uuid.uuid7()}", query).status_code == 404


@pytest.mark.django_db
@override_settings(ANNOUNCEMENT_EXTERNAL_HOSTS=frozenset({"iqro.forum"}))
def test_external_link_redirects_through_the_server_and_counts_a_click(
    api_client: APIClient,
    owner: User,
) -> None:
    announcement = _publish(
        _announcement(action_type="external", action_url="https://iqro.forum/support"),
        owner,
    )
    item = _active(api_client)["results"][0]

    response = api_client.get(
        item["action"]["external_url"], {"platform": "web", "surface": "card"}
    )

    assert item["action"]["external_url"] == f"/api/v1/announcements/{announcement.id}/go"
    assert response.status_code == 302
    assert response["Location"] == "https://iqro.forum/support"
    stat = AnnouncementDailyStat.objects.get(announcement=announcement)
    assert (stat.platform, stat.surface, stat.event, stat.count) == ("web", "card", "click", 1)


@pytest.mark.django_db
def test_events_keep_only_daily_sums_of_published_announcements(
    api_client: APIClient,
    owner: User,
) -> None:
    announcement = _publish(_announcement(), owner)
    draft = _announcement()
    event = {"id": str(announcement.id), "surface": "bubble", "event": "impression"}

    response = api_client.post(
        "/api/v1/announcements/events",
        {
            "platform": "android",
            "events": [
                event,
                event,
                {"id": str(announcement.id), "surface": "bubble", "event": "open"},
                {"id": str(draft.id), "surface": "bubble", "event": "impression"},
            ],
        },
        format="json",
    )
    api_client.post(
        "/api/v1/announcements/events",
        {"platform": "android", "events": [event]},
        format="json",
    )

    assert response.status_code == 202
    assert response.json() == {"accepted": 3}
    counts = {
        (row.surface, row.event): row.count
        for row in AnnouncementDailyStat.objects.filter(announcement=announcement)
    }
    assert counts == {("bubble", "impression"): 3, ("bubble", "open"): 1}
    assert not AnnouncementDailyStat.objects.filter(announcement=draft).exists()
    stored = {field.name for field in AnnouncementDailyStat._meta.get_fields()}
    assert stored == {"id", "date", "announcement", "platform", "surface", "event", "count"}


@pytest.mark.django_db
def test_events_reject_unknown_surfaces(api_client: APIClient) -> None:
    response = api_client.post(
        "/api/v1/announcements/events",
        {"platform": "web", "events": [{"id": str(uuid.uuid7()), "surface": "x", "event": "y"}]},
        format="json",
    )

    assert response.status_code == 400


# Read and dismissed marks


@pytest.mark.django_db
def test_receipts_only_move_forward(api_client: APIClient, owner: User) -> None:
    announcement = _publish(_announcement(), owner)
    reader = User.objects.create_user(status=UserStatus.GUEST)
    api_client.force_authenticate(user=reader)
    url = f"/api/v1/me/announcement-receipts/{announcement.id}"

    read = api_client.put(url, {"read": True}, format="json").json()
    dismissed = api_client.put(url, {"dismissed": True}, format="json").json()
    unchanged = api_client.put(url, {"read": False, "dismissed": False}, format="json").json()
    listing = api_client.get("/api/v1/me/announcement-receipts")

    assert read["read_at"] is not None
    assert read["dismissed_at"] is None
    assert dismissed["read_at"] == read["read_at"]
    assert dismissed["dismissed_at"] is not None
    assert unchanged == dismissed
    assert listing["Cache-Control"].startswith("private, no-store")
    assert listing.json() == {"results": [dismissed]}


@pytest.mark.django_db
def test_receipts_need_a_session_and_a_published_announcement(
    api_client: APIClient,
) -> None:
    draft = _announcement()
    url = f"/api/v1/me/announcement-receipts/{draft.id}"

    assert api_client.put(url, {"read": True}, format="json").status_code == 401
    api_client.force_authenticate(user=User.objects.create_user(status=UserStatus.GUEST))
    assert api_client.put(url, {"read": True}, format="json").status_code == 404


@pytest.mark.django_db
def test_guest_receipts_join_the_account_keeping_the_earliest_marks(owner: User) -> None:
    first = _publish(_announcement(), owner)
    second = _publish(_announcement(), owner)
    guest = User.objects.create_user(status=UserStatus.GUEST)
    target = User.objects.create_user(email="reader@example.com", status=UserStatus.ACTIVE)
    identity = AuthIdentity.objects.create(
        user=target,
        provider=IdentityProvider.EMAIL,
        provider_subject="reader@example.com",
        email_at_provider="reader@example.com",
        email_verified=True,
    )
    earlier = set_receipt(user=guest, announcement=first, read=True, dismissed=False)
    later = set_receipt(user=target, announcement=first, read=True, dismissed=True)
    set_receipt(user=guest, announcement=second, read=False, dismissed=True)

    result = merge_guest_into_account(
        source_user=guest,
        target_user=target,
        trigger_identity=identity,
        idempotency_key=uuid.uuid4(),
    )

    merged = AnnouncementReceipt.objects.get(user=target, announcement=first)
    assert result.moved_counts["announcement_receipts"] == 2
    assert merged.read_at == earlier.read_at
    assert merged.dismissed_at == later.dismissed_at
    assert AnnouncementReceipt.objects.filter(user=target).count() == 2
    assert not AnnouncementReceipt.objects.filter(user=guest).exists()


@pytest.mark.django_db
def test_account_deletion_removes_receipts(owner: User) -> None:
    announcement = _publish(_announcement(), owner)
    user = User.objects.create_user(email="leaving@example.com", status=UserStatus.ACTIVE)
    set_receipt(user=user, announcement=announcement, read=True, dismissed=False)
    requested_at = timezone.now() - timedelta(days=8)
    User.objects.filter(id=user.id).update(
        status=UserStatus.PENDING_DELETION,
        deletion_requested_at=requested_at,
        deletion_scheduled_for=requested_at + timedelta(days=7),
    )

    finalize_due_account_deletions(now=timezone.now())

    assert not AnnouncementReceipt.objects.filter(user=user).exists()


# Site cache


@pytest.mark.django_db
def test_window_changes_refresh_the_site_once(owner: User, recorded_changes: list[str]) -> None:
    announcement = _publish(_announcement(), owner)
    recorded_changes.clear()
    AnnouncementSettings.objects.create(window_checked_at=timezone.now() - timedelta(minutes=5))
    Announcement.objects.filter(pk=announcement.pk).update(
        ends_at=timezone.now() - timedelta(minutes=1)
    )

    assert announcement_tasks.revalidate_window_changes() is True
    assert announcement_tasks.revalidate_window_changes() is False
    assert recorded_changes == ["scheduled"]


# Admin


@pytest.mark.django_db
def test_admin_pages_show_language_tabs_preview_and_sign_off(
    owner: User,
    reciter: Reciter,
) -> None:
    client = Client()
    client.force_login(owner)
    draft = _reciter_announcement(reciter)
    published = _publish(_announcement(), owner)

    add_page = client.get("/admin/announcements/announcement/add/")
    draft_page = client.get(f"/admin/announcements/announcement/{draft.pk}/change/")
    published_page = client.get(f"/admin/announcements/announcement/{published.pk}/change/")
    listing = client.get("/admin/announcements/announcement/")

    assert add_page.status_code == 200
    assert 'id="announcement-language-names"' in add_page.content.decode()
    draft_body = draft_page.content.decode()
    assert "Подписать и опубликовать" in draft_body
    assert "Готово к подписи." in draft_body
    assert 'dir="rtl" lang="ar"' in draft_body
    assert "قارئ جديد" in draft_body
    published_body = published_page.content.decode()
    assert "Снять с публикации" in published_body
    assert "Подписать и опубликовать" not in published_body
    assert listing.status_code == 200


@pytest.mark.django_db
def test_admin_publish_button_reports_problems(owner: User) -> None:
    client = Client()
    client.force_login(owner)
    announcement = _announcement(languages=())

    response = client.post(
        f"/admin/announcements/announcement/{announcement.pk}/change/",
        _change_form_data(announcement) | {"_publish": "1"},
        follow=True,
    )

    assert response.status_code == 200
    assert "Заполните текст хотя бы на одном языке." in response.content.decode()
    announcement.refresh_from_db()
    assert announcement.status == AnnouncementStatus.DRAFT


def _change_form_data(announcement: Announcement) -> dict[str, Any]:
    starts_at = timezone.localtime(announcement.starts_at)
    data: dict[str, Any] = {
        "kind": announcement.kind,
        "priority": announcement.priority,
        "starts_at_0": starts_at.strftime("%Y-%m-%d"),
        "starts_at_1": starts_at.strftime("%H:%M:%S"),
        "action_type": announcement.action_type,
        "audience_platforms": ["web", "android", "ios"],
        "audience_auth": announcement.audience_auth,
        "channel_bubble": "on",
        "channel_home_card": "on",
        "bubble_frequency": announcement.bubble_frequency,
        "bubble_max_impressions": announcement.bubble_max_impressions,
        "bubble_icon": announcement.bubble_icon,
        "translations-TOTAL_FORMS": "4",
        "translations-INITIAL_FORMS": "0",
        "translations-MIN_NUM_FORMS": "0",
        "translations-MAX_NUM_FORMS": "4",
        "step_images-TOTAL_FORMS": "0",
        "step_images-INITIAL_FORMS": "0",
        "step_images-MIN_NUM_FORMS": "0",
        "step_images-MAX_NUM_FORMS": "5",
    }
    for index in range(4):
        data[f"translations-{index}-announcement"] = str(announcement.pk)
    return data


# Media


class RecordingUploader:
    def __init__(self, folder: Path) -> None:
        self.folder = folder
        self.calls: list[ImmutableObjectSpec] = []

    def upload_path(self, source_path: Path, spec: ImmutableObjectSpec) -> StoredObject:
        shutil.copy(source_path, self.folder / Path(spec.key).name)
        self.calls.append(spec)
        return StoredObject(key=spec.key, etag='"etag"', created=True)


@needs_ffmpeg
def test_uploaded_image_gets_its_size_and_a_96px_thumbnail(tmp_path: Path) -> None:
    source = tmp_path / "wide.jpg"
    subprocess.run(  # noqa: S603 - fixed test program
        [
            FFMPEG,
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "color=c=green:s=640x360",
            "-frames:v",
            "1",
            str(source),
        ],
        check=True,
    )
    uploader = RecordingUploader(tmp_path)

    image = upload_announcement_image(
        SimpleUploadedFile("wide.jpg", source.read_bytes(), content_type="image/jpeg"),
        uploader=uploader,
        ffmpeg=FFMPEG,
        ffprobe=FFPROBE,
    )

    assert (image.width, image.height) == (640, 360)
    assert image.object_key.startswith("announcements/images/")
    assert image.thumb_object_key.startswith("announcements/thumbs/")
    probe = subprocess.run(  # noqa: S603 - test-made file
        [
            FFPROBE,
            "-v",
            "error",
            "-show_streams",
            "-of",
            "json",
            str(tmp_path / Path(image.thumb_object_key).name),
        ],
        check=True,
        capture_output=True,
    )
    stream = json.loads(probe.stdout)["streams"][0]
    assert (stream["width"], stream["height"]) == (96, 96)


def test_upload_rejects_formats_other_than_webp_and_jpeg(tmp_path: Path) -> None:
    from quran_backend.modules.announcements.media import AnnouncementMediaError  # noqa: PLC0415

    with pytest.raises(AnnouncementMediaError, match="WebP и JPEG"):
        upload_announcement_image(
            SimpleUploadedFile("x.png", b"\x89PNG\r\n\x1a\n" + b"0" * 32),
            uploader=RecordingUploader(tmp_path),
        )
