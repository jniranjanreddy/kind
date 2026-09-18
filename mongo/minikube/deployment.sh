#!/usr/bin/env bash
#
# Installs MongoDB (standalone) into the "mongodb" namespace of a local
# minikube cluster via the Bitnami Helm chart, using values.yaml, then
# deploys Mongo Express (mongo-express.yaml) as a web UI in front of it.
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

NAMESPACE=mongodb
RELEASE=mongodb
VALUES_FILE="values.yaml"
UI_MANIFEST="mongo-express.yaml"

uninstall() {
  echo "Removing Mongo Express..."
  kubectl delete -f "$UI_MANIFEST" -n "$NAMESPACE" --ignore-not-found

  echo "Uninstalling MongoDB from namespace $NAMESPACE..."
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
  minikube) ;;
  *)
    echo "ERROR: current kubectl context '$CONTEXT' is not 'minikube'. Switch context, or use ../kind/deployment.sh for a kind cluster." >&2
    exit 1
    ;;
esac

echo "kubectl context : $CONTEXT"

# --- namespace (idempotent) ---
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# --- helm repo ---
helm repo add bitnami https://charts.bitnami.com/bitnami >/dev/null 2>&1 || true
helm repo update bitnami

# --- MongoDB (standalone) ---
helm upgrade --install "$RELEASE" bitnami/mongodb -n "$NAMESPACE" -f "$VALUES_FILE"

echo "Waiting for MongoDB to be ready..."
kubectl wait --for=condition=available deployment/"$RELEASE" -n "$NAMESPACE" --timeout=300s

# --- Mongo Express (idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$UI_MANIFEST"

echo "Waiting for Mongo Express to be ready..."
kubectl wait --for=condition=available deployment/mongo-express -n "$NAMESPACE" --timeout=180s

echo
echo "MongoDB deployed. Pods:"
kubectl get pods -n "$NAMESPACE"
echo
echo "MongoDB service (from inside the cluster):"
echo "  ${RELEASE}.${NAMESPACE}.svc:27017  (user: root, see values.yaml for password)"
echo
echo "Mongo Express (web UI):"
echo "  kubectl port-forward svc/mongo-express -n $NAMESPACE 8081:8081   then open http://localhost:8081"
