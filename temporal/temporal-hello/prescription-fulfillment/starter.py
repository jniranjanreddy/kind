"""Run three prescriptions at once, one per outcome, and print each step.

    python3 starter.py
"""
import asyncio
import os
import uuid

from temporalio.client import Client

from workflows import FulfillmentWorkflow, Prescription

ADDRESS = os.getenv("TEMPORAL_ADDRESS", "localhost:7233")
NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "prescription-fulfillment")

SAMPLES = [
    # shipped: every step succeeds
    Prescription("RX-1", "P1001", "amoxicillin", 30, 18.50, "12 Main St"),
    # out of stock: fails at step 1, nothing to undo
    Prescription("RX-2", "P1002", "metformin", 500, 42.00, "4 Lake Rd"),
    # no address: fails at the last step -> refund payment, release stock
    Prescription("RX-3", "P1003", "lisinopril", 60, 25.75, ""),
]


async def main() -> None:
    client = await Client.connect(ADDRESS, namespace=NAMESPACE)
    run = uuid.uuid4().hex[:6]
    handles = [
        await client.start_workflow(
            FulfillmentWorkflow.run, rx, id=f"rx-{rx.rx_id}-{run}", task_queue=TASK_QUEUE
        )
        for rx in SAMPLES
    ]
    print("Started:", ", ".join(h.id for h in handles))
    for h in handles:
        r = await h.result()
        print(f"\n{r.rx_id}: {r.status} {r.tracking}")
        for s in r.steps:
            print(f"  - {s}")


if __name__ == "__main__":
    asyncio.run(main())
