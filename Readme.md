## two node cluster

```
cat kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: milvus-local

nodes:
- role: control-plane
- role: worker
  labels:
    node-id: "workernode1"
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "node-id=workernode1"
      taints:
      - key: "app"
        value: "kubesense"
        effect: "NoSchedule"
- role: worker
  labels:
    node-id: "workernode2"
  kubeadmConfigPatches:
  - |
    kind: JoinConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        node-labels: "node-id=workernode2"
      taints:
      - key: "app"
        value: "kubesense"
        effect: "NoSchedule"
```
