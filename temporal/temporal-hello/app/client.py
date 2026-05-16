import asyncio
from temporalio.client import Client

from workflows import HelloWorkflow


async def main():
    client = await Client.connect("temporal-frontend:7233")

    result = await client.execute_workflow(
        HelloWorkflow.run,
        "Niranjan",
        id="hello-workflow-id",
        task_queue="hello-task-queue",
    )

    print(f"Result: {result}")


if __name__ == "__main__":
    asyncio.run(main())
