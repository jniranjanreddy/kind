import asyncio
from temporalio.client import Client
from temporalio.worker import Worker

from workflows import HelloWorkflow


async def main():
    client = await Client.connect("temporal-frontend:7233")    

    worker = Worker(
        client,
        task_queue="hello-task-queue",
        workflows=[HelloWorkflow],
    )

    print("Worker started...")
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
