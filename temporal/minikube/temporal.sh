#!/usr/bin/env bash
#
# Deploys Temporal (server + Postgres backend) into the "temporal" namespace
# of a local minikube cluster, using the postgres-values.yaml and
# temporal-values.yaml in this same directory.
#
# Usage:
#   ./temporal.sh              # deploy
#   ./temporal.sh uninstall    # tear down everything this script deployed
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Prevent two concurrent runs (e.g. a manual run and an automated one) from
# racing on the same namespace/releases, which surfaces as errors like
# "Error: create: failed to create: namespaces \"temporal\" not found".
LOCK_FILE="$SCRIPT_DIR/.temporal.sh.lock"
exec 200>"$LOCK_FILE"
if ! flock -n 200; then
  echo "ERROR: another instance of $(basename "$0") is already running (lock: $LOCK_FILE)." >&2
  exit 1
fi

NAMESPACE=temporal
PG_RELEASE=temporal-postgres
TEMPORAL_RELEASE=temporal

uninstall() {
  echo "Uninstalling Temporal from namespace $NAMESPACE..."
  helm uninstall "$TEMPORAL_RELEASE" -n "$NAMESPACE" 2>/dev/null || true
  helm uninstall "$PG_RELEASE" -n "$NAMESPACE" 2>/dev/null || true

  # The chart's pre-install schema Job is a Helm hook resource and survives
  # "helm uninstall" — remove it so a later install doesn't hit an immutable
  # Job-spec conflict.
  kubectl delete job temporal-schema -n "$NAMESPACE" --ignore-not-found

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
    echo "ERROR: current kubectl context '$CONTEXT' is not 'minikube'. Switch context, or use temporal.sh / kind/temporal.sh for other clusters." >&2
    exit 1
    ;;
esac

POSTGRES_VALUES="${1:-postgres-values.yaml}"
TEMPORAL_VALUES="${2:-temporal-values.yaml}"

for f in "$POSTGRES_VALUES" "$TEMPORAL_VALUES"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: values file '$f' not found in $SCRIPT_DIR" >&2
    exit 1
  fi
done

echo "kubectl context : $CONTEXT"
echo "postgres values  : $POSTGRES_VALUES"
echo "temporal values  : $TEMPORAL_VALUES"

# --- namespace (idempotent) ---
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Note: temporal-storageclass.yaml in this directory defines a
# "temporal-standardssd-retain" StorageClass that none of the values files
# below reference (postgres uses the cluster's default StorageClass), so it
# is intentionally not applied here.

# --- node pool (all values files pin pods to nodeSelector pool=temporal,workload=temporal) ---
# minikube's single node has no such labels by default, so label it here.
if [ -z "$(kubectl get nodes -l pool=temporal,workload=temporal --no-headers 2>/dev/null)" ]; then
  NODE="$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')"
  echo "No node labeled pool=temporal,workload=temporal found; labeling '$NODE' (single-node fallback)."
  kubectl label node "$NODE" pool=temporal workload=temporal --overwrite
fi

# --- helm repos ---
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo add temporal https://go.temporal.io/helm-charts >/dev/null 2>&1 || true
helm repo update

# --- postgres ---
helm upgrade --install "$PG_RELEASE" bitnami/postgresql -n "$NAMESPACE" -f "$POSTGRES_VALUES"

echo "Waiting for $PG_RELEASE to be ready..."
kubectl rollout status statefulset/"${PG_RELEASE}-postgresql" -n "$NAMESPACE" --timeout=300s

PG_USER="temporal"
PG_PASSWORD="$(kubectl get secret --namespace "$NAMESPACE" "${PG_RELEASE}-postgresql" -o jsonpath='{.data.password}' | base64 -d)"
PG_POD="${PG_RELEASE}-postgresql-0"

# temporal's "default" store database is created by auth.database in $POSTGRES_VALUES.
# The visibility store database is created here, idempotently.
EXISTS="$(kubectl exec -n "$NAMESPACE" "$PG_POD" -- env PGPASSWORD="$PG_PASSWORD" \
  psql -U "$PG_USER" -d temporal -tAc "SELECT 1 FROM pg_database WHERE datname = 'temporal_visibility'")"
if [ "$EXISTS" != "1" ]; then
  kubectl exec -n "$NAMESPACE" "$PG_POD" -- env PGPASSWORD="$PG_PASSWORD" \
    psql -U "$PG_USER" -d temporal -c "CREATE DATABASE temporal_visibility;"
fi

# --- temporal server ---
helm upgrade --install "$TEMPORAL_RELEASE" temporal/temporal --namespace "$NAMESPACE" -f "$TEMPORAL_VALUES"

echo "Waiting for admintools pod to be scheduled..."
ADMIN_POD=""
for _ in $(seq 1 60); do
  ADMIN_POD="$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/component=admintools -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)"
  [ -n "$ADMIN_POD" ] && break
  sleep 2
done
if [ -z "$ADMIN_POD" ]; then
  echo "ERROR: admintools pod never appeared in namespace $NAMESPACE" >&2
  exit 1
fi
kubectl wait --for=condition=ready pod/"$ADMIN_POD" -n "$NAMESPACE" --timeout=300s

echo "Waiting for temporal-frontend to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=frontend -n "$NAMESPACE" --timeout=300s

# --- default namespace (idempotent) ---
# Pod readiness doesn't guarantee the frontend's gRPC service is already
# accepting connections, so retry briefly rather than failing on a transient
# "connection error: error reading server preface: EOF".
DEFAULT_NS_REGISTERED=false
for _ in $(seq 1 15); do
  if kubectl exec -n "$NAMESPACE" "$ADMIN_POD" -- temporal operator namespace describe default >/dev/null 2>&1; then
    DEFAULT_NS_REGISTERED=true
    break
  fi
  if kubectl exec -n "$NAMESPACE" "$ADMIN_POD" -- temporal operator namespace create default 2>&1; then
    DEFAULT_NS_REGISTERED=true
    break
  fi
  sleep 4
done
if [ "$DEFAULT_NS_REGISTERED" != true ]; then
  echo "ERROR: could not register the 'default' Temporal namespace after retries." >&2
  exit 1
fi

echo "Temporal deployed. Pods:"
kubectl get pods -n "$NAMESPACE"

#create ingress for temporal web
#kubectl apply -f temporal-ingress.yaml
