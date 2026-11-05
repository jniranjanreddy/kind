"""Start an appointment, watch its status, then confirm (or cancel) it.

    python3 starter.py            # confirm after a few seconds
    python3 starter.py cancel     # cancel instead
    python3 starter.py none       # do nothing -> expires after the timeout
"""
import asyncio
import os
import sys
import uuid

from temporalio.client import Client

from workflows import AppointmentRequest, AppointmentWorkflow

ADDRESS = os.getenv("TEMPORAL_ADDRESS", "localhost:7233")
NAMESPACE = os.getenv("TEMPORAL_NAMESPACE", "default")
TASK_QUEUE = os.getenv("TASK_QUEUE", "appointment-scheduler")


async def main() -> None:
    action = sys.argv[1] if len(sys.argv) > 1 else "confirm"
    client = await Client.connect(ADDRESS, namespace=NAMESPACE)

    req = AppointmentRequest(
        patient_id="P1001",
        doctor="Rao",
        slot="2026-11-10 09:30",
        confirm_timeout_seconds=60 if action == "none" else 120,
        reminder_delay_seconds=10,
    )
    handle = await client.start_workflow(
        AppointmentWorkflow.run,
        req,
        id=f"appointment-{req.patient_id}-{uuid.uuid4().hex[:6]}",
        task_queue=TASK_QUEUE,
    )
    print(f"Started {handle.id}")

    await asyncio.sleep(3)
    print("status:", await handle.query(AppointmentWorkflow.status))

    if action == "confirm":
        await handle.signal(AppointmentWorkflow.confirm)
        print("sent signal: confirm")
    elif action == "cancel":
        await handle.signal(AppointmentWorkflow.cancel)
        print("sent signal: cancel")
    else:
        print("no signal sent, waiting for the confirmation timeout")

    print("result:", await handle.result())


if __name__ == "__main__":
    asyncio.run(main())
