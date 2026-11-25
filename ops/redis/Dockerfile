FROM redis:7.4.12-alpine3.22 AS upstream

RUN apk add --no-cache 'libcrypto3>=3.5.9-r2' 'libssl3>=3.5.9-r2' 'zlib>=1.3.2-r1' \
        'musl>=1.2.5-r13' 'musl-utils>=1.2.5-r13'

FROM scratch

COPY --from=upstream / /

ENV REDIS_VERSION=7.4.12

VOLUME /data
WORKDIR /data

ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 6379
CMD ["redis-server"]
