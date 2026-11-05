# Temporal workers on kind (`obs-kind`)

Three Python workers, each with its own image, Deployment and task queue, all in
namespace `temporal`, talking to `temporal-frontend.temporal.svc.cluster.local:7233`.

| Worker / task queue | Folder | Workflow | What it demonstrates |
|---|---|---|---|
| `appointment-scheduler` | `appointment-scheduler/` | `AppointmentWorkflow` | Long-running workflow waiting for a human: **signals** (`confirm`, `cancel`), a **query** (`status`), **wait with timeout**, **durable timer** (reminder) |
| `claims-processor` | `claims-processor/` | `ClaimWorkflow` | Failure handling: **automatic retries** (flaky eligibility check), **non-retryable errors** (invalid claim), **parallel activities** (fraud + pricing), branching on results |
| `prescription-fulfillment` | `prescription-fulfillment/` | `FulfillmentWorkflow` | **Saga**: reserve → charge → pack → ship; on failure **undo completed steps in reverse** (refund, release). **Heartbeats** on the long packing step, so a crashed worker is detected in seconds and the step resumes where it stopped |

Each folder holds `workflows.py` (workflow + activities), `worker.py`, `Dockerfile`,
`deployment.yaml` and `starter.py`. `starter.py` is baked into the image so you can
run the example with `kubectl exec`.

Workers handle SIGTERM: on a pod stop or rollout they stop taking new work, give
running activities up to 20s to finish, and exit. Without this, Python as PID 1
ignores SIGTERM and every stop waits the full 30s and then kills the worker mid-task.

## Build and deploy

kind nodes can't see your local Docker images, so every build must be **loaded**
into the cluster. Use a **new tag** for every change: with
`imagePullPolicy: IfNotPresent`, reusing a tag can keep the old image running.

```bash
cd ~/kind/temporal/temporal-hello
NAME=claims-processor TAG=0.1.2        # or appointment-scheduler / prescription-fulfillment

docker build -t $NAME:$TAG $NAME
kind load docker-image $NAME:$TAG --name obs-kind
kubectl --context kind-obs-kind apply -f $NAME/deployment.yaml    # image tag must match
kubectl --context kind-obs-kind -n temporal rollout status deploy/$NAME
```

Upgrading to a new tag:

```bash
kubectl --context kind-obs-kind -n temporal set image deploy/$NAME worker=$NAME:<new-tag>
```

Or edit the tag in the manifest and re-apply.

## Run the examples

```bash
K="kubectl --context kind-obs-kind -n temporal"

# 4 claims at once, one per outcome
$K exec deploy/claims-processor -- python3 starter.py
#   C-100: approved      payout=   960.00  PAY-C-100       (eligibility retried twice first)
#   C-200: rejected      payout=     0.00  invalid claim … (failed fast, no retries)
#   C-300: rejected      payout=     0.00  no active coverage
#   C-400: manual_review payout=     0.00  fraud score 0.96

# prescriptions: shipped / out of stock / failed at the last step -> compensated
$K exec deploy/prescription-fulfillment -- python3 starter.py
#   RX-3: failed_compensated
#     - reserved RES-RX-3 - charged CHG-RX-3 - packed BOX-RX-3
#     - FAILED: no delivery address
#     - refunded payment - released stock          (undone in reverse order)

# appointment: confirm | cancel | none (expires after 60s)
$K exec deploy/appointment-scheduler -- python3 starter.py confirm
#   status: awaiting_confirmation
#   result: APT-P1001-2026-11-10T0930: confirmed, reminder sent
```

Watch them in the UI at **https://dev-temporal.raai.site** (namespace `default`).
For a claim, open *Event History* to see `check_eligibility` with attempts 1–3, and
`fraud_score` / `price_claim` scheduled at the same time.

### Drive an appointment by hand with the Temporal CLI

Start one that waits up to 10 minutes:

```bash
$K exec deploy/temporal-admintools -- temporal workflow start \
  --task-queue appointment-scheduler --type AppointmentWorkflow --workflow-id appt-demo \
  --input '{"patient_id":"P2002","doctor":"Iyer","slot":"2026-11-12 14:00","confirm_timeout_seconds":600,"reminder_delay_seconds":20}'
```

Check its status (query), then confirm it (signal):

```bash
$K exec deploy/temporal-admintools -- temporal workflow query --workflow-id appt-demo --type status
$K exec deploy/temporal-admintools -- temporal workflow signal --workflow-id appt-demo --name confirm
```

Wait for the result:

```bash
$K exec deploy/temporal-admintools -- temporal workflow result --workflow-id appt-demo
```

### See heartbeats recover a crashed worker

Start an order, then kill the worker container (a hard crash, not a graceful stop)
while it packs:

```bash
$K exec deploy/temporal-admintools -- temporal workflow start \
  --task-queue prescription-fulfillment --type FulfillmentWorkflow --workflow-id rx-crash \
  --input '{"rx_id":"RX-9","patient_id":"P9","drug":"insulin","quantity":10,"price":99.0,"address":"1 Test Ave"}'
```

Within ~3s Temporal reports `Heartbeat timeout` and starts `pack_order` attempt 2 on
the restarted pod, continuing from the last heartbeat. The order still ships.

Try `kubectl delete pod -l app=appointment-scheduler` while it waits: the workflow
picks up where it was once the new pod starts. Its state lives in Temporal, not in
the pod.

## Scaling

Workers are stateless. Run more replicas to process a queue faster:

```bash
kubectl --context kind-obs-kind -n temporal scale deploy/claims-processor --replicas=3
```

Check who is polling a queue:

```bash
$K exec deploy/temporal-admintools -- temporal task-queue describe --task-queue claims-processor
```

## Adding another worker

1. Copy a folder, rename it, and change the code in `workflows.py` and `worker.py`.
2. Set the new name (Deployment, labels, image, `TASK_QUEUE`) in `deployment.yaml`.
3. Build, load and apply as above.

Workflow code must be **deterministic**: no direct I/O, `random`, `datetime.now()`
or network calls inside the workflow class. Put those in activities. Use
`workflow.now()` and `asyncio.sleep()` (a durable timer) in workflows.
