"""Submit four sample claims at once, one per outcome, and print the results.

    python3 starter.py
"""
import asyncio
import os
import uuid

from temporalio.client import Client

from workflows import Claim, ClaimWorkflow

ADDRESS = os.getenv("TEMPORAL_ADDRESS", "localhost:7233")
NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "claims-processor")

SAMPLES = [
    Claim("C-100", "P1001", "99213", 1_200.00),   # approved (after 2 eligibility retries)
    Claim("C-200", "P1002", "", 300.00),          # rejected: invalid, no retries
    Claim("C-300", "X9999", "99214", 800.00),     # rejected: no coverage
    Claim("C-400", "P1003", "27447", 48_000.00),  # manual_review: high fraud score
]


async def main() -> None:
    client = await Client.connect(ADDRESS, namespace=NAMESPACE)
    run = uuid.uuid4().hex[:6]
    handles = [
        await client.start_workflow(
            ClaimWorkflow.run, c, id=f"claim-{c.claim_id}-{run}", task_queue=TASK_QUEUE
        )
        for c in SAMPLES
    ]
    print("Started:", ", ".join(h.id for h in handles))
    for h in handles:
        r = await h.result()
        print(f"{r.claim_id}: {r.status:<13} payout={r.payout:>9.2f}  {r.detail}")


if __name__ == "__main__":
    asyncio.run(main())
