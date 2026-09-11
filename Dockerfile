# syntax=docker/dockerfile:1

# Build stage: CGO is required for the mattn/go-sqlite3 driver, and the
# schema uses FTS5 virtual tables (fts5 build tag).
FROM golang:1.27.1-bookworm AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG VERSION=dev
ARG VCS_REF
ENV CGO_ENABLED=1
RUN go build -tags fts5 -trimpath -ldflags "-s -w" -o /out/jai ./cmd/jai

# Runtime stage: distroless base-debian12 gives us glibc (needed by the CGO
# sqlite build) + ca-certificates, and the :nonroot tag runs as uid/gid 65532 —
# matching the team-map Helm chart's podSecurityContext (runAsNonRoot, uid 65532,
# readOnlyRootFilesystem). The only writable paths at runtime are the mounted
# PVC (/data) and the /tmp emptyDir; jai creates its DB dir (--db) under /data.
FROM gcr.io/distroless/base-debian12:nonroot

COPY --from=build /out/jai /usr/local/bin/jai

# MCP server over HTTP is reachable at http://<host>:8947/mcp
EXPOSE 8947

# HOME is set to /tmp by the chart (readOnlyRootFilesystem); keep a sane default
# for standalone `docker run` so config/cache resolution doesn't hit a RO path.
ENV HOME=/tmp

ENTRYPOINT ["jai"]
# Default to serving MCP over HTTP. The team-map chart overrides args with the
# full sidecar invocation (serve --transport=http --toolsets=... --read-only
# --no-sync --config=... --db=...); override similarly for other uses, e.g.
#   docker run <image> get ROX-1234
CMD ["serve", "--transport", "http", "--port", "8947"]
