#!/usr/bin/env bash
#
# Installs Argo CD into the "argocd" namespace of a local kind cluster, and
# registers the Application in application.yaml — tracks the "kind" branch of
# https://github.com/jniranjanreddy/argocd.git (path "k8s"), automated sync
# with self-heal and prune.
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

NAMESPACE=argocd
INSTALL_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
APPLICATION_MANIFEST="application.yaml"

uninstall() {
  echo "Removing Argo CD Application (this does not touch the target repo/branch)..."
  kubectl delete -f "$APPLICATION_MANIFEST" -n "$NAMESPACE" --ignore-not-found

  echo "Uninstalling Argo CD from namespace $NAMESPACE..."
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

# --- Argo CD install (idempotent: kubectl apply) ---
# --server-side avoids the "metadata.annotations: Too long" error that
# client-side apply hits on Argo CD's large ApplicationSet CRD (the
# last-applied-configuration annotation exceeds Kubernetes' 262144-byte limit).
kubectl apply -n "$NAMESPACE" --server-side --force-conflicts -f "$INSTALL_MANIFEST"

echo "Waiting for Argo CD components to be ready..."
kubectl wait --for=condition=available deployment --all -n "$NAMESPACE" --timeout=300s
kubectl rollout status statefulset/argocd-application-controller -n "$NAMESPACE" --timeout=300s

# --- register the Application (declarative GitOps for Argo CD itself) ---
kubectl apply -n "$NAMESPACE" -f "$APPLICATION_MANIFEST"

echo
echo "Argo CD deployed. Pods:"
kubectl get pods -n "$NAMESPACE"
echo
echo "Application:"
kubectl get application -n "$NAMESPACE"
echo
echo "Access the UI:"
echo "  kubectl port-forward svc/argocd-server -n $NAMESPACE 8080:443"
echo "  then open https://localhost:8080  (user: admin)"
echo
echo "Initial admin password:"
echo "  kubectl -n $NAMESPACE get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo"
