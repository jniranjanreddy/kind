# argocd
<img width="3008" height="1585" alt="image" src="https://github.com/user-attachments/assets/9e940de6-be8d-41b3-8c48-9e8890f0a47d" />

```
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
```
 Argo CD on kind — Deploy, Configure, Sync to GitHub

Argo CD is a **GitOps continuous delivery** tool for Kubernetes: it continuously compares what's in your Git repo (desired state) against what's running in the cluster (live state), and syncs them.

---

## Mind map — key components

```mermaid
mindmap
  root((Argo CD))
    Core components
      API Server
        gRPC/REST backend for UI, CLI, CI hooks
        handles auth, RBAC
      Repository Server
        clones/caches Git repos
        renders manifests: raw YAML, Helm, Kustomize, Jsonnet
      Application Controller
        the reconciliation loop
        compares live state vs desired (Git) state
        triggers sync, reports health/status
      Redis
        caches repo/app state for speed
      Dex (optional)
        SSO integration: GitHub, OIDC, LDAP, SAML
      ApplicationSet Controller (optional)
        generates many Applications from one template
        e.g. one per cluster, per repo folder, per PR
      Notifications Controller (optional)
        Slack/email/webhook alerts on sync/health events
    CRDs it introduces
      Application
        one deployable unit: source repo/path + destination cluster/namespace
      AppProject
        RBAC boundary: which repos, clusters, namespaces, resource kinds are allowed
      ApplicationSet
        template that generates multiple Applications
    Core concepts
      Sync policy
        Manual — you click/run sync
        Automated — auto-applies Git changes
      Self-heal
        reverts manual cluster drift back to Git state
      Prune
        deletes resources removed from Git
      Sync waves
        ordering hooks (e.g. DB migration before app deploy)
      Health checks
        Healthy / Degraded / Progressing / Missing status per resource
    Interfaces
      Web UI
      argocd CLI
      kubectl (via Application CRD)
      declarative YAML (GitOps for Argo CD itself)
```

---

## Prerequisites

```bash
# Docker (for kind), kind, kubectl, and the argocd CLI
docker --version
kind version || go install sigs.k8s.io/kind@latest
kubectl version --client

# argocd CLI (Linux example)
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

---

## Step 1 — Create the kind cluster

```bash
kind create cluster --name argocd-demo
kubectl cluster-info --context kind-argocd-demo
```

## Step 2 — Install Argo CD

```bash
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl get pods -n argocd -w
```

## Step 3 — Access the UI/CLI

```bash
# Port-forward the API server (kind has no LoadBalancer by default)
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get the auto-generated initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo

# Log in via CLI
argocd login localhost:8080 --username admin --password <password-from-above> --insecure

# (Recommended) change the password
argocd account update-password
```
Open `https://localhost:8080` in a browser for the UI (accept the self-signed cert warning).

## Step 4 — Connect your GitHub repo

```bash
# Public repo — no auth needed
argocd repo add https://github.com/jniranjanreddy/argocd-manifests.git

# Private repo — HTTPS with a PAT
argocd repo add https://github.com/<your-user>/<your-repo>.git \
  --username <your-user> --password <github-PAT>

# Private repo — SSH key instead
argocd repo add git@github.com:<your-user>/<your-repo>.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

## Step 5 — Create an Application (CLI way)

```bash
argocd app create my-app \
  --repo https://github.com/jniranjanreddy/argocd-manifests.git \
  --revision qa \
  --path k8s/apps \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace apps \
  --sync-policy automated \
  --self-heal \
  --auto-prune

# Trigger a sync manually (if not automated)
argocd app sync my-app

# Check status
argocd app get my-app
```

---

## The declarative way (GitOps for Argo CD itself — recommended)

Instead of `argocd app create`, commit this `Application` manifest to Git and `kubectl apply` it — now Argo CD's own config is also GitOps-managed:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/<your-user>/<your-repo>.git
    targetRevision: main
    path: k8s/manifests
  destination:
    server: https://kubernetes.default.svc
    namespace: default
  syncPolicy:
    automated:
      prune: true      # delete resources removed from Git
      selfHeal: true    # revert manual kubectl edits back to Git state
    syncOptions:
      - CreateNamespace=true
```
```bash
kubectl apply -f my-app-application.yaml -n argocd
```

---

## 3 examples

### 1. Plain Kubernetes manifests, manual sync
```yaml
spec:
  source:
    repoURL: https://github.com/myorg/myapp.git
    path: manifests/prod
    targetRevision: main
  syncPolicy: {}   # empty = manual, you click "Sync" in UI or run `argocd app sync`
```

### 2. Helm chart from your repo, automated sync
```yaml
spec:
  source:
    repoURL: https://github.com/myorg/myapp.git
    path: charts/myapp
    targetRevision: main
    helm:
      valueFiles:
        - values-prod.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 3. ApplicationSet — one Application per environment folder
```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-envs
  namespace: argocd
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/myapp.git
        revision: main
        directories:
          - path: envs/*
  template:
    metadata:
      name: '{{path.basename}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/myapp.git
        targetRevision: main
        path: '{{path}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{path.basename}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```
One repo folder (`envs/dev`, `envs/staging`, `envs/prod`) → one Argo CD Application each, automatically.

---

## argocd CLI cheat sheet

```bash
# Apps
argocd app list
argocd app get <app-name>
argocd app sync <app-name>
argocd app history <app-name>
argocd app rollback <app-name> <history-id>
argocd app diff <app-name>            # shows Git vs live drift
argocd app delete <app-name>

# Repos
argocd repo list
argocd repo rm <repo-url>

# Clusters (for multi-cluster setups)
argocd cluster list
argocd cluster add <kube-context-name>

# Projects (RBAC scoping)
argocd proj list
argocd proj create <project-name>
```

## kubectl equivalents (since Application is just a CRD)
```bash
kubectl get applications -n argocd
kubectl get application <app-name> -n argocd -o yaml
kubectl describe application <app-name> -n argocd
kubectl get appprojects -n argocd
```

---

## Key ideas to hold onto

- **Application = source (Git repo/path/branch) + destination (cluster/namespace).**
- **AppProject = RBAC fence** around which repos/clusters/namespaces/resource kinds an Application is allowed to touch — use this once you have multiple teams.
- **Automated sync + self-heal + prune** together = true GitOps: Git is the single source of truth, manual `kubectl` changes get reverted, and deleted files in Git delete resources in the cluster.
- **ApplicationSet** is how you scale from "one app" to "one app across many folders/clusters/repos" without copy-pasting Application YAML.
