FROM nginx:1.28.3-alpine

COPY default.conf /etc/nginx/conf.d/default.conf
COPY security-headers.conf /etc/nginx/snippets/quran-security-headers.conf

EXPOSE 8080

HEALTHCHECK --interval=10s --timeout=3s --retries=5 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
