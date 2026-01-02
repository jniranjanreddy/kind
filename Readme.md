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
## if you see bel;ow problem, this is the fix.
```
sysctl fs.inotify.max_user_instances=512
cat /etc/sysctl.conf
fs.inotify.max_user_instances=512
fs.inotify.max_user_watches=524288
```

How to get kubeconfig from Kind cluster
```
kind get kubeconfig --name my-kind-cluster > filename

```
## This is for PROD
```
kubectl create configmap airflow-webserver-config -n airflow --from-literal=webserver_config.py="WTF_CSRF_ENABLED = True
WTF_CSRF_TIME_LIMIT = 3600
SESSION_COOKIE_SAMESITE = 'Lax'
SESSION_COOKIE_SECURE = True" --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout status deployment airflow-api-server -n airflow
```
## after port-forward, if you see CORS error
<img width="261" height="96" alt="image" src="https://github.com/user-attachments/assets/6f1caf62-fe26-44e6-9766-a2354fc4577a" />

```
kubectl create configmap airflow-webserver-config -n airflow --from-literal=webserver_config.py="WTF_CSRF_ENABLED = False
WTF_CSRF_TIME_LIMIT = None
SESSION_COOKIE_SAMESITE = 'Lax'
SESSION_COOKIE_SECURE = False" --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout status deployment airflow-api-server -n airflow

```
