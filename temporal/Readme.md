## Kind uses rancher storage.



```
helm install temporal-postgres bitnami/postgresql \
  --set primary.persistence.enabled=false \
  --set primary.nodeSelector=null \
  -n temporal
```
