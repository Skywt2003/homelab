FROM debian:trixie-slim

ARG SCRCPY_VERSION=4.1
ARG SCRCPY_SHA256=ad56ae8bfeedf41e824945c11dbf55fcb092b3e615b9b486f48a50e30d389635

RUN apt-get -o Acquire::Retries=5 -o Acquire::http::Timeout=30 update \
    && DEBIAN_FRONTEND=noninteractive apt-get \
        -o Acquire::Retries=5 -o Acquire::http::Timeout=30 \
        install -y --no-install-recommends \
        adb \
        ca-certificates \
        curl \
        openbox \
        novnc \
        tigervnc-standalone-server \
        tigervnc-tools \
        tini \
        websockify \
        x11-utils \
    && rm -rf /var/lib/apt/lists/*

RUN curl --fail --location --silent --show-error \
        "https://github.com/Genymobile/scrcpy/releases/download/v${SCRCPY_VERSION}/scrcpy-linux-x86_64-v${SCRCPY_VERSION}.tar.gz" \
        --output /tmp/scrcpy.tar.gz \
    && echo "${SCRCPY_SHA256}  /tmp/scrcpy.tar.gz" | sha256sum --check --strict \
    && mkdir -p /opt/scrcpy \
    && tar --extract --gzip --file /tmp/scrcpy.tar.gz \
        --directory /opt/scrcpy --strip-components=1 \
    && ln -s /opt/scrcpy/scrcpy /usr/local/bin/scrcpy \
    && rm /tmp/scrcpy.tar.gz

COPY entrypoint.sh /usr/local/bin/android-scrcpy-entrypoint
COPY patch-novnc-direct-touch.py /usr/local/bin/patch-novnc-direct-touch

RUN chmod 0755 /usr/local/bin/android-scrcpy-entrypoint \
    && python3 /usr/local/bin/patch-novnc-direct-touch \
    && rm /usr/local/bin/patch-novnc-direct-touch \
    && mkdir -p /var/lib/android/.android \
    && chmod 0700 /var/lib/android/.android

ENV HOME=/var/lib/android
ENV DISPLAY=:1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/android-scrcpy-entrypoint"]
CMD ["desktop"]
