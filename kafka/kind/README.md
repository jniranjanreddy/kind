# Strimzi Kafka on kind

Installs the [Strimzi](https://strimzi.io/) Kafka operator into the `kafka`
namespace of a local kind cluster, then creates a single-node, KRaft-mode
Kafka cluster (`my-cluster`) from [kafka-cluster.yaml](kafka-cluster.yaml) —
no ZooKeeper (removed in Strimzi 1.x), ephemeral storage (no StorageClass
dependency), and trimmed-down resource requests since this shares the node
with other dev workloads. Also deploys two web UIs for browsing the
cluster: [Kafdrop](kafdrop.yaml) and [AKHQ](akhq.yaml).

## Prerequisites

- `kubectl` pointed at your kind cluster (`kubectl config current-context`
  should show `kind-*`)
- Cluster access to reach `strimzi.io` (the operator's install manifest) and
  `quay.io` (operator + Kafka broker images)

## Deploy

```bash
./deployment.sh
```

The script refuses to run unless the current kubectl context matches
`kind-*`, to avoid installing against the wrong cluster.

What it does:

1. Creates the `kafka` namespace (idempotent).
2. Applies Strimzi's official install manifest
   (`https://strimzi.io/install/latest?namespace=kafka`) with
   `--server-side` (Strimzi's Kafka CRD is too large for client-side
   `kubectl apply`'s annotation limit) and waits for the
   `strimzi-cluster-operator` Deployment to be ready.
3. Applies [kafka-cluster.yaml](kafka-cluster.yaml) — a `KafkaNodePool`
   (single dual-role controller+broker node) and a `Kafka` resource — and
   waits for the `Kafka` custom resource to report `Ready` (this pulls
   broker images and can take a few minutes on a fresh cluster).
4. Applies [kafdrop.yaml](kafdrop.yaml) and [akhq.yaml](akhq.yaml) (both
   pointed at the `my-cluster-kafka-bootstrap:9092` bootstrap address) and
   waits for both Deployments to be ready.
5. Prints the pod list, the Kafka cluster status, the in-cluster bootstrap
   address, example producer/consumer commands, and how to reach both UIs.

Safe to re-run — every step is idempotent (`kubectl apply`). It also takes a
file lock (`.deployment.sh.lock`) for its duration, so a second concurrent
run fails fast instead of racing the first.

## Using the cluster

Bootstrap address, from inside the cluster:

```
my-cluster-kafka-bootstrap.kafka.svc:9092
```

Quick produce/consume from a throwaway pod (no client install needed):

```bash
kubectl run kafka-producer -ti --image=quay.io/strimzi/kafka:1.2.0-kafka-4.3.1 \
  --rm=true --restart=Never -n kafka -- \
  bin/kafka-console-producer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic

kubectl run kafka-consumer -ti --image=quay.io/strimzi/kafka:1.2.0-kafka-4.3.1 \
  --rm=true --restart=Never -n kafka -- \
  bin/kafka-console-consumer.sh --bootstrap-server my-cluster-kafka-bootstrap:9092 --topic my-topic --from-beginning
```

Check cluster/topic/user status:

```bash
kubectl get kafka,kafkanodepools,kafkatopics,kafkausers -n kafka
kubectl describe kafka my-cluster -n kafka
```

Topics and users can be managed declaratively too — Strimzi's Topic
Operator and User Operator (both enabled in `kafka-cluster.yaml`) reconcile
`KafkaTopic` and `KafkaUser` custom resources the same way the `Kafka`
resource itself works.

## Web UIs

Both are ClusterIP-only — reach them via port-forward:

```bash
kubectl port-forward svc/kafdrop -n kafka 9000:9000   # then open http://localhost:9000
kubectl port-forward svc/akhq -n kafka 8085:8080      # then open http://localhost:8085
```

- **[Kafdrop](https://github.com/obsidiandynamics/kafdrop)** — lightweight,
  read-only: browse topics, partitions, consumer groups, and messages.
- **[AKHQ](https://github.com/tchiotludo/akhq)** — fuller-featured: the
  above plus message tailing/search, ACLs, schema registry, and Kafka
  Connect if you add those later. Its Kafka connection is configured in
  [akhq.yaml](akhq.yaml)'s `akhq-config` ConfigMap — add more `akhq.connections.<name>`
  entries there if you point it at other clusters.

## Expected warning: ephemeral storage

`kubectl get kafka -n kafka` shows `WARNINGS: True` — this is expected, not
a problem:

```
A Kafka cluster with a single broker node and ephemeral storage will lose
topic messages after any restart or rolling update.
```

That's the deliberate tradeoff of using `type: ephemeral` storage: no
StorageClass dependency, nothing to provision, and it's disposable dev data
anyway. To get durability across restarts instead, edit
[kafka-cluster.yaml](kafka-cluster.yaml)'s `KafkaNodePool.spec.storage` to:

```yaml
storage:
  type: jbod
  volumes:
    - id: 0
      type: persistent-claim
      size: 10Gi
      kraftMetadata: shared
```

then re-run `./deployment.sh` (this requires a working StorageClass on the
cluster — kind's default `standard` class works out of the box).

## Tear down

```bash
./deployment.sh uninstall
```

Deletes Kafdrop, AKHQ, and the Kafka cluster (`KafkaNodePool` + `Kafka`),
then the entire `kafka` namespace (which removes the Strimzi operator
itself), and waits for the namespace to fully terminate. Safe to run even if
nothing is deployed.
