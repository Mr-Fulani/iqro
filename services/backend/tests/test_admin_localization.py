from __future__ import annotations

import pytest
from django.contrib import admin
from django.test import Client
from django.utils import translation

from quran_backend.admin_localization import FIELD_LABELS, MODEL_LABELS, configure_russian_admin
from quran_backend.modules.accounts.models import User
from quran_backend.modules.feedback.models import FeedbackTicket

configure_russian_admin()


def test_admin_login_is_forced_to_russian() -> None:
    response = Client().get("/admin/login/", HTTP_ACCEPT_LANGUAGE="en")

    assert response.status_code == 200
    assert response.headers["Content-Language"] == "ru"
    assert "Администрирование Iqro" in response.content.decode()
    assert "Войти" in response.content.decode()


@pytest.mark.django_db
def test_admin_index_uses_russian_project_labels() -> None:
    operator = User.objects.create_user(
        email="russian-admin@example.test",
        password="temporary-strong-password",
        status="active",
        is_staff=True,
        is_superuser=True,
    )
    client = Client()
    client.force_login(operator)

    response = client.get("/admin/", HTTP_ACCEPT_LANGUAGE="en")
    body = response.content.decode()

    assert response.status_code == 200
    assert response.headers["Content-Language"] == "ru"
    assert "Управление платформой" in body
    assert "Обратная связь" in body
    assert "Обращения пользователей" in body
    assert "Аудио Корана" in body
    assert "Время намаза" in body
    assert "Настройки сайта" in body
    assert "Социальные сети" in body


def test_every_project_admin_model_and_field_has_a_russian_label() -> None:
    project_models = [model for model in admin.site._registry if model._meta.app_label != "auth"]

    assert all(model._meta.label in MODEL_LABELS for model in project_models)
    assert all(
        field.name in FIELD_LABELS for model in project_models for field in model._meta.fields
    )
    assert FeedbackTicket._meta.verbose_name_plural == "обращения пользователей"
    assert FeedbackTicket._meta.get_field("public_id").verbose_name == "Номер обращения"
    with translation.override("ru"):
        assert FeedbackTicket._meta.get_field("category").flatchoices[0] == (
            "general",
            "Общее предложение",
        )
