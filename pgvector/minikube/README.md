# pgvector on minikube

For day-to-day commands (checking status, using Adminer, connecting from
code, changing config), see [../README.md](../README.md).

Deploys PostgreSQL + the [pgvector](https://github.com/pgvector/pgvector)
extension into the `pgvector` namespace of a local minikube cluster
([postgres.yaml](postgres.yaml)), plus [Adminer](https://www.adminer.org/)
([adminer.yaml](adminer.yaml)) as a web UI. Plain Kubernetes manifests, no
Helm chart — there's no well-established pgvector Helm chart, and this is
simple enough not to need one.

## Why not the Bitnami Postgres image (like Temporal uses)

Verified hands-on: Bitnami's `bitnami/postgresql` image does have the
`vector` extension available, and plain (non-indexed) similarity queries
work fine on it — but **building an HNSW or IVFFlat index on it crashes the
Postgres server** with `signal 4: Illegal instruction`, on this host's CPU
(Intel Meteor Lake, AVX-VNNI). That's a real backend crash — Postgres
survives via its own crash-recovery, but it forcibly drops every other
connection to the same instance while it recovers, which is not something
you want happening to a shared database.

This deployment uses the **official `pgvector/pgvector` image** instead —
verified: builds both HNSW and IVFFlat indexes successfully on the same
host. `deployment.sh` re-verifies this (extension enabled + HNSW index
build) as its last step, every time you deploy, specifically so this
doesn't regress silently if the image tag ever changes.

## Prerequisites

- `kubectl` pointed at your minikube cluster (`kubectl config current-context`
  should show `minikube`)
- Cluster access to reach Docker Hub (`pgvector/pgvector`, `adminer` images)

## Deploy

```bash
./deployment.sh
```

The script refuses to run unless the current kubectl context is exactly
`minikube`, to avoid installing against the wrong cluster.

What it does:

1. Creates the `pgvector` namespace (idempotent).
2. Applies [postgres.yaml](postgres.yaml) — a ConfigMap that auto-enables
   the `vector` extension on first init (via Postgres's own
   `/docker-entrypoint-initdb.d` mechanism) and a StatefulSet running
   `pgvector/pgvector` — and waits for its rollout to finish.
3. Applies [adminer.yaml](adminer.yaml) and waits for it to be ready.
4. **Verifies pgvector actually works**: connects, creates a throwaway
   table with a `vector` column, builds an HNSW index on it, then drops the
   table. If this fails, the script fails loudly instead of reporting
   success on a broken deployment.
5. Prints the pod list, the in-cluster service address, and how to reach
   Adminer.

Safe to re-run — every step is idempotent (`kubectl apply`). It also takes a
file lock (`.deployment.sh.lock`) for its duration, so a second concurrent
run fails fast instead of racing the first.

## Using Adminer

```bash
kubectl port-forward svc/adminer -n pgvector 8080:8080
```

Open http://localhost:8080. Unlike Mongo Express/Kafdrop in the other
stacks, Adminer does show a login form — that's normal, it's logging into
Postgres itself, not a separate broken auth layer. Fill in:

- System: **PostgreSQL**
- Server: **pgvector** (pre-filled)
- Username: **postgres**
- Password: see `POSTGRES_PASSWORD` in [postgres.yaml](postgres.yaml)
- Database: **vectordb**

## Connecting from your own code

From inside the cluster: `pgvector.pgvector.svc.cluster.local:5432` (or just
`pgvector:5432` from within the `pgvector` namespace). From outside:

```bash
kubectl port-forward svc/pgvector -n pgvector 5432:5432
```

```bash
psql "postgresql://postgres:PgVectorDevPassword@localhost:5432/vectordb"
```

```sql
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(4));
INSERT INTO items (embedding) VALUES ('[0.1,0.2,0.3,0.4]');
CREATE INDEX ON items USING hnsw (embedding vector_l2_ops);
SELECT id, embedding <-> '[0.1,0.2,0.3,0.4]' AS distance FROM items ORDER BY distance LIMIT 5;
```

Or with a driver (e.g. `psycopg` + `pgvector-python`):

```python
import psycopg
from pgvector.psycopg import register_vector

conn = psycopg.connect("postgresql://postgres:PgVectorDevPassword@localhost:5432/vectordb")
register_vector(conn)
```

## Tear down

```bash
./deployment.sh uninstall
```

Deletes Adminer, the Postgres StatefulSet (and its PVC, since it's deleted
along with the namespace), then the entire `pgvector` namespace, and waits
for it to fully terminate. Safe to run even if nothing is deployed.
