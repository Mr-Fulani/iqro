from __future__ import annotations

import uuid

from django.db import models


class UUIDv7Model(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid7, editable=False)

    class Meta:
        abstract = True


class TimeStampedModel(models.Model):
    created_at = models.DateTimeField(auto_now_add=True, db_index=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class BaseModel(UUIDv7Model, TimeStampedModel):
    class Meta:
        abstract = True
