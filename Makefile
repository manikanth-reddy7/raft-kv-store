BUILD_VERSION ?= v0.1
IMAGE_NAME    ?= raft-kv-store

# ──────────────────────────────────────────────
#  LOCAL BUILD  (no Docker needed)
# ──────────────────────────────────────────────

.PHONY: build-local
build-local:
	go mod tidy
	CGO_ENABLED=0 GOARCH=amd64 go build -o bin/kv .
	CGO_ENABLED=0 GOARCH=amd64 go build -o bin/client client/cmd/main.go
	@echo "✅  Binaries: bin/kv  bin/client"

.PHONY: proto
proto:
	protoc -I=. --go_out=. raftpb/raft.proto

# ──────────────────────────────────────────────
#  DOCKER BUILD
# ──────────────────────────────────────────────

.PHONY: build
build:
	docker build -t $(IMAGE_NAME):$(BUILD_VERSION) -f Dockerfile .
	docker tag $(IMAGE_NAME):$(BUILD_VERSION) $(IMAGE_NAME):latest
	@echo "✅  Image: $(IMAGE_NAME):$(BUILD_VERSION)"

# ──────────────────────────────────────────────
#  DOCKER-COMPOSE CLUSTER  (recommended)
# ──────────────────────────────────────────────

.PHONY: cluster
cluster: build cluster-up

.PHONY: cluster-up
cluster-up:
	docker-compose up -d node0 node1 node2
	@echo "⏳  Waiting 8s for cluster to form..."
	@sleep 8
	@echo "✅  Cluster is up. Run:  make client"

.PHONY: client
client:
	@echo "🚀  Starting interactive client shell..."
	docker-compose run --rm -e TERM=xterm client

.PHONY: cluster-down
cluster-down:
	docker-compose down -v
	@echo "✅  Cluster stopped and volumes removed."

.PHONY: cluster-logs
cluster-logs:
	docker-compose logs -f node0 node1 node2

# ──────────────────────────────────────────────
#  LEGACY  (original Makefile targets preserved)
# ──────────────────────────────────────────────

.PHONY: cluster-legacy
cluster-legacy: cluster-clean
	@docker network create raft-net --subnet 10.10.10.0/24 || true
	mkdir -p node0 node1 node2 client
	docker run -d -e BOOTSTRAP_LEADER=yes   -p 17000:17000 -v ${PWD}/node0:/pv/ --rm --net raft-net --hostname node0 --name node0 $(IMAGE_NAME):$(BUILD_VERSION)
	docker run -d -e BOOTSTRAP_FOLLOWER=yes -p 17001:17000 -v ${PWD}/node1:/pv/ --rm --net raft-net --hostname node1 --name node1 $(IMAGE_NAME):$(BUILD_VERSION)
	docker run -d -e BOOTSTRAP_FOLLOWER=yes -p 17002:17000 -v ${PWD}/node2:/pv/ --rm --net raft-net --hostname node2 --name node2 $(IMAGE_NAME):$(BUILD_VERSION)
	@printf "\n\n ######### Starting Client #########\n\n"
	@docker run -it -v ${PWD}/metric:/metric/ --net raft-net --hostname client --name client $(IMAGE_NAME):$(BUILD_VERSION) client -e node0:17000

cluster-clean: clean
	docker rm -fv node0 node1 node2 client 2>/dev/null || true

clean:
	rm -rf node* cohort* bin/

# ──────────────────────────────────────────────
#  FAILURE SIMULATION
# ──────────────────────────────────────────────

.PHONY: kill-leader
kill-leader:
	@echo "💥  Pausing node0 (leader) for 10s..."
	bash turn-down.sh -n node0 -t 10 -r

.PHONY: kill-follower
kill-follower:
	@echo "💥  Pausing node1 (follower) for 10s..."
	bash turn-down.sh -n node1 -t 10

# ──────────────────────────────────────────────
#  TESTS & PERFORMANCE
# ──────────────────────────────────────────────

.PHONY: test
test:
	go test ./...

.PHONY: test-client
test-client:
	cd client && go test -v

.PHONY: performance-test
performance-test:
	env GOOS=linux GOARCH=amd64 go build -o metric/bin/performance metric/performance.go
	docker exec -it client metric/bin/performance -c

.PHONY: help
help:
	@echo ""
	@echo "  Raft KV Store – Available make targets"
	@echo "  ───────────────────────────────────────"
	@echo "  build          Build Docker image"
	@echo "  cluster        Build image + start 3-node cluster"
	@echo "  client         Open interactive client shell"
	@echo "  cluster-down   Stop cluster and remove volumes"
	@echo "  cluster-logs   Tail cluster logs"
	@echo "  kill-leader    Pause node0 for 10s (test leader election)"
	@echo "  kill-follower  Pause node1 for 10s (test fault tolerance)"
	@echo "  test           Run all Go unit tests"
	@echo "  build-local    Build binaries locally (needs Go + protoc)"
	@echo ""
