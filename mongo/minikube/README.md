# MongoDB on minikube

For day-to-day commands (checking status, using Mongo Express, connecting
from code, changing config), see [../README.md](../README.md).

Installs MongoDB (standalone) into the `mongodb` namespace of a local
minikube cluster via the Bitnami Helm chart (`bitnami/mongodb`), using
[values.yaml](values.yaml), then deploys
[Mongo Express](https://github.com/mongo-express/mongo-express) — a simple
web UI — in front of it.

## Prerequisites

- `kubectl` pointed at your minikube cluster (`kubectl config current-context`
  should show `minikube`)
- `helm` installed
- Cluster access to reach `charts.bitnami.com` and Docker Hub (MongoDB +
  Mongo Express images)

## Deploy

```bash
./deployment.sh
```

The script refuses to run unless the current kubectl context is exactly
`minikube`, to avoid installing against the wrong cluster.

What it does:

1. Creates the `mongodb` namespace (idempotent).
2. Adds/updates the `bitnami` Helm repo.
3. Installs/upgrades the `mongodb` release from [values.yaml](values.yaml)
   (standalone architecture, root user `root`, password set in that file)
   and waits for the `mongodb` Deployment to be ready.
4. Applies [mongo-express.yaml](mongo-express.yaml) and waits for it to be
   ready.
5. Prints the pod list, the in-cluster service address, and how to reach
   Mongo Express.

Safe to re-run — every step is idempotent (`helm upgrade --install`,
`kubectl apply`). It also takes a file lock (`.deployment.sh.lock`) for its
duration, so a second concurrent run fails fast instead of racing the first.

## Using Mongo Express

```bash
kubectl port-forward svc/mongo-express -n mongodb 8081:8081
```

Open http://localhost:8081 — no login required (Mongo Express's own basic
auth is explicitly disabled in [mongo-express.yaml](mongo-express.yaml); it
connects to MongoDB straight away).

## Connecting from your own code

From inside the cluster: `mongodb.mongodb.svc.cluster.local:27017` (or just
`mongodb:27017` from within the `mongodb` namespace). From outside the
cluster:

```bash
kubectl port-forward svc/mongodb -n mongodb 27017:27017
```

Then connect with any MongoDB driver/`mongosh` using the root credentials
from [values.yaml](values.yaml), e.g.:

```
mongodb://root:MongoDevPassword@localhost:27017/?authSource=admin
```

## Tear down

```bash
./deployment.sh uninstall
```

Deletes Mongo Express, uninstalls the `mongodb` Helm release, then the
entire `mongodb` namespace, and waits for it to fully terminate. Safe to run
even if nothing is deployed.
