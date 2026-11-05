"""Appointment scheduling: a long-running workflow that waits for a human.

Shows: signals (confirm / cancel), a query (status), waiting with a timeout,
and a durable timer (the reminder). The workflow can wait minutes or days;
it survives worker restarts because Temporal stores its history.
"""
import asyncio
from dataclasses import dataclass
from datetime import timedelta
from typing import Optional

from temporalio import activity, workflow


@dataclass
class AppointmentRequest:
    patient_id: str
    doctor: str
    slot: str                          # e.g. "2026-11-10 09:30"
    confirm_timeout_seconds: int = 120  # how long the patient has to confirm
    reminder_delay_seconds: int = 30    # demo value; in real life "24h before the slot"


# --- Activities: the side effects (calendar, SMS/email). Plain async functions. ---

@activity.defn
async def reserve_slot(req: AppointmentRequest) -> str:
    appointment_id = f"APT-{req.patient_id}-{req.slot.replace(' ', 'T').replace(':', '')}"
    activity.logger.info("Reserved %s with Dr. %s", appointment_id, req.doctor)
    return appointment_id


@activity.defn
async def release_slot(appointment_id: str) -> None:
    activity.logger.info("Released %s", appointment_id)


@activity.defn
async def send_notification(message: str) -> None:
    # Stand-in for an SMS/email provider.
    activity.logger.info("NOTIFY: %s", message)


# --- Workflow: the durable orchestration. Must be deterministic. ---

@workflow.defn
class AppointmentWorkflow:
    def __init__(self) -> None:
        self._status = "requested"
        self._decision: Optional[str] = None  # "confirmed" | "cancelled"
        self._appointment_id = ""

    @workflow.run
    async def run(self, req: AppointmentRequest) -> str:
        opts = {"start_to_close_timeout": timedelta(seconds=10)}

        self._appointment_id = await workflow.execute_activity(reserve_slot, req, **opts)
        self._status = "awaiting_confirmation"
        await workflow.execute_activity(
            send_notification,
            f"Patient {req.patient_id}: please confirm {self._appointment_id} "
            f"with Dr. {req.doctor} at {req.slot}",
            **opts,
        )

        # Wait for a confirm/cancel signal, but not forever.
        try:
            await workflow.wait_condition(
                lambda: self._decision is not None,
                timeout=timedelta(seconds=req.confirm_timeout_seconds),
            )
        except asyncio.TimeoutError:
            self._decision = "expired"

        if self._decision != "confirmed":
            await workflow.execute_activity(release_slot, self._appointment_id, **opts)
            self._status = self._decision
            return f"{self._appointment_id}: {self._decision}, slot released"

        self._status = "confirmed"
        # Durable timer: no worker needs to stay up while this runs down.
        await asyncio.sleep(req.reminder_delay_seconds)
        await workflow.execute_activity(
            send_notification,
            f"Reminder: {self._appointment_id} with Dr. {req.doctor} at {req.slot}",
            **opts,
        )
        self._status = "reminder_sent"
        return f"{self._appointment_id}: confirmed, reminder sent"

    @workflow.signal
    def confirm(self) -> None:
        if self._decision is None:
            self._decision = "confirmed"

    @workflow.signal
    def cancel(self) -> None:
        if self._decision is None:
            self._decision = "cancelled"

    @workflow.query
    def status(self) -> str:
        return self._status
