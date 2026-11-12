# Operator-facing text is intentionally Russian.
# ruff: noqa: RUF001
from __future__ import annotations

import json
from typing import Any
from unittest.mock import patch

import pytest
from django.core.exceptions import ValidationError
from django.core.management import call_command
from django.db import IntegrityError
from django.test import Client
from django.urls import reverse
from rest_framework.test import APIClient

from quran_backend.admin_site import placement
from quran_backend.modules.accounts.models import User
from quran_backend.modules.names.models import (
    DivineName,
    NamesCollection,
    NamesDocument,
    NamesStatus,
    NamesVersion,
)
from quran_backend.modules.names.publication import (
    NamesError,
    copy_names_version,
    import_names,
    publish_names_version,
    sign_names_version,
    version_problems,
)

LANGUAGES = ("ru", "en", "tr", "ar")


def _all(text: str, languages: tuple[str, ...] = LANGUAGES) -> dict[str, str]:
    return {language: f"{text} [{language}]" for language in languages}


def _data(version: str = "v1") -> dict[str, Any]:
    return {
        "schema_version": 1,
        "collection": {"slug": "asma-al-husna", "version": version},
        "list_source": _all("Книга списка"),
        "tafsir_source": _all("Книга толкований"),
        "names": [
            {
                "slug": "ar-rahman",
                "arabic": "الرَّحْمَٰنُ",
                "transliteration": _all("Ар-Рахман", ("ru", "en", "tr")),
                "meaning": _all("Милостивый"),
                "tafsir": _all("Толкование первого имени"),
                "tafsir_ref": "с. 5",
                "ayah": {"surah": 55, "ayah": 1, "word": 1},
            },
            {
                "slug": "al-jamil",
                "arabic": "الْجَمِيلُ",
                "transliteration": _all("Аль-Джамиль", ("ru", "en", "tr")),
                "meaning": _all("Прекрасный"),
                "tafsir": _all("Толкование второго имени"),
            },
        ],
    }


@pytest.fixture
def owner(db: None) -> User:
    return User.objects.create_user(
        email="names-owner@example.test", status="active", is_staff=True, is_superuser=True
    )


def _published(owner: User, version: str = "v1") -> NamesVersion:
    draft = import_names(_data(version))
    sign_names_version(draft, owner)
    return publish_names_version(draft)


def _url(slug: str = "asma-al-husna") -> str:
    return reverse("names-collection", args=[slug])


@pytest.mark.django_db
def test_import_creates_a_draft_and_is_repeatable() -> None:
    version = import_names(_data())
    assert version.status == NamesStatus.DRAFT
    assert version.list_source_tr == "Книга списка [tr]"
    assert [(name.position, name.slug) for name in version.names.all()] == [
        (1, "ar-rahman"),
        (2, "al-jamil"),
    ]
    first = version.names.get(position=1)
    assert (first.surah, first.ayah, first.word_position) == (55, 1, 1)
    assert first.transliteration_en == "Ар-Рахман [en]"
    # The same version again changes nothing: the owner's edits in the admin stay.
    first.meaning_ru = "Правка владельца"
    first.save()
    assert import_names(_data()).pk == version.pk
    assert DivineName.objects.count() == 2
    assert version.names.get(position=1).meaning_ru == "Правка владельца"


@pytest.mark.django_db
@pytest.mark.parametrize(
    ("change", "message"),
    [
        (lambda data: data.update(schema_version=2), "schema_version"),
        (lambda data: data.update(names=[]), "names"),
        (lambda data: data["names"][1].update(slug="ar-rahman"), "повторяются"),
        (lambda data: data["names"][0].update(arabic=""), "Имя 1"),
        (lambda data: data["names"][0]["ayah"].update(surah=115), "Имя 1"),
        (lambda data: data["names"][0]["ayah"].update(ayah=None), "Имя 1"),
    ],
)
def test_import_rejects_a_broken_file(change: Any, message: str) -> None:
    data = _data()
    change(data)
    with pytest.raises(NamesError, match=message):
        import_names(data)
    assert not NamesVersion.objects.exists()


@pytest.mark.django_db
def test_a_draft_is_not_served(api_client: APIClient) -> None:
    import_names(_data())
    assert api_client.get(_url()).status_code == 404


@pytest.mark.django_db
def test_signing_needs_every_text_in_every_language(owner: User) -> None:
    version = import_names(_data())
    name = version.names.get(position=2)
    name.tafsir_tr = ""
    name.transliteration_en = " "
    name.save()
    version.tafsir_source_ar = ""
    version.save()
    problems = version_problems(version)
    assert len(problems) == 2
    assert "арабский" in problems[0]
    assert "толкование [tr]" in problems[1]
    assert "имя буквами языка [en]" in problems[1]
    with pytest.raises(NamesError):
        sign_names_version(version, owner)
    version.refresh_from_db()
    assert not version.is_signed


@pytest.mark.django_db
def test_numbers_must_run_without_gaps(owner: User) -> None:
    version = import_names(_data())
    version.names.filter(position=2).update(position=3)
    assert any("подряд" in problem for problem in version_problems(version))


@pytest.mark.django_db
def test_publication_serves_the_list_in_the_asked_language(
    owner: User, api_client: APIClient
) -> None:
    draft = import_names(_data())
    with pytest.raises(NamesError, match="подписать"):
        publish_names_version(draft)
    sign_names_version(draft, owner)
    with patch(
        "quran_backend.modules.names.publication.enqueue_names_content_change"
    ) as revalidate:
        version = publish_names_version(draft)
    revalidate.assert_called_once_with(action="activated", collection="asma-al-husna", version="v1")
    assert version.status == NamesStatus.PUBLISHED
    assert NamesDocument.objects.filter(version=version).count() == 4

    response = api_client.get(_url(), {"language": "tr"})
    assert response.status_code == 200
    assert response["Cache-Control"].startswith("public")
    body = response.json()
    assert body["collection"] == {
        "slug": "asma-al-husna",
        "version": "v1",
        "language": "tr",
        "published_at": version.published_at.isoformat(),
        "list_source": "Книга списка [tr]",
        "tafsir_source": "Книга толкований [tr]",
    }
    assert body["names"][0] == {
        "slug": "ar-rahman",
        "position": 1,
        "arabic": "الرَّحْمَٰنُ",
        "transliteration": "Ар-Рахман [tr]",
        "meaning": "Милостивый [tr]",
        "tafsir": "Толкование первого имени [tr]",
        "tafsir_ref": "с. 5",
        "ayah": {"surah": 55, "ayah": 1, "word": 1},
    }
    # A name that is not in the Quran has no ayah: the card shows neither the link nor the sound.
    assert body["names"][1]["ayah"] is None

    arabic = api_client.get(_url(), {"language": "ar"}).json()
    assert arabic["names"][0]["transliteration"] == ""
    assert arabic["names"][0]["meaning"] == "Милостивый [ar]"
    # Russian is the default.
    assert api_client.get(_url()).json()["collection"]["language"] == "ru"
    assert api_client.get(_url(), {"language": "de"}).status_code == 400
    assert api_client.get(_url("other")).status_code == 404
    etag = response["ETag"]
    assert api_client.get(_url(), {"language": "tr"}, HTTP_IF_NONE_MATCH=etag).status_code == 304


@pytest.mark.django_db
def test_a_correction_is_a_new_version(owner: User, api_client: APIClient) -> None:
    first = _published(owner)
    draft = copy_names_version(first, "v2")
    assert draft.is_editable
    assert draft.names.count() == 2
    assert draft.tafsir_source_en == first.tafsir_source_en
    name = draft.names.get(slug="ar-rahman")
    name.meaning_ru = "Исправлено"
    name.save()
    # The published version still serves its own text.
    assert api_client.get(_url()).json()["names"][0]["meaning"] == "Милостивый [ru]"
    with pytest.raises(NamesError, match="уже есть"):
        copy_names_version(first, "v2")

    sign_names_version(draft, owner)
    publish_names_version(draft)
    first.refresh_from_db()
    assert first.status == NamesStatus.WITHDRAWN
    assert NamesCollection.objects.get().active_version == draft
    body = api_client.get(_url()).json()
    assert body["collection"]["version"] == "v2"
    assert body["names"][0]["meaning"] == "Исправлено"
    with pytest.raises(NamesError, match="только черновик"):
        publish_names_version(first)


@pytest.mark.django_db
def test_model_rules(owner: User) -> None:
    version = import_names(_data())
    name = version.names.get(position=2)
    name.word_position = 2
    with pytest.raises(ValidationError):
        name.full_clean()
    name.word_position = None
    name.surah = 2
    with pytest.raises(ValidationError):
        name.full_clean()
    # Published means signed.
    with pytest.raises(IntegrityError):
        NamesVersion.objects.filter(pk=version.pk).update(status=NamesStatus.PUBLISHED)


@pytest.mark.django_db
def test_import_command(capsys: pytest.CaptureFixture[str], tmp_path: Any) -> None:
    path = tmp_path / "names.json"
    path.write_text(json.dumps(_data()), encoding="utf-8")
    call_command("import_names", str(path))
    assert "имён: 2" in capsys.readouterr().out
    assert NamesVersion.objects.get().status == NamesStatus.DRAFT


# Admin ---------------------------------------------------------------------


def _client(user: User) -> Client:
    client = Client()
    client.force_login(user)
    return client


def _action(client: Client, action: str, version: NamesVersion) -> Any:
    return client.post(
        reverse("admin:names_namesversion_changelist"),
        {"action": action, "_selected_action": [str(version.pk)]},
        follow=True,
    )


def test_admin_section() -> None:
    assert placement("names", "DivineName") == ("learning", None)


@pytest.mark.django_db
def test_owner_edits_signs_and_publishes_in_the_admin(owner: User, api_client: APIClient) -> None:
    version = import_names(_data())
    name = version.names.get(position=2)
    name.tafsir_en = ""
    name.save()
    client = _client(owner)

    page = client.get(reverse("admin:names_namesversion_change", args=[version.pk]))
    assert page.status_code == 200
    content = page.content.decode()
    assert "Править имена" in content
    assert "толкование [en]" in content  # what is left to fill in
    assert "Толкование первого имени [ru]" in content  # the list for the sign-off

    # The list of names opens on the draft being worked on.
    listing = client.get(reverse("admin:names_divinename_changelist"))
    assert listing.status_code == 302
    assert f"version__id__exact={version.pk}" in listing["Location"]
    assert "Аль-Джамиль" in client.get(listing["Location"]).content.decode()

    response = _action(client, "sign_versions", version)
    assert "не подписана" in response.content.decode()

    # The owner fills in the missing text on the name's page.
    form_url = reverse("admin:names_divinename_change", args=[name.pk])
    form = client.get(form_url).context["adminform"].form
    data = {key: "" if value is None else value for key, value in form.initial.items()}
    data["tafsir_en"] = "Explanation"
    assert client.post(form_url, data).status_code == 302
    name.refresh_from_db()
    assert name.tafsir_en == "Explanation"

    assert "подписана" in _action(client, "sign_versions", version).content.decode()
    version.refresh_from_db()
    assert version.reviewed_by == owner
    # A signed version is read-only.
    assert client.post(form_url, {**data, "tafsir_en": "Changed"}).status_code == 403
    assert "опубликована" in _action(client, "publish_versions", version).content.decode()
    assert api_client.get(_url(), {"language": "en"}).json()["names"][1]["tafsir"] == "Explanation"

    # A correction starts as a copy; the published version stays.
    assert "Создан черновик" in _action(client, "copy_versions", version).content.decode()
    draft = NamesVersion.objects.get(status=NamesStatus.DRAFT)
    assert draft.names.count() == 2
    assert not version.is_editable
    assert draft.is_editable


@pytest.mark.django_db
def test_published_names_cannot_be_deleted_in_the_admin(owner: User) -> None:
    version = _published(owner)
    client = _client(owner)
    name = version.names.first()
    assert name is not None
    assert (
        client.post(
            reverse("admin:names_divinename_delete", args=[name.pk]), {"post": "yes"}
        ).status_code
        == 403
    )
    assert (
        client.post(
            reverse("admin:names_namesversion_delete", args=[version.pk]), {"post": "yes"}
        ).status_code
        == 403
    )
    assert version.names.count() == 2
