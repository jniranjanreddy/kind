"""Insurance claim processing: a pipeline that has to cope with failures.

Shows: automatic retries with a RetryPolicy (a flaky eligibility service),
non-retryable errors (invalid input fails fast, no retries), activities run in
parallel (fraud check + pricing), and business branching on the results.
"""
import asyncio
from dataclasses import dataclass
from datetime import timedelta

from temporalio import activity, workflow
from temporalio.common import RetryPolicy
from temporalio.exceptions import ActivityError, ApplicationError


@dataclass
class Claim:
    claim_id: str
    patient_id: str
    procedure_code: str
    amount: float


@dataclass
class ClaimResult:
    claim_id: str
    status: str          # approved | rejected | manual_review
    payout: float
    detail: str


# --- Activities ---

@activity.defn
async def validate_claim(claim: Claim) -> None:
    if claim.amount <= 0 or not claim.procedure_code:
        # Bad input won't get better by retrying: fail immediately.
        raise ApplicationError(
            f"invalid claim {claim.claim_id}: amount={claim.amount}, "
            f"procedure='{claim.procedure_code}'",
            non_retryable=True,
        )


@activity.defn
async def check_eligibility(claim: Claim) -> bool:
    # Simulated flaky downstream service: the first 2 attempts fail.
    # Temporal retries it per the RetryPolicy; the workflow code never sees it.
    attempt = activity.info().attempt
    if attempt < 3:
        raise RuntimeError(f"eligibility service unavailable (attempt {attempt})")
    activity.logger.info("Eligibility OK on attempt %d", attempt)
    return not claim.patient_id.startswith("X")  # "X..." = no active policy


@activity.defn
async def fraud_score(claim: Claim) -> float:
    await asyncio.sleep(1)  # pretend to call a scoring model
    return min(claim.amount / 50_000, 1.0)


@activity.defn
async def price_claim(claim: Claim) -> float:
    await asyncio.sleep(1)  # pretend to look up the fee schedule
    return round(claim.amount * 0.8, 2)  # plan covers 80%


@activity.defn
async def issue_payment(claim_id: str, amount: float) -> str:
    activity.logger.info("Paid %.2f for %s", amount, claim_id)
    return f"PAY-{claim_id}"


# --- Workflow ---

@workflow.defn
class ClaimWorkflow:
    @workflow.run
    async def run(self, claim: Claim) -> ClaimResult:
        quick = {"start_to_close_timeout": timedelta(seconds=10)}

        try:
            await workflow.execute_activity(validate_claim, claim, **quick)
        except ActivityError as err:
            return ClaimResult(claim.claim_id, "rejected", 0.0, str(err.cause))

        eligible = await workflow.execute_activity(
            check_eligibility,
            claim,
            start_to_close_timeout=timedelta(seconds=10),
            retry_policy=RetryPolicy(
                initial_interval=timedelta(seconds=1),
                backoff_coefficient=2.0,
                maximum_attempts=5,
            ),
        )
        if not eligible:
            return ClaimResult(claim.claim_id, "rejected", 0.0, "no active coverage")

        # Fan out: both run at the same time, possibly on different worker pods.
        score, covered = await asyncio.gather(
            workflow.execute_activity(fraud_score, claim, **quick),
            workflow.execute_activity(price_claim, claim, **quick),
        )
        if score > 0.8:
            return ClaimResult(
                claim.claim_id, "manual_review", 0.0, f"fraud score {score:.2f}"
            )

        payment_id = await workflow.execute_activity(
            issue_payment, args=[claim.claim_id, covered], **quick
        )
        return ClaimResult(claim.claim_id, "approved", covered, payment_id)
