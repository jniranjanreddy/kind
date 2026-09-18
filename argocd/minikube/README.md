# Argo CD on minikube

Installs Argo CD into the `argocd` namespace of a local minikube cluster, and
registers an `Application` that tracks this repo:

- Repo: https://github.com/jniranjanreddy/argocd
- Branch: `minikube`
- Path: `k8s`
- Destination: `https://kubernetes.default.svc`, namespace `default`
- Sync policy: automated, with `selfHeal` and `prune` — any push to the
  `minikube` branch auto-syncs to the cluster, manual `kubectl` drift gets
  reverted, and resources removed from the branch get deleted from the
  cluster.

## Prerequisites

- `kubectl` pointed at your minikube cluster (`kubectl config current-context`
  should show `minikube`)
- Cluster access to reach `raw.githubusercontent.com` (Argo CD's own install
  manifest) and `github.com` (the tracked repo)

## Deploy

```bash
./deployment.sh
```

The script refuses to run unless the current kubectl context is exactly
`minikube`, to avoid installing minikube-sized config against the wrong
cluster.

What it does:

1. Creates the `argocd` namespace (idempotent).
2. Applies Argo CD's official install manifest
   (`https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml`)
   and waits for all its Deployments and the `argocd-application-controller`
   StatefulSet to be ready.
3. Applies [application.yaml](application.yaml), registering the `app`
   Application against the `minikube` branch.
4. Prints the pod list, the Application's status, and how to reach the UI.

Safe to re-run — every step is idempotent (`kubectl apply`). It also takes a
file lock (`.deployment.sh.lock`) for its duration, so a second concurrent
run fails fast instead of racing the first.

**Note:** as of this writing the `minikube` branch only has a `README.md` —
the `k8s` path this Application points to doesn't exist yet. Argo CD will
report the Application as an error until you add manifests under `k8s/` on
that branch and push. That's expected, not a bug in this script.

## Access the UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Open https://localhost:8080 (self-signed cert — accept the browser warning).
Log in as `admin` with the initial password:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

## Check status from the CLI

```bash
kubectl get applications -n argocd
kubectl describe application app -n argocd
```

## Tear down

```bash
./deployment.sh uninstall
```

Deletes the `app` Application, then the entire `argocd` namespace (which
removes Argo CD itself), and waits for the namespace to fully terminate.
Safe to run even if nothing is deployed. Does not touch the Git repo.
