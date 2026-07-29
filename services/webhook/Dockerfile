FROM alpine:3.22

ADD https://github.com/adnanh/webhook/releases/download/2.8.3/webhook-linux-amd64.tar.gz /tmp/webhook.tar.gz

RUN apk add --no-cache ca-certificates curl \
    && echo "3cdf93f0615f11bfc575c158d0d613666394228f6e830ff6f792178933773f7b  /tmp/webhook.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/webhook.tar.gz -C /tmp \
    && install -m 0755 /tmp/webhook-linux-amd64/webhook /usr/local/bin/webhook \
    && rm -rf /tmp/webhook.tar.gz /tmp/webhook-linux-amd64 \
    && addgroup -S -g 10001 webhook \
    && adduser -S -D -H -u 10001 -G webhook webhook

USER webhook:webhook
WORKDIR /etc/webhook

ENTRYPOINT ["/usr/local/bin/webhook"]
