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
        value: "kubesamosa"
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
        value: "kubesamosa"
        effect: "NoSchedule"
```
## How to add new for kind
```
1. create user
     sudo useradd -m airflow
2. add to docker group
    sudo usermod -aG docker airflow
3. add to cat /etc/sudoers


if any issues
sudo chmod 666 /var/run/docker.sock

```
