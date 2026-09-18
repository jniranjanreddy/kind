#!/usr/bin/env bash
#
# Installs the Strimzi Kafka operator into the "kafka" namespace of a local
# minikube cluster, then creates a single-node KRaft Kafka cluster from
# kafka-cluster.yaml (KafkaNodePool + Kafka custom resources).
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

NAMESPACE=kafka
INSTALL_MANIFEST="https://strimzi.io/install/latest?namespace=${NAMESPACE}"
KAFKA_MANIFEST="kafka-cluster.yaml"
KAFKA_CLUSTER_NAME="my-cluster"
KAFDROP_MANIFEST="kafdrop.yaml"
AKHQ_MANIFEST="akhq.yaml"

uninstall() {
  echo "Removing Kafdrop and AKHQ..."
  kubectl delete -f "$KAFDROP_MANIFEST" -n "$NAMESPACE" --ignore-not-found
  kubectl delete -f "$AKHQ_MANIFEST" -n "$NAMESPACE" --ignore-not-found

  echo "Removing the Kafka cluster (KafkaNodePool + Kafka)..."
  kubectl delete -f "$KAFKA_MANIFEST" -n "$NAMESPACE" --ignore-not-found

  echo "Uninstalling the Strimzi operator from namespace $NAMESPACE..."
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

# --server-side avoids the "metadata.annotations: Too long" error that
# client-side apply hits on Strimzi's large Kafka CRD (its schema exceeds
# Kubernetes' 262144-byte last-applied-configuration annotation limit).
kubectl apply -n "$NAMESPACE" --server-side --force-conflicts -f "$INSTALL_MANIFEST"

echo "Waiting for the Strimzi operator to be ready..."
kubectl wait --for=condition=available deployment/strimzi-cluster-operator -n "$NAMESPACE" --timeout=300s

# kubectl's client-side discovery cache doesn't know about the CRDs just
# created above yet, so applying kafka-cluster.yaml right away can fail with
# "no matches for kind ... ensure CRDs are installed first". Wait for them
# to be Established before using them.
echo "Waiting for Strimzi CRDs to be established..."
kubectl wait --for=condition=Established \
  crd/kafkas.kafka.strimzi.io crd/kafkanodepools.kafka.strimzi.io \
  --timeout=120s

# --- Kafka cluster (idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$KAFKA_MANIFEST"

echo "Waiting for the Kafka cluster to be ready (pulls broker images — can take a few minutes)..."
kubectl wait kafka/"$KAFKA_CLUSTER_NAME" -n "$NAMESPACE" --for=condition=Ready --timeout=600s

# --- Kafdrop + AKHQ (web UIs, idempotent) ---
kubectl apply -n "$NAMESPACE" -f "$KAFDROP_MANIFEST"
kubectl apply -n "$NAMESPACE" -f "$AKHQ_MANIFEST"

echo "Waiting for Kafdrop and AKHQ to be ready..."
kubectl wait --for=condition=available deployment/kafdrop -n "$NAMESPACE" --timeout=180s
kubectl wait --for=condition=available deployment/akhq -n "$NAMESPACE" --timeout=180s

echo
echo "Kafka deployed. Pods:"
kubectl get pods -n "$NAMESPACE"
echo
echo "Kafka cluster:"
kubectl get kafka -n "$NAMESPACE"
echo
echo "Bootstrap address (from inside the cluster):"
echo "  ${KAFKA_CLUSTER_NAME}-kafka-bootstrap.${NAMESPACE}.svc:9092"
echo
echo "Produce/consume from a throwaway pod:"
echo "  kubectl run kafka-producer -ti --image=quay.io/strimzi/kafka:1.2.0-kafka-4.3.1 --rm=true --restart=Never -n $NAMESPACE -- bin/kafka-console-producer.sh --bootstrap-server ${KAFKA_CLUSTER_NAME}-kafka-bootstrap:9092 --topic my-topic"
echo "  kubectl run kafka-consumer -ti --image=quay.io/strimzi/kafka:1.2.0-kafka-4.3.1 --rm=true --restart=Never -n $NAMESPACE -- bin/kafka-console-consumer.sh --bootstrap-server ${KAFKA_CLUSTER_NAME}-kafka-bootstrap:9092 --topic my-topic --from-beginning"
echo
echo "Web UIs:"
echo "  Kafdrop: kubectl port-forward svc/kafdrop -n $NAMESPACE 9000:9000   then open http://localhost:9000"
echo "  AKHQ:    kubectl port-forward svc/akhq -n $NAMESPACE 8085:8080     then open http://localhost:8085"
