FROM alpine:3.23.5

RUN apk add --no-cache nginx nginx-mod-http-cache-purge \
        'libcrypto3>=3.5.8-r0' 'libssl3>=3.5.8-r0' \
    && mkdir -p /var/cache/nginx/public-api

COPY default.conf /etc/nginx/http.d/default.conf
COPY security-headers.conf /etc/nginx/snippets/quran-security-headers.conf

EXPOSE 8080

STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1

CMD ["nginx", "-g", "daemon off;"]
