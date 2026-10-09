FROM golang:1.25.7-bookworm AS build

WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY *.go ./
RUN CGO_ENABLED=1 go build -tags duckdb_arrow -trimpath -o /usr/local/bin/ampere-flight-sql .

ENV HOME=/home/flight
RUN mkdir -p "$HOME" && FLIGHT_SQL_INSTALL_EXTENSIONS=1 /usr/local/bin/ampere-flight-sql

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 10001 --create-home flight
COPY --from=build /usr/local/bin/ampere-flight-sql /usr/local/bin/ampere-flight-sql
COPY --from=build --chown=10001:10001 /home/flight/.duckdb /home/flight/.duckdb
ENV HOME=/home/flight
USER 10001:10001
EXPOSE 8815 8080
ENTRYPOINT ["/usr/local/bin/ampere-flight-sql"]
