FROM redis:7.4.11-alpine3.21 AS upstream

RUN apk add --no-cache 'libcrypto3>=3.3.7-r2' 'libssl3>=3.3.7-r2'

FROM scratch

COPY --from=upstream / /

ENV REDIS_VERSION=7.4.11

VOLUME /data
WORKDIR /data

ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 6379
CMD ["redis-server"]
