# Stage 1: Build the Go binaries
FROM golang:1.14-alpine AS builder

# Install required build tools and protobuf compiler
RUN apk update && apk add --no-cache \
    git \
    curl \
    unzip \
    bash \
    build-base \
    protobuf-dev

# Install the protoc Go plugin
RUN go get github.com/golang/protobuf/protoc-gen-go@v1.3.3

WORKDIR /go/src/github.com/raft-kv-store

# Copy go.mod and go.sum first to cache dependencies
COPY go.mod go.sum ./
RUN go mod download

# Copy the rest of the source code
COPY . .

# Generate Go code from protobuf definitions
RUN PATH="$PATH:$(go env GOPATH)/bin" protoc -I=. --go_out=. raftpb/raft.proto

# Compile the server and client binaries statically
RUN CGO_ENABLED=0 GOARCH=amd64 go build -o bin/kv .
RUN CGO_ENABLED=0 GOARCH=amd64 go build -o bin/client client/cmd/main.go

# Stage 2: Create a minimal runtime image
FROM alpine:3.11

# Install basic runtime utilities
RUN apk update && apk add --no-cache curl bash

# Copy the compiled binaries and configuration from the builder stage
COPY --from=builder /go/src/github.com/raft-kv-store/bin/client /bin/client
COPY --from=builder /go/src/github.com/raft-kv-store/bin/kv     /bin/kv
COPY config/shard-config.json config/shard-config.json
COPY bootstrap.sh /bootstrap.sh

# Make the bootstrap script executable and create a directory for logs
RUN chmod +x /bootstrap.sh && mkdir /logs

# Expose ports for communication
EXPOSE 17000 17001 17002 18000 18001 18002

# Start the application
CMD ["/bootstrap.sh"]
