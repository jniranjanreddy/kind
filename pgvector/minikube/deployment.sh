#!/usr/bin/env bash
#
# Deploys PostgreSQL + pgvector (postgres.yaml) into the "pgvector" namespace
# of a local minikube cluster, plus Adminer (adminer.yaml) as a web UI, then
# verifies the vector extension actually works end to end (extension
# present, index build succeeds) before declaring success.
#
# Usage:
#   ./deployment.sh              # deploy
#   ./deployment.sh uninstall    # tear down everything this script deployed
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Prevent two concurrent runs from racing on the same namespace/resources.
LOCK_FILE="$SCRIPT_DIR/.deployment.sh.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "ERROR: another instance of $(basename "$0") is already running (lock: $LOCK_FILE)." >&2
  exit 1
fi

NAMESPACE=pgvector
PG_MANIFEST="postgres.yaml"
UI_MANIFEST="adminer.yaml"

uninstall() {
  echo "Removing Adminer and PostgreSQL/pgvector..."
  kubectl delete -f "$UI_MANIFEST" -n "$NAMESPACE" --ignore-not-found
  kubectl delete -f "$PG_MANIFEST" -n "$NAMESPACE" --ignore-not-found
  kubectl delete namespace "$NAMESPACE" --ignore-not-found

  echo "Waiting for namespace $NAMESPACE to terminate..."
  for _ in $(seq 1 60); do
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
      echo "Namespace $NAMESPACE removed."
      return 0
    fi
    sleep 2
  done
  echo "WARNING: namespace $NAMESPACE is still terminating after 2 minutes; check 'kubectl get namespace $NAMESPACE -o yaml' for stuck finalizers." >&2
}

if [ "${1:-}" = "uninstall" ]; then
  uninstall
  exit 0
fi

CONTEXT="$(kubectl config current-context)"
case "$CONTEXT" in
  minikube) ;;
  *)
    echo "ERROR: current kubectl context '$CONTEXT' is not 'minikube'. Switch context, or use ../kind/deployment.sh for a kind cluster." >&2
    exit 1
    ;;
esac

echo "kubectl context : $CONTEXT"

# --- namespace (idempotent) ---
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- PostgreSQL + pgvector (idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$PG_MANIFEST"

echo "Waiting for PostgreSQL to be ready..."
kubectl rollout status statefulset/pgvector -n "$NAMESPACE" --timeout=300s

# --- Adminer (idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$UI_MANIFEST"

echo "Waiting for Adminer to be ready..."
kubectl wait --for=condition=available deployment/adminer -n "$NAMESPACE" --timeout=120s

# --- verify the vector extension actually works (not just that the pod is up) ---
echo "Verifying pgvector: extension present, HNSW index build succeeds..."
kubectl exec -n "$NAMESPACE" pgvector-0 -- env PGPASSWORD="PgVectorDevPassword" psql -U postgres -d vectordb -v ON_ERROR_STOP=1 -c "
DROP TABLE IF EXISTS _deploy_check;
CREATE TABLE _deploy_check (id bigserial PRIMARY KEY, embedding vector(3));
INSERT INTO _deploy_check (embedding) VALUES ('[0.1,0.2,0.3]'), ('[0.4,0.5,0.6]');
CREATE INDEX ON _deploy_check USING hnsw (embedding vector_l2_ops);
DROP TABLE _deploy_check;
" >/dev/null
echo "pgvector verified: extension enabled and HNSW index build succeeded."

echo
echo "pgvector deployed. Pods:"
kubectl get pods -n "$NAMESPACE"
echo
echo "Postgres service (from inside the cluster):"
echo "  pgvector.${NAMESPACE}.svc:5432  (db: vectordb, user: postgres, see postgres.yaml for password)"
echo
echo "Adminer (web UI):"
echo "  kubectl port-forward svc/adminer -n $NAMESPACE 8080:8080   then open http://localhost:8080"
echo "  System: PostgreSQL | Server: pgvector (pre-filled) | Username: postgres | Password: see postgres.yaml | Database: vectordb"
