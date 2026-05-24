<div align="center">

<img src="https://readme-typing-svg.demolab.com?font=Fira+Code&size=14&pause=1000&color=7C6AF7&center=true&vCenter=true&width=500&lines=Distributed+%E2%80%A2+Fault+Tolerant+%E2%80%A2+Strongly+Consistent" alt="Typing SVG" />

# 🗄️ Raft KV Store

### A Distributed Key-Value Store Built for the Real World

[![Go Version](https://img.shields.io/badge/Go-1.14-00ADD8?style=for-the-badge&logo=go&logoColor=white)](https://golang.org)
[![Consensus](https://img.shields.io/badge/Consensus-Raft-4ADE80?style=for-the-badge&logo=hashicorp&logoColor=white)](https://raft.github.io)
[![License](https://img.shields.io/badge/License-Apache_2.0-7C6AF7?style=for-the-badge)](LICENSE)
[![CI](https://img.shields.io/badge/CI-CircleCI-343434?style=for-the-badge&logo=circleci&logoColor=white)](https://circleci.com)
[![Docker](https://img.shields.io/badge/Docker-Ready-2496ED?style=for-the-badge&logo=docker&logoColor=white)](https://docker.com)

<br/>

> *"What if your database could survive anything — crashes, network splits, even losing multiple servers — and still give you perfectly consistent data?"*
>
> That's exactly what this project does.

<br/>

[📖 What It Does](#-what-it-does) · [🏗️ Architecture](#️-architecture) · [🚀 Quick Start](#-quick-start) · [⌨️ Commands](#️-commands) · [💥 Failure Testing](#-failure--recovery-testing) · [📊 How It Works](#-how-it-works-deep-dive)

</div>

---

## 🧠 What It Does

Imagine you have a key-value store like Redis — but instead of one machine that can crash and lose everything, this system runs across **multiple machines** and:

- ✅ **Stays online** even if servers crash (fault tolerant via Raft consensus)
- ✅ **Never loses committed data** (replicated to majority before confirming)
- ✅ **Gives you the same answer** no matter which node you ask (strong consistency)
- ✅ **Handles bank-transfer-style operations** that must be all-or-nothing across servers (distributed transactions)
- ✅ **Automatically recovers** from partial failures mid-transaction

This is the same family of technology used inside **Google Spanner**, **CockroachDB**, **etcd** (Kubernetes' brain), and **Consul**.

---

## 🎯 Purpose & Real-World Use Cases

| Use Case | How This System Helps |
|---|---|
| 🏦 **Banking / Ledgers** | Transfer money between accounts atomically — `xfer alice bob 500` is all-or-nothing |
| 📦 **Inventory Management** | Decrement stock across multiple warehouses simultaneously without double-selling |
| 🔒 **Distributed Locking** | Store lock state consistently — only one process gets the lock across all nodes |
| ⚙️ **Config/Feature Flags** | All 100 services read the same config value at all times |
| 🔢 **Rate Limiting** | Accurate shared counters for quotas that can't be fooled by replication lag |
| 🗺️ **Service Discovery** | Consistent registry of which services are alive — like etcd, but yours |

---

## 🛠️ Tools & Technologies

<table>
<tr>
<td width="50%">

**Core Stack**

| Technology | Role |
|---|---|
| **Go 1.14** | Language — goroutines make distributed systems elegant |
| **Hashicorp Raft** | Consensus algorithm library (battle-tested in Consul & Vault) |
| **BoltDB** | Embedded persistent store for Raft logs + snapshots |
| **Protocol Buffers** | Binary serialization — 5-10× smaller than JSON |
| **Go net/rpc** | Inter-node RPC communication |

</td>
<td width="50%">

**Infrastructure & Dev**

| Technology | Role |
|---|---|
| **Docker** | Container runtime — consistent environment |
| **Docker Compose** | Spin up entire 3-node cluster in one command |
| **CircleCI** | Automated CI/CD pipeline |
| **Logrus** | Structured logging with component tagging |
| **XID** | Globally unique, time-sortable transaction IDs |

</td>
</tr>
</table>

### Why These Choices?

> **Why Raft over Paxos?**
> Raft was specifically designed to be *understandable*. Paxos leaves critical parts unspecified (leader election, log compaction, membership changes). Raft specifies all of them precisely — making correct implementation dramatically easier.

> **Why BoltDB over a separate database?**
> BoltDB is embedded (no separate process), ACID-compliant, and supports the sequential append-like writes that Raft logs need. Zero operational overhead.

> **Why Protocol Buffers over JSON?**
> Raft log entries are written and read thousands of times per second. Protobuf is 3-10× smaller and 5-10× faster than JSON. At scale, this is the difference between a fast system and a slow one.

---

## 🏗️ Architecture

### Bird's Eye View

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT (CLI)                            │
│         set alice 5000 · get alice · xfer alice bob 300         │
└──────────────────────────┬──────────────────────────────────────┘
                           │ HTTP
                           ▼
┌──────────────────────────────────────────────────────────────────┐
│                   COORDINATOR RAFT GROUP                         │
│                                                                  │
│   ┌─────────────────┐   ┌──────────────────┐   ┌─────────────┐  │
│   │  Coord Leader   │◄──│  Coord Follower  │   │Coord Follow │  │
│   │   node0:17000   │   │   node1:17000    │   │ node2:17000 │  │
│   │  Raft: 18000    │   │   Raft: 18000    │   │ Raft: 18000 │  │
│   └────────┬────────┘   └──────────────────┘   └─────────────┘  │
│            │                                                     │
│    Routes requests · Orchestrates 2PC · Recovers stuck txns      │
└────────────┬────────────────────────────────────────────────────┘
             │ RPC (net/rpc)
    ┌────────┴────────┐
    │                 │
    ▼                 ▼
┌───────────────┐  ┌───────────────┐
│  SHARD 0      │  │  SHARD 1      │    Keys → shard via hash(key) % 2
│  Raft Group   │  │  Raft Group   │
│               │  │               │
│ node0:17001 ◄─┤  │ node0:17002 ◄─┤  ← Leaders
│ node1:17001   │  │ node1:17002   │  ← Followers
│ node2:17001   │  │ node2:17002   │  ← Followers
│               │  │               │
│ + Cohort Raft │  │ + Cohort Raft │  ← Separate Raft for 2PC state
│   port +20000 │  │   port +20000 │    (38001, 38002)
└───────────────┘  └───────────────┘
```

### What Lives Inside Each Node?

Every Docker container (`node0`, `node1`, `node2`) runs **three processes** via `bootstrap.sh`:

```
node0 container
├── kv --coordinator  → Coordinator (Raft group 1)  port 17000/18000
├── kv (shard-0)      → KV Store    (Raft group 2)  port 17001/18001
│                       + Cohort    (Raft group 3)  port 38001
└── kv (shard-1)      → KV Store    (Raft group 4)  port 17002/18002
                        + Cohort    (Raft group 5)  port 38002
```

> 💡 **That's 5 separate Raft instances across the system, all working in concert.**

---

## 📊 How It Works: Deep Dive

### 1️⃣ The Raft Consensus Algorithm

Raft solves the hardest problem in distributed systems: **how do multiple machines agree on a single sequence of events?**

```
  ┌──────────────────────────────────────────────────────────┐
  │                    RAFT IN 3 STEPS                       │
  │                                                          │
  │  STEP 1: Leader Election                                 │
  │  ─────────────────────                                   │
  │  • All nodes start as Followers                          │
  │  • If no heartbeat in 150-300ms → become Candidate       │
  │  • Ask others to vote → first to get majority wins       │
  │  • Now there is exactly ONE leader (no split-brain)      │
  │                                                          │
  │  STEP 2: Log Replication                                 │
  │  ───────────────────────                                 │
  │  Client → Leader → AppendEntries RPC → Followers         │
  │  Once MAJORITY acknowledges → Entry is COMMITTED         │
  │  Committed entry → Applied to state machine (FSM)        │
  │                                                          │
  │  STEP 3: Safety Guarantee                                │
  │  ────────────────────────                                │
  │  New leader MUST have all committed entries              │
  │  Enforced by vote restrictions on log completeness       │
  │  → Committed data NEVER lost, even across leader changes │
  └──────────────────────────────────────────────────────────┘
```

### 2️⃣ Key-to-Shard Routing

When you type `set alice 5000`, the coordinator decides which shard stores it:

```
hash("alice") % 2 = 0  → Shard 0 (node0:17001, node1:17001, node2:17001)
hash("bob")   % 2 = 1  → Shard 1 (node0:17002, node1:17002, node2:17002)
```

The hash function is a polynomial rolling hash:
```go
func SimpleHash(s string, bins int) int64 {
    h := 0
    for _, c := range s {
        h = 31*h + int(c)  // Same as Java's String.hashCode()
    }
    return int64(h % bins)
}
```

### 3️⃣ Distributed Transactions: Two-Phase Commit (2PC)

When `xfer alice bob 500` spans two shards, we need a transaction. If this were not atomic, a crash halfway through would lose $500 forever.

```
  CLIENT: xfer alice bob 500
        │
        ▼
  COORDINATOR assigns txid = "cbq5t2..."
        │
        │──────── PHASE 1: PREPARE ────────────────────────
        │
        ├──► Shard-0 Cohort: "Lock 'alice', prepare to sub 500"
        │    └── Shard-0: Acquires lock on 'alice' ✓
        │        Replicates PREPARED state to its Raft group
        │        Replies: YES ✓
        │
        ├──► Shard-1 Cohort: "Lock 'bob', prepare to add 500"
        │    └── Shard-1: Acquires lock on 'bob' ✓
        │        Replicates PREPARED state to its Raft group
        │        Replies: YES ✓
        │
        │  All YES received → Coordinator logs PREPARED to its Raft
        │  ← This is the POINT OF NO RETURN →
        │
        │──────── PHASE 2: COMMIT ─────────────────────────
        │
        ├──► Shard-0: Apply sub 500 to Raft FSM, release lock ✓
        ├──► Shard-1: Apply add 500 to Raft FSM, release lock ✓
        │
        ▼
  COORDINATOR logs COMMITTED, responds OK to client ✓
```

**What if something crashes?**

| Crash Point | What Happens |
|---|---|
| Before Prepare sent | Coordinator recovers → sends Abort (no locks held anywhere) |
| After Prepare, before Commit logged | Coordinator recovers → sends Abort (cohorts release locks) |
| After Commit logged (point of no return) | Coordinator recovers → **must Commit** (retries until all shards confirm) |
| Shard leader crashes mid-commit | Raft elects new shard leader → Coordinator retries Commit to new leader |

### 4️⃣ Two-Phase Locking (2PL) — Preventing Race Conditions

What stops two transactions from corrupting data by running simultaneously?

```
Transaction A: xfer alice→bob 500   (locks alice, then bob)
Transaction B: xfer bob→alice 200   (locks bob, then alice)

WITHOUT 2PL: Both can run → dirty reads, lost updates
WITH 2PL:   One acquires all locks → other waits → then runs
            → Serializable isolation (strongest level)
```

The lock uses `TryLock` with a random timeout (based on txid hash) to avoid deadlocks:
```go
// If lock can't be acquired in time → abort transaction
// Random timeout prevents all transactions retrying simultaneously
func txTimeout(txid string) time.Duration {
    h := fnv.New32a()
    h.Write([]byte(txid))
    return time.Duration(h.Sum32()%50000)*time.Microsecond + LockContention
}
```

---

## 📁 Project Structure

```
raft-kv-store-master/
│
├── main.go                    ← Entry point (coordinator or shard node)
├── bootstrap.sh               ← Starts 3 kv processes per container
├── Dockerfile                 ← Multi-stage build (Go builder + Alpine runtime)
├── docker-compose.yml         ← 3-node cluster setup
├── Makefile                   ← build · cluster · client · test targets
│
├── coordinator/
│   ├── coordinator.go         ← Coordinator Raft group + 2PC orchestration
│   ├── api.go                 ← get/set/del/transaction logic
│   └── helpers.go             ← FindLeader, SendMessageToShard, RetryCommit/Abort
│
├── store/
│   ├── store.go               ← KV Store + Raft setup + BoltDB snapshots
│   ├── fsm.go                 ← Raft FSM: Apply (set/del commands to Cmap)
│   └── cohort.go              ← 2PC participant: Prepare/Commit/Abort handler
│
├── common/
│   ├── cmap.go                ← Concurrent map with per-key TryLock (2PL)
│   └── common.go              ← Raft setup, SimpleHash, constants
│
├── raftpb/
│   ├── raft.proto             ← Protobuf schema (Command, RaftCommand, GlobalTransaction)
│   └── raft.pb.go             ← Generated Go code (do not edit)
│
├── client/
│   ├── client.go              ← Interactive CLI client (REPL)
│   └── cmd/main.go            ← Client entry point
│
├── config/
│   └── shard-config.json      ← Shard topology (which nodes serve which shard)
│
├── http/
│   ├── service.go             ← HTTP server routing (/key, /transaction, /join)
│   └── handler.go             ← Request handlers
│
├── metric/
│   ├── performance.go         ← Throughput/latency benchmarks
│   └── Analysis.ipynb         ← Jupyter notebook with performance graphs
│
└── docs/
    ├── paper.pdf              ← Full academic paper
    └── slide.pdf              ← Presentation slides
```

---

## 🚀 Quick Start

### Prerequisites

You only need **Docker** and **Docker Compose** installed. That's it.

| Tool | Minimum Version | Install |
|---|---|---|
| Docker | 20.x | [docs.docker.com/get-docker](https://docs.docker.com/get-docker/) |
| Docker Compose | 1.29+ | Bundled with Docker Desktop |
| make | any | Pre-installed on Linux/Mac |

> **Windows?** Use WSL2 (Ubuntu). The scripts use bash.

### Step 1 — Add the generated files

> ⚠️ The original `Dockerfile` uses a **private builder image** (`supriyapremkumar/builder:v0.1`) that cannot be pulled publicly. Replace it with the self-contained version provided in this repo.

Copy these files into the project root (replacing originals):
- `Dockerfile` ← self-contained (uses `golang:1.14-alpine`)
- `docker-compose.yml` ← new file
- `Makefile` ← updated targets

### Step 2 — Build the Docker image

```bash
make build
# Or directly:
docker build -t raft-kv-store:latest .
```

**Expected output:**
```
[+] Building 180s
 => [builder 1/8] FROM golang:1.14-alpine
 => [builder 5/8] RUN go mod download
 => [builder 7/8] RUN go build -o bin/kv .
 => [runtime 2/4] COPY --from=builder .../bin/kv /bin/kv
 => exporting to image
✅  Image: raft-kv-store:v0.1
```

> First build takes ~3–5 minutes (downloading Go modules). Subsequent builds use the cache and finish in ~30 seconds.

### Step 3 — Start the 3-node cluster

```bash
make cluster-up
```

**Expected output:**
```
Creating network "raft-net"
Creating node0 ... done    ← Leader (boots first)
Creating node1 ... done    ← Follower
Creating node2 ... done    ← Follower
⏳  Waiting 8s for cluster to form...
✅  Cluster is up. Run:  make client
```

### Step 4 — Open the interactive client

```bash
make client
```

**Expected output:**
```
🚀  Starting interactive client shell...
>
```

You're in! The `>` prompt is the Raft KV Store REPL. Try commands below.

### Stopping the cluster

```bash
make cluster-down      # stops containers + removes volumes
make cluster-logs      # watch live logs from all nodes
```

---

## ⌨️ Commands

### Basic Operations

```bash
# Write a value
> set universe 42
OK

# Read a value
> get universe
Key=universe, Value=42

# Delete a key
> del universe
OK

# Get a deleted/missing key
> get universe
Key=universe does not exist

# Increment / Decrement
> set score 100
OK
> add score 50
OK
> get score
Key=score, Value=150
> sub score 30
OK
> get score
Key=score, Value=120
```

### Bank Transfer (Cross-Shard Atomic Transaction)

```bash
> set alice 5000
OK
> set bob 1000
OK

# Transfer 2000 from alice to bob — guaranteed atomic across shards
> xfer alice bob 2000
OK

> get alice
Key=alice, Value=3000
> get bob
Key=bob, Value=3000

# Try to overdraft — safely rejected
> xfer alice bob 99999
Insufficient funds: 3000 < 99999 in alice

# alice's balance unchanged
> get alice
Key=alice, Value=3000
```

### Multi-Key Transactions

```bash
# Group multiple operations into one atomic commit
> txn
Entering transaction mode
> set account-A 700
> set account-B 800
> del temp-key
> end
Submitting [method:"set" key:"account-A" value:700  method:"set" key:"account-B" value:800  method:"del" key:"temp-key"]
OK

# Both committed atomically
> get account-A
Key=account-A, Value=700
> get account-B
Key=account-B, Value=800
```

### All Commands Reference

| Command | Syntax | Description |
|---|---|---|
| `set` | `set <key> <int64>` | Write or overwrite a key |
| `get` | `get <key>` | Read a key's value |
| `del` | `del <key>` | Delete a key |
| `add` | `add <key> <delta>` | Atomically increment by delta |
| `sub` | `sub <key> <delta>` | Atomically decrement by delta |
| `xfer` | `xfer <from> <to> <amount>` | Atomic cross-shard transfer |
| `txn` | `txn` | Start a transaction block |
| `end` | `end` | Commit the current transaction |
| `exit` | `exit` | Disconnect from server |

> 💡 Keys with spaces must be quoted: `set "my account" 1000`
> Values must be **int64** integers (positive or negative)

---

## 💥 Failure & Recovery Testing

This is where the system gets interesting. Let's break things and watch it heal.

### Test 1: Kill the Leader

```bash
# Terminal 1: Pause node0 (the leader) for 15 seconds
bash turn-down.sh -n node0 -t 15 -r

# Output:
# Pause node0...
# Resume node0 in 15s...
# Restarting node0...
```

```bash
# Terminal 2: Watch logs during this time
docker-compose logs -f node1 node2
```

**Expected in logs (within ~300ms of node0 going down):**
```
node1 | WARN heartbeat timeout reached, starting election
node1 | INFO entering candidate state, term=2
node1 | INFO entering leader state, term=2  ← New leader elected!
```

```bash
# Terminal 3: Client keeps working during/after election
> set testkey 999
OK                          ← Might get brief error during election, then works
> get testkey
Key=testkey, Value=999      ← Data intact on new leader
```

### Test 2: Kill a Follower (Service Stays Up)

```bash
bash turn-down.sh -n node2 -t 30
```

With 3 nodes and 1 down, we still have **majority (2/3)** — the cluster keeps serving reads and writes normally. Raft only needs majority, not unanimity.

### Test 3: Watch 2PC Recovery in Action

```bash
# Check coordinator logs during a transaction
docker-compose logs -f node0 | grep -i "txid\|phase\|prepared\|commit"
```

```
INFO Processing Transaction txid: cbq5t2...
INFO [txid cbq5t2...] Starting prepare phase
INFO [txid cbq5t2...] Prepared received: 2 Expected: 2
INFO [txid cbq5t2...] Point of no return — replicating Prepared state
INFO [txid cbq5t2...] Commit Ack received: 2 Expected: 2
INFO [txid cbq5t2...] Transaction committed successfully
```

### Test 4: Performance Benchmark

```bash
# Run throughput benchmark inside the cluster
docker exec -it node0 sh
go run metric/performance.go
```

---

## ⚙️ Configuration Reference

### CLI Flags (`kv` binary)

| Flag | Short | Default | Description |
|---|---|---|---|
| `--listen` | `-l` | `localhost:11000` | HTTP/RPC listen address |
| `--raft` | `-r` | `localhost:12000` | Raft TCP bind address |
| `--join` | `-j` | *(none)* | Leader address to join (omit to bootstrap) |
| `--id` | `-i` | *(random)* | Node ID |
| `--dir` | `-d` | `./nodeID` | Raft data directory (BoltDB lives here) |
| `--coordinator` | `-c` | false | Start as coordinator instead of shard |
| `--fail` | `-t` | *(none)* | Inject failure: `prepared` or `commit` |
| `--snapshotthreshold` | | `5` | Log entries before triggering snapshot |
| `--snapshotinterval` | | `180` | Seconds between periodic snapshots |

### Shard Config (`config/shard-config.json`)

```json
{
  "shards": [
    ["node0:17001", "node1:17001", "node2:17001"],  ← Shard 0 replicas
    ["node0:17002", "node1:17002", "node2:17002"]   ← Shard 1 replicas
  ]
}
```

The coordinator reads this to know which RPC addresses serve which shard. Container hostnames must match these names.

---

## 🔍 How Fault Tolerance Actually Works

```
Normal Operation (all 3 nodes up):
┌────────┐    ┌────────┐    ┌────────┐
│ node0  │    │ node1  │    │ node2  │
│ Leader │◄──►│Follower│◄──►│Follower│
└────────┘    └────────┘    └────────┘
  Commits need 2/3 ✓

node0 crashes:
             ┌────────┐    ┌────────┐
  💥 DOWN    │ node1  │◄──►│ node2  │
             │ (elects│    │        │
             │ itself)│    │        │
             │ Leader │    │Follower│
             └────────┘    └────────┘
  Election in ~300ms. Commits need 2/3. Still works ✓

node0 + node1 crash (majority gone):
  💥 DOWN    💥 DOWN   ┌────────┐
                        │ node2  │
                        │        │
                        │ Cannot │
                        │ commit │← Correctly refuses writes
                        └────────┘
  No majority → No commits → No split-brain ✓
  Comes back when enough nodes restart
```

---

## 🆚 Why Not Just Use [X]?

| System | vs This Project |
|---|---|
| **Redis** | Redis replication has lag → possible stale reads. This system is strictly consistent. Redis also has no cross-key atomic transactions. |
| **Cassandra** | AP system (eventual consistency). Great for high throughput, wrong for banking. This is CP (strong consistency). |
| **etcd** | No sharding — single Raft group handles everything. This system shards data across multiple Raft groups for horizontal scalability. |
| **MySQL** | Single node. No automatic failover. This replicates automatically via Raft. |
| **Zookeeper** | Great for coordination primitives (locks, leader election). Not designed for general KV storage with transactions. |

---

## 📈 Performance Characteristics

| Operation | Latency | Notes |
|---|---|---|
| `get` | ~1-5ms | Single shard Raft read |
| `set` | ~5-15ms | Raft Apply (majority quorum round-trip) |
| Single-shard txn | ~10-30ms | 2PC within one Raft group |
| Cross-shard txn | ~20-60ms | 2PC across 2 Raft groups |
| Leader election | ~150-300ms | Brief pause in writes |

> Throughput scales with number of shards — each shard is an independent Raft group. Adding more shards linearly increases write throughput.

---

## 🚨 Known Limitations

> This is an academic/learning project. For production use, you'd want:

- **Int64 values only** — no strings, JSON, or byte arrays
- **Static sharding** — can't add shards without re-hashing all keys (no consistent hashing)
- **No TLS/auth** — all communication is plaintext
- **No follower reads** — all reads go through leader (bottleneck at scale)
- **Sequential 2PC Prepare** — could be parallelized for lower latency
- **No client retry library** — clients must handle transient errors manually

---

## 🏃 Run Locally (Without Docker)

If you have Go 1.14+ and protoc installed:

```bash
# Install dependencies
go get github.com/golang/protobuf/protoc-gen-go@v1.3.3
export PATH="$PATH:$(go env GOPATH)/bin"

# Regenerate protobuf (only if you change .proto)
protoc -I=. --go_out=. raftpb/raft.proto

# Build
make build-local
# Creates: bin/kv  and  bin/client

# Terminal 1: Start leader node
./bin/kv -c -i node0 -l :17000 -r :18000 -d /tmp/coord0

# Terminal 2: Start shard-0 leader
./bin/kv -i node0 -l :17001 -r :18001 -d /tmp/shard0 -b shard0

# Terminal 3: Start shard-1 leader
./bin/kv -i node0 -l :17002 -r :18002 -d /tmp/shard1 -b shard1

# Terminal 4: Connect client
./bin/client -e localhost:17000
```

---

## 🧪 Running Tests

```bash
# Unit tests
make test

# Client-specific tests
make test-client

# Performance benchmark (cluster must be running)
make performance-test
```

---

## 📚 Further Reading

- 📄 [Raft Paper](https://raft.github.io/raft.pdf) — "In Search of an Understandable Consensus Algorithm" (Ongaro & Ousterhout)
- 📖 [Hashicorp Raft Library](https://github.com/hashicorp/raft) — What this project uses
- 🌐 [Raft Visualization](https://raft.github.io/) — Interactive demo of leader election and log replication
- 📖 [Designing Data-Intensive Applications](https://dataintensive.net/) — Chapter 9 covers consensus algorithms in depth

---

<div align="center">

**If this helped you understand distributed systems, give it a ⭐**

*Built with Go · Powered by Raft · Hardened with 2PC*

</div>
