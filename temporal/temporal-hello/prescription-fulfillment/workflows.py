"""Prescription fulfillment: a saga with compensation.

Steps: reserve stock -> charge payment -> pack (long-running, heartbeats) -> ship.
If a later step fails, the steps that already succeeded are undone in reverse
order (refund payment, release stock). Temporal guarantees the compensations run
even if the worker crashes halfway, because the workflow's progress is durable.

Shows: saga / compensation, activity heartbeats + heartbeat timeout (detects a
stuck or dead worker quickly), and limited retries for steps that may fail for good.
"""
import asyncio
from dataclasses import dataclass
from datetime import timedelta

from temporalio import activity, workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError, ApplicationError


@dataclass
class Prescription:
    rx_id: str
    patient_id: str
    drug: str
    quantity: int
    price: float
    address: str


@dataclass
class FulfillmentResult:
    rx_id: str
    status: str            # shipped | failed_compensated
    tracking: str
    steps: list[str]       # what ran, in order, including compensations


# --- Activities ---

@activity.defn
async def reserve_stock(rx: Prescription) -> str:
    if rx.quantity > 90:
        raise ApplicationError(f"not enough {rx.drug} in stock for {rx.quantity}", non_retryable=True)
    return f"RES-{rx.rx_id}"


@activity.defn
async def release_stock(reservation_id: str) -> None:
    activity.logger.info("Released %s", reservation_id)


@activity.defn
async def charge_payment(rx: Prescription) -> str:
    activity.logger.info("Charged %.2f to %s", rx.price, rx.patient_id)
    return f"CHG-{rx.rx_id}"


@activity.defn
async def refund_payment(charge_id: str) -> None:
    activity.logger.info("Refunded %s", charge_id)


@activity.defn
async def pack_order(rx: Prescription) -> str:
    # Long-running step. Heartbeats tell Temporal "still alive, at step N".
    # If they stop (pod killed), Temporal retries on another worker after the
    # heartbeat timeout instead of waiting for the full start-to-close timeout,
    # and the retry can resume from the last heartbeat details.
    start = activity.info().heartbeat_details[0] if activity.info().heartbeat_details else 0
    for step in range(start, 5):
        await asyncio.sleep(1)
        activity.heartbeat(step + 1)
    return f"BOX-{rx.rx_id}"


@activity.defn
async def ship_order(rx: Prescription) -> str:
    if not rx.address.strip():
        raise ApplicationError("no delivery address", non_retryable=True)
    return f"TRK-{rx.rx_id}"


# --- Workflow ---

@workflow.defn
class FulfillmentWorkflow:
    @workflow.run
    async def run(self, rx: Prescription) -> FulfillmentResult:
        quick = {
            "start_to_close_timeout": timedelta(seconds=10),
            "retry_policy": RetryPolicy(maximum_attempts=3),
        }
        steps: list[str] = []
        compensations = []  # (label, activity, arg) to run in reverse on failure

        try:
            reservation = await workflow.execute_activity(reserve_stock, rx, **quick)
            steps.append(f"reserved {reservation}")
            compensations.append(("released stock", release_stock, reservation))

            charge = await workflow.execute_activity(charge_payment, rx, **quick)
            steps.append(f"charged {charge}")
            compensations.append(("refunded payment", refund_payment, charge))

            box = await workflow.execute_activity(
                pack_order,
                rx,
                start_to_close_timeout=timedelta(minutes=2),
                heartbeat_timeout=timedelta(seconds=3),
            )
            steps.append(f"packed {box}")

            tracking = await workflow.execute_activity(ship_order, rx, **quick)
            steps.append(f"shipped {tracking}")
            return FulfillmentResult(rx.rx_id, "shipped", tracking, steps)

        except ActivityError as err:
            steps.append(f"FAILED: {err.cause}")
            for label, compensate, arg in reversed(compensations):
                await workflow.execute_activity(
                    compensate,
                    arg,
                    start_to_close_timeout=timedelta(seconds=10),
                    retry_policy=RetryPolicy(maximum_attempts=0),  # 0 = retry until it succeeds
                )
                steps.append(label)
            return FulfillmentResult(rx.rx_id, "failed_compensated", "", steps)
