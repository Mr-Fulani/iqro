from __future__ import annotations

from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    path("admin/", admin.site.urls),
    path("api/v1/", include("quran_backend.modules.core.urls")),
    path("api/v1/auth/", include("quran_backend.modules.accounts.urls")),
    path("api/v1/quran/", include("quran_backend.modules.quran.urls")),
    path("api/v1/feedback/", include("quran_backend.modules.feedback.urls")),
    path("api/v1/", include("quran_backend.modules.reading.urls")),
    path("api/schema", SpectacularAPIView.as_view(), name="openapi-schema"),
    path(
        "api/docs",
        SpectacularSwaggerView.as_view(url_name="openapi-schema"),
        name="swagger-ui",
    ),
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
