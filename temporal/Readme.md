## Kind uses rancher storage.

## Label the nodes, so can simulate HPA.
```
kubectl label node temporal-control-plane pool=temporal
kubectl label node temporal-control-plane workload=temporal
```
## Steps to install Temporal in KIND.
```
1. create rancher storage
   1.1 kubectl create namespace temporal
   1.2 k apply -f kind-temporal-storageclass.yaml
   1.3 helm repo add bitnami https://charts.bitnami.com/bitnami
   1.4 helm repo update
2. Install Postgress - need postgres-values.yaml for helm, 
   2.1 helm install temporal-postgres bitnami/postgresql -n temporal -f postgres-values.yaml
   
```

```
helm install temporal-postgres bitnami/postgresql \
  --set primary.persistence.enabled=false \
  --set primary.nodeSelector=null \
  -n temporal
```
## lable node befor deploying
```

```
