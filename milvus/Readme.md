
# Milvus + Attu

A [Milvus](https://milvus.io/) vector database (standalone mode) with
[Attu](https://github.com/zilliztech/attu) as its web UI, deployable to
either a local kind or minikube cluster.

**Attu is pinned to `v2.6.5`, deliberately** — `:latest`/`v3.0` (released
September 2026) turned out to be a rewrite with its own tenant/billing/login
system: no default account exists, and you'd have to sign up at `/login`
before seeing anything. `v2.6.5` is the classic, no-login Attu — open it and
pick a Milvus connection, no account needed. Don't bump the image tag in
`attu.yaml` without checking what you're actually getting.

- [kind/](kind/README.md) — deploy/uninstall on a kind cluster
- [minikube/](minikube/README.md) — deploy/uninstall on a minikube cluster

Both are self-contained: run the one matching your current `kubectl`
context (`kubectl config current-context`); each refuses to run against the
wrong cluster type.

```bash
./kind/deployment.sh          # for a kind-* context
./minikube/deployment.sh      # for a minikube context
```

## Why standalone, not cluster mode

Milvus cluster (distributed) mode needs an external message queue. Even
Milvus's own officially-tested lightweight cluster config pulls in a Pulsar
sub-cluster (zookeeper + bookkeeper + broker + proxy) on top of Milvus's own
proxy/coordinator/data/query/streaming pods — 15+ pods total. Standalone
mode uses Milvus's embedded message queue instead (no Pulsar/Kafka needed)
and exposes the same data-plane APIs, so Attu and any client code work
identically — just with ~4 pods instead of 15+. This matters since this
cluster also runs Temporal, Argo CD, and Kafka stacks side by side.

## What's running

| Component | Role |
|---|---|
| `milvus-standalone` | The Milvus server itself (proxy + all coordinator/node roles in one process) |
| `milvus-etcd` | Metadata store (1 replica) |
| `milvus-minio` | Object storage for vector/index data (standalone mode) |
| `attu` | Web UI, pre-configured to point at `milvus:19530` |

## Commands you'll actually use

### Check status

```bash
kubectl get pods -n milvus
kubectl describe pod -n milvus <pod-name>       # events, restarts, why something's not ready
helm status milvus -n milvus                    # Helm release status
helm get values milvus -n milvus                # what values are actually applied
```

### Access Attu (web UI)

```bash
kubectl port-forward svc/attu -n milvus 3000:3000
```

Open http://localhost:3000 — the Milvus address (`milvus:19530`) is
pre-filled via Attu's `MILVUS_URL` env var.

### Access Milvus directly (for scripts/SDKs)

```bash
kubectl port-forward svc/milvus -n milvus 19530:19530
```

Then, with `pymilvus` installed (`pip install pymilvus`):

```python
from pymilvus import MilvusClient

client = MilvusClient(uri="http://localhost:19530")
client.create_collection(collection_name="my_collection", dimension=4)
client.insert(collection_name="my_collection", data=[{"id": 1, "vector": [0.1, 0.2, 0.3, 0.4]}])
client.flush(collection_name="my_collection")   # needed before a just-inserted vector is searchable
results = client.search(collection_name="my_collection", data=[[0.1, 0.2, 0.3, 0.4]], limit=5)
```

### Health check without port-forwarding a client

```bash
kubectl port-forward svc/milvus -n milvus 9091:9091
curl http://localhost:9091/healthz   # -> "OK"
```

### Upgrade or change configuration

Edit `kind/values.yaml` or `minikube/values.yaml` (e.g. to bump
`standalone.resources`, change persistence sizes, etc.), then re-run the
deploy script — it's `helm upgrade --install`, so it's idempotent:

```bash
./kind/deployment.sh
```

## Tear down

```bash
./kind/deployment.sh uninstall        # or ./minikube/deployment.sh uninstall
```

See each environment's README for exactly what that removes.
