# Stage 1: Build Stage
FROM golang:1.25.4-alpine AS builder
ENV CGO_ENABLED=0
ENV GOOS=linux
ENV GOPROXY=https://goproxy.cn,direct

WORKDIR /app
COPY . .
RUN go mod download && go mod tidy
RUN go build -ldflags="-w -s" -o /mihomo-exporter .


# Stage 2: Final Image
FROM alpine:3.22
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
COPY --from=builder /mihomo-exporter /mihomo-exporter
RUN chown appuser:appgroup /mihomo-exporter
USER appuser

EXPOSE 9188
ENTRYPOINT ["/mihomo-exporter"]
