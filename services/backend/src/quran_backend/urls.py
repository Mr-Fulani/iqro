from __future__ import annotations

from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

from quran_backend.admin_localization import configure_russian_admin

configure_russian_admin()

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("quran_backend.modules.core.urls")),
    path("api/v1/", include("quran_backend.modules.accounts.user_urls")),
    path("api/v1/auth/", include("quran_backend.modules.accounts.urls")),
    path("api/v1/quran/", include("quran_backend.modules.quran.urls")),
    path("api/v1/quran/", include("quran_backend.modules.translations.urls")),
    path("api/v1/quran/", include("quran_backend.modules.tafsirs.urls")),
    path("api/v1/prayer/", include("quran_backend.modules.prayer_times.urls")),
    path("api/v1/", include("quran_backend.modules.prayer_times.profile_urls")),
    path("api/v1/", include("quran_backend.modules.audio.urls")),
    path("api/v1/feedback/", include("quran_backend.modules.feedback.urls")),
    path("api/v1/dua/", include("quran_backend.modules.dua.urls")),
    path("api/v1/", include("quran_backend.modules.dua.personal_urls")),
    path("api/v1/site/", include("quran_backend.modules.website.urls")),
    path("api/v1/", include("quran_backend.modules.reading.urls")),
    path("api/v1/", include("quran_backend.modules.memorization.urls")),
    path("api/v1/", include("quran_backend.modules.reminders.urls")),
    path("api/schema", SpectacularAPIView.as_view(), name="openapi-schema"),
    path(
        "api/docs",
        SpectacularSwaggerView.as_view(url_name="openapi-schema"),
        name="swagger-ui",
    ),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
