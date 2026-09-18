#!/usr/bin/env bash
#
# Installs Milvus (standalone mode) into the "milvus" namespace of a local
# kind cluster via the official Helm chart, using values.yaml, then deploys
# Attu (attu.yaml) as a web UI in front of it.
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

NAMESPACE=milvus
RELEASE=milvus
VALUES_FILE="values.yaml"
ATTU_MANIFEST="attu.yaml"

uninstall() {
  echo "Removing Attu..."
  kubectl delete -f "$ATTU_MANIFEST" -n "$NAMESPACE" --ignore-not-found

  echo "Uninstalling Milvus from namespace $NAMESPACE..."
  helm uninstall "$RELEASE" -n "$NAMESPACE" 2>/dev/null || true
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
  kind-*) ;;
  *)
    echo "ERROR: current kubectl context '$CONTEXT' doesn't look like a kind cluster (expected 'kind-*'). Switch context, or use ../minikube/deployment.sh for a minikube cluster." >&2
    exit 1
    ;;
esac

echo "kubectl context : $CONTEXT"

# --- namespace (idempotent) ---
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- helm repo ---
helm repo add milvus https://zilliztech.github.io/milvus-helm >/dev/null 2>&1 || true
helm repo update milvus

# --- Milvus (standalone) ---
helm upgrade --install "$RELEASE" milvus/milvus -n "$NAMESPACE" -f "$VALUES_FILE"

echo "Waiting for Milvus to be ready (pulls etcd/minio/milvus images — can take a few minutes)..."
kubectl wait --for=condition=available deployment/"${RELEASE}-standalone" -n "$NAMESPACE" --timeout=600s

# --- Attu (idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$ATTU_MANIFEST"

echo "Waiting for Attu to be ready..."
kubectl wait --for=condition=available deployment/attu -n "$NAMESPACE" --timeout=180s

echo
echo "Milvus deployed. Pods:"
kubectl get pods -n "$NAMESPACE"
echo
echo "Milvus service (from inside the cluster):"
echo "  ${RELEASE}.${NAMESPACE}.svc:19530"
echo
echo "Attu (web UI):"
echo "  kubectl port-forward svc/attu -n $NAMESPACE 3000:3000   then open http://localhost:3000"
echo "  (in Attu, set the Milvus address to: ${RELEASE}:19530)"
