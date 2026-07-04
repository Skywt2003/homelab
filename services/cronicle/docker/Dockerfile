# Use an existing local Node.js image on this lab host to avoid depending on Docker Hub pulls during deploy.
FROM diygod/rsshub:latest

ARG CRONICLE_VERSION=v0.9.122

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /opt/cronicle \
    && curl -fsSL "https://github.com/jhuckaby/Cronicle/archive/${CRONICLE_VERSION}.tar.gz" \
      | tar xz -C /opt/cronicle --strip-components=1 \
    && cd /opt/cronicle \
    && npm install --omit=dev \
    && node bin/build.js dist \
    && mkdir -p /opt/cronicle/data /opt/cronicle/logs /opt/cronicle/queue /etc/cronicle

COPY docker/entrypoint.sh /usr/local/bin/cronicle-entrypoint.sh
RUN chmod +x /usr/local/bin/cronicle-entrypoint.sh

WORKDIR /opt/cronicle
EXPOSE 3012
ENTRYPOINT ["/usr/local/bin/cronicle-entrypoint.sh"]
CMD ["node", "lib/main.js"]
