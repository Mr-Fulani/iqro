# syntax=docker/dockerfile:1.7
FROM python:3.14.7-alpine3.24 AS python-base

FROM python-base AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

RUN apk add --no-cache gettext

COPY --from=ghcr.io/astral-sh/uv:0.9.28 /uv /uvx /bin/

WORKDIR /app
COPY pyproject.toml uv.lock* README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY src ./src
COPY manage.py ./manage.py
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev
RUN .venv/bin/python manage.py compilemessages --locale ru
RUN DJANGO_SETTINGS_MODULE=quran_backend.settings.test \
    .venv/bin/python manage.py collectstatic --noinput

FROM builder AS test

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --all-groups
COPY tests ./tests
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    DJANGO_SETTINGS_MODULE=quran_backend.settings.test
CMD ["pytest"]

FROM alpine:3.24.1 AS runtime-foundation

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=quran_backend.settings.production

RUN apk add --no-cache \
        ca-certificates \
        gdbm \
        libbz2 \
        libffi \
        libncursesw \
        libpanelw \
        libuuid \
        ncurses-terminfo-base \
        readline \
        sqlite-libs \
        tzdata \
        xz-libs \
        zstd-libs \
    && addgroup --system app \
    && adduser --system --ingroup app app
COPY --from=python-base /usr/local /usr/local
RUN rm -rf \
        /usr/local/bin/pip \
        /usr/local/bin/pip3 \
        /usr/local/bin/pip3.14 \
        /usr/local/lib/python3.14/ensurepip \
        /usr/local/lib/python3.14/site-packages/pip \
        /usr/local/lib/python3.14/site-packages/pip-*.dist-info
WORKDIR /app

FROM runtime-foundation AS asset-tooling

RUN apk add --no-cache \
        libwebp-tools \
        poppler-utils
COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/src /app/src
COPY --from=builder --chown=app:app /app/manage.py /app/manage.py
COPY --from=builder --chown=app:app /app/staticfiles /app/staticfiles
USER app

FROM runtime-foundation AS runtime-files

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/src /app/src
COPY --from=builder --chown=app:app /app/manage.py /app/manage.py
COPY --from=builder --chown=app:app /app/staticfiles /app/staticfiles

FROM scratch AS runtime

COPY --from=runtime-files / /

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=quran_backend.settings.production

WORKDIR /app
USER app

EXPOSE 8000

CMD ["gunicorn", "quran_backend.asgi:application", "--config", "python:quran_backend.gunicorn_config"]
