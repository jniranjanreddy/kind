## Kind uses rancher storage.

## Label the nodes, so can simulate HPA.
```
 kubectl label node temporal-worker pool=temporal workload=temporal
```
## Steps to install Temporal in KIND.
```
1. create rancher storage
   1.1 kubectl create namespace temporal
   1.2 k apply -f kind-temporal-storageclass.yaml
   1.3 helm repo add bitnami https://charts.bitnami.com/bitnami
   1.4 helm repo update

2. Install Postgress - need postgres-values.yaml for helm, 
   helm install temporal-postgres bitnami/postgresql \
  --set primary.persistence.enabled=false \
  --set primary.nodeSelector=null \
  -n temporal

3. Craete required databases and changes need for postgres.
   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="password" psql -U temporal -c "CREATE DATABASE temporal;" #
   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="strongpassword" psql -U temporal -c "CREATE DATABASE temporal_visibility;"

   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="strongpassword" psql -U temporal -c "CREATE EXTENSION IF NOT EXISTS btree_gin;"
   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="strongpassword" psql -U temporal -c "CREATE EXTENSION IF NOT EXISTS pg_trgm;"
   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="strongpassword" psql -U temporal -c "CREATE EXTENSION IF NOT EXISTS uuid-ossp;"
   kubectl exec -it temporal-postgres-postgresql-0 -n temporal -- env PGPASSWORD="strongpassword" psql -U temporal -c "CREATE EXTENSION IF NOT EXISTS pgcrypto;"

```
## Actual Temporal deployment.
```
helm repo add temporal https://go.temporal.io/helm-charts 2>/dev/null || true
helm repo update

helm upgrade --install temporal temporal/temporal --namespace temporal -f temporal-values.yaml --timeout 30m

wait until all Tempral pods cimes up

kubectl exec -n temporal $(kubectl get pods -n temporal -l app.kubernetes.io/component=admintools -o jsonpath='{.items[0].metadata.name}') -- temporal operator namespace create default || true
## End of Temporal deployment
kubectl port-forward svc/temporal-web 8080:8080 -n temporal

helm install temporal-postgres bitnami/postgresql \
  --set primary.persistence.enabled=false \
  --set primary.nodeSelector=null \
  -n temporal
```
## Deploy Worker and workflow to see work.
```
Create structure
   mkdir temporal-hello
   cd temporal-hello
   
   mkdir app
   touch app/workflows.py
   touch app/worker.py
   touch app/client.py
   touch requirements.txt # add temporalio to requirements.txt
   touch Dockerfile








```

