import asyncio
import logging
import os
import signal
from datetime import timedelta

from temporalio.client import Client
from temporalio.worker import Worker

from workflows import (
    ClaimWorkflow,
    check_eligibility,
    fraud_score,
    issue_payment,
    price_claim,
    validate_claim,
)

ADDRESS = os.getenv("TEMPORAL_ADDRESS", "localhost:7233")
NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "claims-processor")


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    # Plaintext gRPC: the kind cluster's frontend has TLS disabled.
    client = await Client.connect(ADDRESS, namespace=NAMESPACE)
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[ClaimWorkflow],
        activities=[validate_claim, check_eligibility, fraud_score, price_claim, issue_payment],
        # on shutdown, give running activities this long to finish
        graceful_shutdown_timeout=timedelta(seconds=20),
    )
    # Kubernetes stops pods with SIGTERM. Python as PID 1 ignores it by default,
    # so handle it: stop polling, let running activities finish, then exit.
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        asyncio.get_running_loop().add_signal_handler(sig, stop.set)

    async with worker:
        print(f"Worker listening on {ADDRESS}, task queue '{TASK_QUEUE}'.", flush=True)
        await stop.wait()
        print("SIGTERM received, shutting down gracefully...", flush=True)
    print("Worker stopped.", flush=True)


if __name__ == "__main__":
    asyncio.run(main())
