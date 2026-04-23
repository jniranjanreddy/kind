## Kind uses rancher storage.



```
helm install temporal-postgres bitnami/postgresql \
  --set primary.persistence.enabled=false \
  --set primary.nodeSelector=null \
  -n temporal
```
## lable node befor deploying
```
kubectl label node temporal-control-plane pool=temporal
kubectl label node temporal-control-plane workload=temporal
```
