## 
```
cat kind-istio-cluster.yaml
# kind-istio-cluster.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: istio-cluster
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - containerPort: 80
        hostPort: 80
        protocol: TCP
      - containerPort: 443
        hostPort: 443
        protocol: TCP
  - role: worker
networking:
  disableDefaultCNI: false
  kubeProxyMode: "iptables"

kind create cluster --config kind-istio-cluster.yaml

kubectl get nodes

kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl get pods -n metallb-system

## Configure MetalLB IP range
## Get the Docker network IP range:
docker network inspect -f '{{.IPAM.Config}}' kind
Example output: - [{172.18.0.0 16}]

cat metallb-config.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: default-pool
  namespace: metallb-system
spec:
  addresses:
    - 172.18.255.200-172.18.255.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: default-advertisement
  namespace: metallb-system

kubectl apply -f metallb-config.yaml


## istio
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.23.2 sh -

cd istio-1.23.2
export PATH=$PWD/bin:$PATH
kubectl get svc -n istio-system



## deploy App
kubectl apply -f samples/bookinfo/platform/kube/bookinfo.yaml
kubectl apply -f samples/bookinfo/networking/bookinfo-gateway.yaml

export INGRESS_IP=$(kubectl get svc istio-ingressgateway -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "http://${INGRESS_IP}/productpage"

```
## get kubeconfig
```
kind get kubeconfig --name airflow-3x > kind-airflow.yaml
kubectl --kubeconfig kind-airflow.yaml get pods -A
NAMESPACE            NAME                                               READY   STATUS    RESTARTS        AGE
kube-system          coredns-674b8bbfcf-vjp9c                           1/1     Running   0               4m32s
kube-system          coredns-674b8bbfcf-z47w7                           1/1     Running   0               4m32s
kube-system          etcd-airflow-3x-control-plane                      1/1     Running   0               4m36s
kube-system          kindnet-xsc9x                                      1/1     Running   0               4m32s
kube-system          kube-apiserver-airflow-3x-control-plane            1/1     Running   0               4m36s
kube-system          kube-controller-manager-airflow-3x-control-plane   1/1     Running   0               4m36s
kube-system          kube-proxy-zq5bp                                   1/1     Running   5 (2m53s ago)   4m32s
kube-system          kube-scheduler-airflow-3x-control-plane            1/1     Running   0               4m36s
local-path-storage   local-path-provisioner-7dc846544d-pfp9k            1/1     Running   5 (112s ago)    4m32s
```
