from temporalio.client import Client
from temporalio.worker import Worker
from temporalio import workflow, activity
import asyncio

# -------- Activity --------
@activity.defn
async def say_hello(name: str) -> str:
    return f"Hello {name}!"

# -------- Workflow --------
@workflow.defn
class HelloWorkflow:
    @workflow.run
    async def run(self, name: str) -> str:
        return await workflow.execute_activity(
            say_hello,
            name,
            schedule_to_close_timeout=10
        )

# -------- Worker --------
async def main():
    client = await Client.connect("temporal-frontend.temporal.svc.cluster.local:7233", namespace="temporal")

    worker = Worker(
        client,
        task_queue="hello-task-queue",
        workflows=[HelloWorkflow],
        activities=[say_hello],
    )

    await worker.run()

if __name__ == "__main__":
    asyncio.run(main())
