## How to install Keda rules..
```

helm repo add kedacore https://kedacore.github.io/charts
helm repo update


helm install keda kedacore/keda \
  --namespace keda \
  --create-namespace

kubectl get pods -n keda
kubectl get crds | grep keda
```
## Testing Keda
```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx
spec:
  replicas: 1
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx
        resources:
          requests:
            cpu: "100m"
```
## Keda scaled objects
```
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: nginx-scaler
spec:
  scaleTargetRef:
    name: nginx
  minReplicaCount: 1
  maxReplicaCount: 5
  triggers:
  - type: cpu
    metadata:
      type: Utilization
      value: "50"
```


