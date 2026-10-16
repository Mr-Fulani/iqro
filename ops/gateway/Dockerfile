FROM alpine:3.23.5

RUN apk add --no-cache nginx nginx-mod-http-cache-purge \
        'libcrypto3>=3.5.8-r0' 'libssl3>=3.5.8-r0' \
    && mkdir -p /var/cache/nginx/public-api \
    # The container is capped at half a CPU; `auto` would start one worker per host core.
    && sed -i 's/^worker_processes auto;/worker_processes 2;/' /etc/nginx/nginx.conf \
    && grep -q '^worker_processes 2;' /etc/nginx/nginx.conf \
    # Errors to stderr for `docker logs`; the access log is set in default.conf.
    && sed -i 's#^error_log /var/log/nginx/error.log warn;#error_log /dev/stderr warn;#' /etc/nginx/nginx.conf \
    && grep -q '^error_log /dev/stderr warn;' /etc/nginx/nginx.conf

COPY default.conf /etc/nginx/http.d/default.conf
COPY security-headers.conf /etc/nginx/snippets/quran-security-headers.conf

EXPOSE 8080

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
