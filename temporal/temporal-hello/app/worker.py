import asyncio
import os

from temporalio.client import Client
from temporalio.worker import Worker

from workflows import HelloWorkflow, say_hello

ADDRESS = os.getenv("TEMPORAL_ADDRESS", "localhost:7233")
NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "patient-services")


async def main() -> None:
    # Plaintext gRPC: the kind cluster's frontend has TLS disabled.
    client = await Client.connect(ADDRESS, namespace=NAMESPACE)
    worker = Worker(
        client,
        task_queue=TASK_QUEUE,
        workflows=[HelloWorkflow],
        activities=[say_hello],
    )
    print(f"Worker listening on {ADDRESS}, task queue '{TASK_QUEUE}'.", flush=True)
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
