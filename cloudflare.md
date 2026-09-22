# Local ingress: hostnames + real HTTPS for a laptop cluster

The mental model behind giving services on a local kind cluster real
hostnames (`attu.raai.site`, `argocd.raai.site`, ...) with real,
browser-trusted HTTPS - no port-forwarding, no self-signed-cert warnings.
Written so you can repeat this by hand on a different cluster; the actual
resources for *this* cluster live in [kind/](kind/).

There are four independent problems being solved, stacked on top of each
other. Understand them in this order:

## 1. Get *a* port from your laptop into the cluster

A `kind` cluster has no real LoadBalancer (no cloud provider, no MetalLB) -
`kubectl get svc -n istio-system istio-ingressgateway` shows
`EXTERNAL-IP: <pending>` forever. Traffic has to get in some other way.

- **kind**: `extraPortMappings` in the cluster config map a host port
  straight to a `containerPort` on the node (the node is just a docker
  container). This only takes effect at cluster *creation* time - you
  cannot add a mapping to a running cluster, only recreate it. Point the
  mapping at fixed NodePorts on the ingress gateway's Service (see step 2),
  not directly at container port 80/443:
  ```yaml
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 30080   # matches the Service nodePort below
      hostPort: 80
    - containerPort: 30443
      hostPort: 443
  ```
- **minikube**: `minikube tunnel` (routes LoadBalancer IPs to your host,
  needs a terminal kept open) or `minikube service` for one-off access, or
  the same NodePort approach as above via `minikube ip`.
- Binding host port 80/443 directly needs root (`ip_unprivileged_port_start`
  is usually 1024) - if you're not running as root, forward to a high port
  instead and put it in the URL (`:8080`), or accept the root requirement.

## 2. Pin the ingress gateway's Service ports so the mapping is stable

`istio-ingressgateway`'s Service is `type: LoadBalancer`, which still
allocates NodePorts even with a pending external IP - but Helm picks random
ones on every install. Patch them to fixed values so your kind config's
`extraPortMappings` (which are baked in at cluster-create time) always land
on the right port:
```bash
kubectl patch svc istio-ingressgateway -n istio-system --type merge -p '
{"spec":{"ports":[
  {"name":"http2","nodePort":30080,"port":80,"protocol":"TCP","targetPort":8080},
  {"name":"https","nodePort":30443,"port":443,"protocol":"TCP","targetPort":8443}
]}}'
```
(Keep the Service's other ports - status-port, tcp, tls - unchanged; only
list the ones you're overriding won't work, `kubectl patch --type merge` on
`.spec.ports` replaces the *whole list*, so include every port entry.)

Now `curl -H "Host: whatever" http://localhost/` on the laptop reaches
Envoy at the ingress gateway - Istio just has no routing rules yet.

## 3. Route hostnames to services with Gateway + VirtualService

One shared `Gateway` (in `istio-system`, selecting the ingress gateway
pod) declares which hostnames/ports it accepts. One `VirtualService` per
app (in the app's own namespace) says where a given hostname's traffic
goes:
```yaml
apiVersion: networking.istio.io/v1
kind: Gateway
metadata:
  name: raai-gateway
  namespace: istio-system
spec:
  selector: {istio: ingressgateway}
  servers:
  - port: {number: 443, name: https, protocol: HTTPS}
    tls: {mode: SIMPLE, credentialName: raai-site-tls}   # see step 4
    hosts: ["*.raai.site"]
  - port: {number: 80, name: http, protocol: HTTP}
    tls: {httpsRedirect: true}
    hosts: ["*.raai.site"]
---
apiVersion: networking.istio.io/v1
kind: VirtualService
metadata:
  name: attu-vs
  namespace: milvus            # lives with the app it routes to
spec:
  hosts: ["attu.raai.site"]
  gateways: ["istio-system/raai-gateway"]
  http:
  - route:
    - destination: {host: attu.milvus.svc.cluster.local, port: {number: 3000}}
```
`credentialName` in the Gateway's `tls` block looks up a Secret **in the
Gateway's own namespace** by default - that's why the cert Secret has to
be created in `istio-system` even though the apps it's for live elsewhere.

**If a backend already serves its own TLS** (e.g. Argo CD's `argocd-server`
defaults to HTTPS-only on its port, redirecting plain HTTP) route to its
HTTPS port and add a `DestinationRule` telling Envoy to originate TLS to it
and skip verifying its (self-signed) cert, instead of weakening the backend
itself with `--insecure`:
```yaml
apiVersion: networking.istio.io/v1
kind: DestinationRule
metadata: {name: argocd-server-tls-origination, namespace: argocd}
spec:
  host: argocd-server.argocd.svc.cluster.local
  trafficPolicy:
    tls: {mode: SIMPLE, insecureSkipVerify: true}
```

## 4. Get a real cert for a name nobody publicly hosts

You don't need the hostname to be reachable from the internet to get a
real, browser-trusted certificate - you need to **own the domain's DNS**.
That's what Let's Encrypt's **DNS-01** challenge checks (as opposed to
HTTP-01, which requires a publicly reachable server on port 80): it asks
you to create a `_acme-challenge.<domain>` TXT record proving you control
the zone, and never touches the A record or tries to connect to the host
at all. So `attu.raai.site` can point at `127.0.0.1` in your hosts file
forever and still get a real cert.

Requirements:
- A domain you actually registered (any TLD - `.site`, `.com`, doesn't
  matter to Let's Encrypt), with DNS hosted somewhere `cert-manager` has a
  solver for (Cloudflare, Route53, Google Cloud DNS, ...). Cloudflare is a
  good choice: sells domains at cost, and its DNS-01 solver is built into
  cert-manager core.
- `cert-manager` installed in-cluster (Helm chart `jetstack/cert-manager`,
  `--set crds.enabled=true`).
- An API token scoped to `Zone:DNS:Edit` + `Zone:Zone:Read` for just that
  zone, stored as a Secret cert-manager's solver reads:
  ```bash
  kubectl create secret generic cloudflare-api-token-secret \
    -n cert-manager --from-literal=api-token=<token>
  ```
- A `ClusterIssuer` referencing that Secret, and a `Certificate` naming the
  hostnames you want (a wildcard `*.raai.site` needs DNS-01 - HTTP-01 can't
  do wildcards at all) and a `secretName` - cert-manager issues into that
  Secret, which the Gateway's `credentialName` then references.

**Always test against the staging ACME server first**
(`https://acme-staging-v02.api.letsencrypt.org/directory`) - production
rate-limits hard (5 failures/hour per hostname, 50 certs/week per
registered domain), and staging has no such limit. Staging certs aren't
trusted by real browsers (wrong root CA) but prove the DNS-01 plumbing
works end to end. Once `kubectl get certificate` shows `READY: True`
against staging, flip the `Certificate`'s `issuerRef.name` to
`letsencrypt-prod` and re-apply - that's the only change needed.

If a `Certificate` sits `READY: False` for a while, check the `Challenge`
it spawned - `kubectl describe challenge -n <ns>`. "Waiting for DNS-01
challenge propagation" that doesn't clear for a long time on a
freshly-registered domain is usually the registry's NS delegation to your
DNS host still propagating (can take minutes, occasionally longer) rather
than the TXT record itself - verify directly against the domain's own
authoritative nameservers to tell the difference:
```bash
dig NS <domain> +short @8.8.8.8                       # who's authoritative
dig TXT _acme-challenge.<domain> +short @<that-ns>     # does the record exist there
```
If it's already there on the authoritative server, cert-manager is just on
its own backoff timer - `kubectl delete challenge -n <ns> --all` forces an
immediate recheck without waiting it out.

## Windows hosts file (WSL2 specifically)

The browser runs on Windows, not inside WSL - `/etc/hosts` inside WSL only
affects tools run from a WSL shell (`curl`, etc.), not the Windows browser.
Edit `C:\Windows\System32\drivers\etc\hosts` (reachable from WSL at
`/mnt/c/Windows/System32/drivers/etc/hosts`) instead:
```
127.0.0.1   attu.raai.site
127.0.0.1   argocd.raai.site
```
WSL2's automatic localhost-forwarding means a port a process binds to
inside WSL (e.g. the kind node container's mapped host port) is reachable
from Windows as `localhost`/`127.0.0.1` too, so this just works without
any extra networking setup.

## End-to-end checklist for a new cluster

1. Create the cluster with `extraPortMappings` for 80/443 -> two fixed
   NodePort numbers you'll reuse below (only possible at cluster-create
   time for kind).
2. Install Istio; patch `istio-ingressgateway`'s Service to use those exact
   NodePorts for its `http2`/`https` ports.
3. Install `cert-manager`; create the DNS provider's API token Secret;
   apply `ClusterIssuer`s (staging + prod).
4. Apply a `Certificate` for your hostnames, issuer = staging first.
   Confirm `READY: True`, then switch to prod and re-apply.
5. Apply the shared `Gateway` (HTTPS listener using the cert Secret, HTTP
   listener with `httpsRedirect: true`) in `istio-system`.
6. Per app: a `VirtualService` (+ a `DestinationRule` if the backend
   already terminates its own TLS) in the app's namespace, referencing the
   shared Gateway.
7. Add the hostnames to the Windows hosts file, pointed at `127.0.0.1`.
8. `curl -kI -H "Host: <name>" https://localhost/` to sanity-check routing
   before trying the browser.
