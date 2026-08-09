# syntax=docker/dockerfile:1.7
FROM python:3.14-slim AS builder

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy

COPY --from=ghcr.io/astral-sh/uv:0.9.28 /uv /uvx /bin/

WORKDIR /app
COPY pyproject.toml uv.lock* README.md ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project

COPY src ./src
COPY manage.py ./manage.py
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM builder AS test

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --all-groups
COPY tests ./tests
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    DJANGO_SETTINGS_MODULE=quran_backend.settings.test
CMD ["pytest"]

FROM python:3.14-slim AS runtime-foundation

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONPATH=/app/src \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    DJANGO_SETTINGS_MODULE=quran_backend.settings.production

RUN addgroup --system app && adduser --system --ingroup app app
WORKDIR /app

FROM runtime-foundation AS asset-tooling

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends \
        poppler-utils \
        webp
COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/src /app/src
COPY --from=builder --chown=app:app /app/manage.py /app/manage.py
USER app

FROM runtime-foundation AS runtime

COPY --from=builder --chown=app:app /app/.venv /app/.venv
COPY --from=builder --chown=app:app /app/src /app/src
COPY --from=builder --chown=app:app /app/manage.py /app/manage.py
USER app

EXPOSE 8000

CMD ["gunicorn", "quran_backend.asgi:application", "-k", "uvicorn.workers.UvicornWorker", "--bind", "0.0.0.0:8000", "--workers", "2", "--access-logfile", "-", "--error-logfile", "-"]
