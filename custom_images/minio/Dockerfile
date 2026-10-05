FROM golang:1.24-bookworm AS build

ARG MINIO_TAG=RELEASE.2025-09-07T16-13-09Z
ARG MINIO_COMMIT=07c3a429bfed433e49018cb0f78a52145d4bedeb

RUN git clone --depth 1 --branch "${MINIO_TAG}" https://github.com/minio/minio.git /src
WORKDIR /src
RUN test "$(git rev-parse HEAD)" = "${MINIO_COMMIT}" \
    && MINIO_RELEASE=RELEASE go run buildscripts/gen-ldflags.go 2025-09-07T16-13-09Z > /tmp/minio-ldflags \
    && CGO_ENABLED=0 go build -tags kqueue -trimpath -ldflags "$(cat /tmp/minio-ldflags)" -o /out/minio . \
    && /out/minio --version

FROM alpine:3.21
RUN apk add --no-cache ca-certificates
COPY --from=build /out/minio /usr/local/bin/minio
EXPOSE 9000 9001
VOLUME /data
ENTRYPOINT ["/usr/local/bin/minio"]
