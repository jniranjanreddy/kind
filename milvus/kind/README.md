# Milvus on kind

For day-to-day commands (checking status, using Attu, connecting from code,
changing config), see [../README.md](../README.md).

Installs [Milvus](https://milvus.io/) (standalone mode) into the `milvus`
namespace of a local kind cluster via the official Helm chart
(`milvus/milvus`), using [values.yaml](values.yaml), then deploys
[Attu](https://github.com/zilliztech/attu) — Milvus's official web UI — in
front of it.

**Why standalone, not cluster mode:** Milvus cluster (distributed) mode
needs an external message queue. Even Milvus's own officially-tested
lightweight cluster config pulls in a Pulsar sub-cluster (zookeeper +
bookkeeper + broker + proxy) on top of Milvus's own proxy/coordinator/data/
query/streaming pods — 15+ pods total. Standalone mode uses Milvus's
embedded message queue instead (no Pulsar/Kafka needed) and exposes the same
data-plane APIs, so Attu and any client code work identically — just with
~4 pods instead of 15+. This matters here since this cluster also runs
Temporal, Argo CD, and Kafka stacks side by side.

## Prerequisites

- `kubectl` pointed at your kind cluster (`kubectl config current-context`
  should show `kind-*`)
- `helm` installed
- Cluster access to reach `zilliztech.github.io` (the Helm repo), and
  wherever the chart pulls its etcd/minio/Milvus/Attu images from (Docker
  Hub, quay.io)

## Deploy

```bash
./deployment.sh
```

The script refuses to run unless the current kubectl context matches
`kind-*`, to avoid installing against the wrong cluster.

What it does:

1. Creates the `milvus` namespace (idempotent).
2. Adds/updates the `milvus` Helm repo
   (`https://zilliztech.github.io/milvus-helm`).
3. Installs/upgrades the `milvus` release from [values.yaml](values.yaml)
   and waits for the `milvus-standalone` Deployment to be ready (pulls
   etcd/minio/Milvus images — can take a few minutes on a fresh cluster).
4. Applies [attu.yaml](attu.yaml) and waits for it to be ready.
5. Prints the pod list, the in-cluster service address, and how to reach
   Attu.

Safe to re-run — every step is idempotent (`helm upgrade --install`,
`kubectl apply`). It also takes a file lock (`.deployment.sh.lock`) for its
duration, so a second concurrent run fails fast instead of racing the first.

## Using Attu

```bash
kubectl port-forward svc/attu -n milvus 3000:3000
```

Open http://localhost:3000 and connect using Milvus address `milvus:19530`
(this is pre-set as Attu's `MILVUS_URL` env var, so it should be filled in
already).

## Connecting from your own code

From inside the cluster: `milvus.milvus.svc.cluster.local:19530` (or just
`milvus:19530` from within the `milvus` namespace). From outside the
cluster, port-forward it the same way as Attu:

```bash
kubectl port-forward svc/milvus -n milvus 19530:19530
```

Then use any Milvus SDK (Python `pymilvus`, etc.) against `localhost:19530`.

## Tear down

```bash
./deployment.sh uninstall
```

Deletes Attu, uninstalls the `milvus` Helm release, then the entire `milvus`
namespace, and waits for it to fully terminate. Safe to run even if nothing
is deployed.
