FROM caddy:2.11.4-alpine

# The upstream binary can bind privileged ports, but staging maps host ports
# to unprivileged 8080/8443. Remove the unused file capability so Caddy can
# run with every container capability dropped and no-new-privileges enabled.
RUN apk add --no-cache libcap-utils \
    && setcap -r /usr/bin/caddy \
    && apk del libcap-utils
