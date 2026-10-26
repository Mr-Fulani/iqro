FROM postgres:17.11-alpine3.24 AS upstream

RUN apk add --no-cache su-exec 'libcrypto3>=3.5.8-r0' 'libssl3>=3.5.8-r0' \
        'libuuid>=2.42.3-r1' \
    && rm /usr/local/bin/gosu \
    && ln -s /sbin/su-exec /usr/local/bin/gosu

FROM scratch

COPY --from=upstream / /

ENV LANG=en_US.utf8 \
    PGDATA=/var/lib/postgresql/data

VOLUME /var/lib/postgresql/data

# The upstream image stops with SIGINT (fast shutdown); FROM scratch drops that, and the
# default SIGTERM is a smart shutdown that waits for pooled clients until Docker kills it.
STOPSIGNAL SIGINT
ENTRYPOINT ["docker-entrypoint.sh"]
EXPOSE 5432
CMD ["postgres"]
