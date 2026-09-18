
# MongoDB + Mongo Express

A MongoDB database (standalone) with
[Mongo Express](https://github.com/mongo-express/mongo-express) as its web
UI, deployable to either a local kind or minikube cluster.

- [kind/](kind/README.md) — deploy/uninstall on a kind cluster
- [minikube/](minikube/README.md) — deploy/uninstall on a minikube cluster

Both are self-contained: run the one matching your current `kubectl`
context (`kubectl config current-context`); each refuses to run against the
wrong cluster type.

```bash
./kind/deployment.sh          # for a kind-* context
./minikube/deployment.sh      # for a minikube context
```

**Mongo Express is pinned to `1.0.2-20-alpine3.19`**, not `:latest` —
Docker Hub flags the plain `mongo-express` image "DEPRECATED" (it lost
Docker's official-image curation), but the upstream project is still
actively maintained and this remains the image its own README tells you to
run; pinning just avoids depending on a floating tag. Its own basic-auth
login is explicitly disabled (`ME_CONFIG_BASICAUTH_ENABLED=false`, which is
also its upstream default) — open the UI and it goes straight to browsing.

## What's running

| Component | Role |
|---|---|
| `mongodb` | The MongoDB server (standalone, single Deployment, no replica set) |
| `mongo-express` | Web UI, pre-configured to connect as `root` |

## Commands you'll actually use

### Check status

```bash
kubectl get pods -n mongodb
kubectl describe pod -n mongodb <pod-name>       # events, restarts, why something's not ready
helm status mongodb -n mongodb                    # Helm release status
helm get values mongodb -n mongodb                # what values are actually applied
```

### Access Mongo Express (web UI)

```bash
kubectl port-forward svc/mongo-express -n mongodb 8081:8081
```

Open http://localhost:8081 — no login, goes straight to the database list.

### Access MongoDB directly (for scripts/`mongosh`)

```bash
kubectl port-forward svc/mongodb -n mongodb 27017:27017
```

```bash
mongosh "mongodb://root:MongoDevPassword@localhost:27017/?authSource=admin"
```

Or with a driver (e.g. `pymongo`):

```python
from pymongo import MongoClient
client = MongoClient("mongodb://root:MongoDevPassword@localhost:27017/?authSource=admin")
db = client["mydb"]
db["mycollection"].insert_one({"hello": "world"})
print(list(db["mycollection"].find()))
```

### Run a command from inside the cluster (no port-forward)

```bash
kubectl run mongo-shell --rm -it --restart=Never --image=mongo:8.0 -n mongodb -- \
  mongosh "mongodb://root:MongoDevPassword@mongodb:27017/?authSource=admin"
```

### Change the root password or other config

Edit `kind/values.yaml` or `minikube/values.yaml` (`auth.rootPassword`,
`resources`, `persistence.size`, etc.) **and** the matching
`ME_CONFIG_MONGODB_URL` in that folder's `mongo-express.yaml` if you change
the password, then re-run the deploy script — it's `helm upgrade --install`,
so it's idempotent:

```bash
./kind/deployment.sh
```

## Tear down

```bash
./kind/deployment.sh uninstall        # or ./minikube/deployment.sh uninstall
```

See each environment's README for exactly what that removes.
