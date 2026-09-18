# Temporal deployment

Deploys Temporal server + a dedicated Postgres backend into the `temporal`
namespace via Helm, on kind, minikube, or a real Kubernetes cluster.

## Prerequisites

- `kubectl` pointed at the target cluster (`kubectl config current-context`)
- `helm` installed
- Cluster access to reach `charts.bitnami.com` and `go.temporal.io/helm-charts`

## Layout

Each environment has its own self-contained deploy script next to its own
values files — there's no auto-detection anymore, so you always run the
script for the cluster you actually have selected.

```
temporal.sh                    # deploy/uninstall for a generic/production cluster
postgres-values.yaml           # its postgres values (repo root)
temporal-values.yaml           # its temporal values (repo root)
temporal-storageclass.yaml     # unused, see note below
kind/
  temporal.sh                  # deploy/uninstall for a local kind cluster
  postgres-values.yaml
  temporal-values.yaml
  temporal-storageclass.yaml   # unused, see note below
  worker.py                    # sample worker for kind
minikube/
  temporal.sh                  # deploy/uninstall for a local minikube cluster
  postgres-values.yaml
  temporal-values.yaml
  temporal-storageclass.yaml   # unused, see note below
  worker.yaml                  # sample worker for minikube
```

Note: each `temporal-storageclass.yaml` defines a `temporal-standardssd-retain`
StorageClass. It's currently unused — no values file references it (Postgres
uses the cluster's default StorageClass instead) — and none of the scripts
apply it. Kept for future use.

## Deploy

Run the script that matches your current kubectl context (`kubectl config
current-context`):

```bash
./kind/temporal.sh          # for a kind-* context
./minikube/temporal.sh      # for a minikube context
./temporal.sh                # for anything else (generic/production)
```

Each script checks the current context before doing anything and refuses to
run against the wrong one — e.g. `kind/temporal.sh` exits immediately if your
context isn't `kind-*`, telling you which script to use instead. This
prevents accidentally applying kind-sized dev values to a real cluster, or
vice versa.

To override the values files explicitly:

```bash
./kind/temporal.sh custom-postgres-values.yaml custom-temporal-values.yaml
```

### What each script does

1. Creates the `temporal` namespace (idempotent).
2. Ensures at least one node carries the `pool=temporal,workload=temporal`
   labels that the values files' `nodeSelector` requires. On a real cluster
   with pre-labeled node pools this is a no-op; on a single-node kind/minikube
   cluster it labels that node automatically.
3. Installs/upgrades Postgres (`temporal-postgres` release) from
   `postgres-values.yaml`, waits for it to be ready, then creates the
   `temporal_visibility` database (the `temporal` database itself is created
   by the chart via `auth.database`).
4. Installs/upgrades the Temporal server (`temporal` release) from
   `temporal-values.yaml`.
5. Waits for the `admintools` pod and the `temporal-frontend` pods, then
   registers the `default` Temporal namespace (idempotent, retries briefly
   since pod-ready doesn't guarantee the gRPC service is already accepting
   connections).
6. Prints the pod list for a final sanity check.

Each script is safe to re-run — every step is idempotent. It also takes a
file lock (`.temporal.sh.lock`, scoped to its own directory) for its
duration, so running it twice at once (e.g. manually while an automated run
is in flight) fails fast with a clear error instead of both instances racing
on the same namespace/releases.

## Access the Web UI

```bash
kubectl port-forward -n temporal svc/temporal-web 8080:8080
```

Then open http://localhost:8080.

## Tear down

Run `uninstall` on whichever script you deployed with, e.g.:

```bash
./kind/temporal.sh uninstall
```

This uninstalls the `temporal` and `temporal-postgres` Helm releases, deletes
the chart's pre-install schema Job (a Helm hook resource that `helm
uninstall` leaves behind and which would otherwise cause an immutable-field
conflict on the next install), deletes the `temporal` namespace, and waits
for the namespace to fully terminate before returning. Safe to run even if
nothing is deployed. Note `uninstall` skips the context check, since tearing
down doesn't risk applying the wrong values file.

## Troubleshooting notes (from real failed/edge-case deploys)

- If `helm install temporal-postgres ...` references a values file that
  doesn't exist, it fails silently (no `set -e` in old script versions) and
  every later step cascades into failure — the `temporal` Helm release ends
  up `failed` with no Postgres behind it. Each script now validates both
  values files exist before doing anything, and runs under `set -euo pipefail`.
- Pods stuck `Pending` with `FailedScheduling: node(s) didn't match Pod's
  node affinity/selector` mean no node carries the `pool=temporal` /
  `workload=temporal` labels the charts require — see step 2 above.
- A visibility-schema version mismatch in the Temporal logs ("Expected …
  vs Actual …") means the server started before `manageSchema` could
  finish; for dev, drop and recreate the `temporal_visibility` database and
  restart the pods.
- `Error: failed connecting to Temporal server at temporal-frontend:7233:
  error reading server preface: EOF` when registering the `default`
  namespace means the frontend pod reported ready before its gRPC service
  was actually accepting connections — this is why step 5 waits on frontend
  readiness and retries the namespace registration.
- Running two instances of the same script (or the same cluster's script
  twice) concurrently races on namespace/release creation — this is what the
  per-directory `.temporal.sh.lock` file prevents.
