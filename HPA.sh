#!/bin/bash

set -e

APP_NAME=php-apache
NAMESPACE=default

echo "🚀 Creating Kubernetes Deployment, Service, and HPA..."

# ----------------------------
# Deployment
# ----------------------------
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $APP_NAME
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $APP_NAME
  template:
    metadata:
      labels:
        app: $APP_NAME
    spec:
      containers:
      - name: php-apache
        image: registry.k8s.io/hpa-example
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi
EOF

echo "📦 Deployment created"

# ----------------------------
# Service
# ----------------------------
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: $APP_NAME
spec:
  selector:
    app: $APP_NAME
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

echo "🌐 Service created"

# ----------------------------
# HPA
# ----------------------------
cat <<EOF | kubectl apply -f -
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: $APP_NAME
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: $APP_NAME
  minReplicas: 1
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 50
EOF

echo "📊 HPA created"

echo "✅ Setup completed successfully!"

echo "-----------------------------------"
kubectl get deployment,svc,hpa


## load test - kubectl run load-generator -it --rm --image=busybox -- /bin/sh -c "while true; do wget -q -O- http://php-apache; done"

