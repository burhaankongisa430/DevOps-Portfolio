# syntax=docker/dockerfile:1

# Stage 1: Build
FROM golang:1.21-alpine AS builder

# git is needed by go mod to resolve VCS metadata for some dependencies
RUN apk add --no-cache ca-certificates tzdata git

WORKDIR /app

# Copy module manifest first, then run go mod tidy to fetch dependencies and
# generate go.sum. Separating this from the COPY . step means dependency
# downloads are cached until go.mod changes — code-only edits reuse this layer.
COPY go.mod ./
RUN go mod tidy && go mod download && go mod verify

COPY . .

ARG VERSION=dev
ARG BUILD_TIME=unknown

RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -ldflags="-w -s -X main.version=${VERSION} -X 'main.buildTime=${BUILD_TIME}'" \
    -trimpath \
    -o /server \
    .

# Stage 2: Minimal distroless runtime
FROM gcr.io/distroless/static:nonroot

COPY --from=builder /server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

USER nonroot:nonroot

EXPOSE 8080

ENTRYPOINT ["/server"]
