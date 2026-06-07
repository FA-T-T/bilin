from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any
from uuid import uuid4

from pydantic import ValidationError

from bilin_api import article_store
from bilin_api.database import open_db, utc_now
from bilin_api.schemas import (
    AgentActionPlan,
    AgentActionPlanEventKind,
    AgentActionPlanKind,
    AgentActionPlanStatus,
    Library,
    ReadingOutline,
    ResearchPaperMasteryOutline,
    ResearchPlanKind,
    ResearchPlanStatus,
    ResearchSkillPermission,
)


class ActionPlanError(ValueError):
    """Base error for action plan service failures."""


class ActionPlanNotFoundError(ActionPlanError):
    """Raised when an action plan cannot be found."""


class ActionPlanTransitionError(ActionPlanError):
    """Raised when an action plan status transition is not allowed."""


class ActionPlanPayloadHashMismatchError(ActionPlanError):
    """Raised when an approval precondition sees a different payload hash."""


async def create_agent_action_plan(
    library: Library,
    *,
    kind: AgentActionPlanKind,
    title: str,
    research_plan_id: str | None = None,
    article_revision_id: str | None = None,
    skill_id: str | None = None,
    skill_slug: str | None = None,
    job_id: str | None = None,
    status: AgentActionPlanStatus = AgentActionPlanStatus.pending,
    description: str = "",
    idempotency_key: str | None = None,
    payload_hash: str | None = None,
    required_permissions: list[ResearchSkillPermission | str] | None = None,
    payload: Mapping[str, Any] | None = None,
    preview: Mapping[str, Any] | None = None,
    result: Mapping[str, Any] | None = None,
    error: Mapping[str, Any] | None = None,
    steps: list[Mapping[str, Any]] | None = None,
) -> AgentActionPlan:
    return await article_store.create_agent_action_plan(
        library,
        kind=kind,
        title=title,
        research_plan_id=research_plan_id,
        article_revision_id=article_revision_id,
        skill_id=skill_id,
        skill_slug=skill_slug,
        job_id=job_id,
        status=status,
        description=description,
        idempotency_key=idempotency_key,
        payload_hash=payload_hash,
        required_permissions=required_permissions,
        payload=payload,
        preview=preview,
        result=result,
        error=error,
        steps=steps,
    )


async def list_agent_action_plans(
    library: Library,
    *,
    research_plan_id: str | None = None,
    article_revision_id: str | None = None,
    status: AgentActionPlanStatus | None = None,
    kind: AgentActionPlanKind | None = None,
) -> list[AgentActionPlan]:
    return await article_store.list_agent_action_plans(
        library,
        research_plan_id=research_plan_id,
        article_revision_id=article_revision_id,
        status=status,
        kind=kind,
    )


async def get_agent_action_plan(
    library: Library,
    action_plan_id: str,
) -> AgentActionPlan | None:
    return await article_store.get_agent_action_plan(library, action_plan_id)


async def approve_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    expected_payload_hash: str | None = None,
    message: str = "Action plan approved",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.approved,
        allowed_statuses={AgentActionPlanStatus.pending},
        message=message,
        expected_payload_hash=expected_payload_hash,
        event_payload=payload,
        approved_at=True,
    )


async def reject_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    message: str = "Action plan rejected",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.rejected,
        allowed_statuses={AgentActionPlanStatus.pending},
        message=message,
        event_payload=payload,
        finished_at=True,
    )


async def cancel_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    message: str = "Action plan cancelled",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.cancelled,
        allowed_statuses={
            AgentActionPlanStatus.pending,
            AgentActionPlanStatus.approved,
            AgentActionPlanStatus.queued,
            AgentActionPlanStatus.running,
        },
        message=message,
        event_payload=payload,
        finished_at=True,
    )


async def start_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    message: str = "Action plan started",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.running,
        allowed_statuses={AgentActionPlanStatus.approved, AgentActionPlanStatus.queued},
        message=message,
        event_payload=payload,
        started_at=True,
    )


async def succeed_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    result: Mapping[str, Any] | None = None,
    message: str = "Action plan succeeded",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.succeeded,
        allowed_statuses={AgentActionPlanStatus.running},
        message=message,
        event_payload=payload,
        result=result,
        clear_error=True,
        finished_at=True,
    )


def _coerce_text(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return value.strip()
    if isinstance(value, (int, float, bool)):
        return str(value)
    return str(value)


def _coerce_text_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [item.strip() for item in map(_coerce_text, value) if item.strip()]
    text = _coerce_text(value)
    if not text:
        return []
    return [line.strip() for line in text.splitlines() if line.strip()]


def _coerce_paper_identifier(candidate: Mapping[str, Any]) -> str:
    return (
        _coerce_text(candidate.get("id"))
        or _coerce_text(candidate.get("arxiv_id"))
        or _coerce_text(candidate.get("paper_id"))
        or "paper"
    )


def _coerce_paper_title(candidate: Mapping[str, Any]) -> str:
    metadata = candidate.get("metadata")
    if isinstance(metadata, Mapping):
        return _coerce_text(metadata.get("title")) or _coerce_text(candidate.get("title"))
    return _coerce_text(candidate.get("title"))


def _coerce_paper_mastery_outline(candidate: Mapping[str, Any]) -> ResearchPaperMasteryOutline:
    claim = _coerce_text_list(candidate.get("claim"))
    if not claim:
        claim = _coerce_text_list(candidate.get("summary"))
    if not claim:
        claim = _coerce_text_list(candidate.get("abstract"))
    return ResearchPaperMasteryOutline(
        paper_id=_coerce_paper_identifier(candidate),
        paper_title=_coerce_paper_title(candidate),
        claim=claim,
        method=_coerce_text_list(
            candidate.get("method") or candidate.get("methodology") or candidate.get("approach")
        ),
        equation=_coerce_text_list(candidate.get("equation") or candidate.get("equations")),
        evidence=_coerce_text_list(
            candidate.get("evidence") or candidate.get("data") or candidate.get("experiments")
        ),
        limitation=_coerce_text_list(candidate.get("limitation") or candidate.get("limitations")),
        follow_up=_coerce_text_list(
            candidate.get("follow_up") or candidate.get("followUp") or candidate.get("future_work")
        ),
    )


def _build_research_outline_from_candidates(
    *,
    title: str,
    topic: str | None,
    candidate_papers: list[Mapping[str, Any]],
) -> ReadingOutline:
    paper_outlines = [_coerce_paper_mastery_outline(candidate) for candidate in candidate_papers]
    sections = [
        {
            "title": outline.paper_title,
            "paper_id": outline.paper_id,
            "claims": outline.claim,
            "methods": outline.method,
            "equations": outline.equation,
            "evidences": outline.evidence,
            "limitations": outline.limitation,
            "follow_up": outline.follow_up,
        }
        for outline in paper_outlines
    ]
    source_refs = [
        outline.paper_id
        for outline in paper_outlines
        if isinstance(outline.paper_id, str) and outline.paper_id
    ]
    questions = [
        f"What should be verified in {outline.paper_title}?"
        for outline in paper_outlines
        if outline.paper_title
    ]
    summary_parts = [
        f"Generated outline for paper '{outline.paper_title or 'Untitled'}' "
        f"({outline.paper_id or 'unknown'})"
        for outline in paper_outlines
    ]

    return ReadingOutline(
        title=title,
        summary="; ".join(summary_parts),
        sections=sections,
        questions=questions,
        source_refs=source_refs,
        paper_mastery_outlines=paper_outlines,
        metadata={"topic": topic, "paper_count": len(paper_outlines)},
    )


def _reading_outline_from_generation_result(
    result: Mapping[str, Any] | None,
    *,
    title: str,
    topic: str | None,
) -> ReadingOutline | None:
    if not isinstance(result, Mapping):
        return None

    outline_payload = result.get("reading_outline") or result.get("readingOutline")
    if outline_payload is None and any(
        key in result
        for key in (
            "summary",
            "sections",
            "questions",
            "source_refs",
            "sourceRefs",
            "paper_mastery_outlines",
            "paperMasteryOutlines",
        )
    ):
        outline_payload = result
    if not isinstance(outline_payload, Mapping):
        return None

    normalized_payload = dict(outline_payload)
    if "sourceRefs" in normalized_payload and "source_refs" not in normalized_payload:
        normalized_payload["source_refs"] = normalized_payload["sourceRefs"]
    if (
        "paperMasteryOutlines" in normalized_payload
        and "paper_mastery_outlines" not in normalized_payload
    ):
        normalized_payload["paper_mastery_outlines"] = normalized_payload[
            "paperMasteryOutlines"
        ]

    try:
        outline = ReadingOutline.model_validate(normalized_payload)
    except ValidationError:
        return None

    updates: dict[str, Any] = {}
    if not outline.title:
        updates["title"] = title
    metadata = dict(outline.metadata)
    if topic is not None and "topic" not in metadata:
        metadata["topic"] = topic
    if metadata != outline.metadata:
        updates["metadata"] = metadata
    if not updates:
        return outline
    return outline.model_copy(update=updates)


async def _materialize_research_plan_from_generation_action(
    library: Library,
    action_plan: AgentActionPlan,
) -> None:
    payload = action_plan.payload if isinstance(action_plan.payload, Mapping) else {}
    candidate_papers = payload.get("candidate_papers")
    if not isinstance(candidate_papers, list):
        candidate_papers = []
    candidate_papers = [
        dict(item) if isinstance(item, Mapping) else {} for item in candidate_papers
    ]
    title = _coerce_text(payload.get("title")) or "Research Outline"
    topic = payload.get("topic") if isinstance(payload.get("topic"), str) else None
    try:
        kind = ResearchPlanKind(payload.get("kind", "paper_reading"))
    except ValueError:
        kind = ResearchPlanKind.paper_reading

    existing = await article_store.list_research_plans(
        library,
        article_revision_id=action_plan.article_revision_id,
        kind=kind,
    )
    if any(plan.payload.get("source_action_plan_id") == action_plan.id for plan in existing):
        return

    reading_outline = _reading_outline_from_generation_result(
        action_plan.result,
        title=title,
        topic=topic,
    ) or _build_research_outline_from_candidates(
        title=title,
        topic=topic,
        candidate_papers=candidate_papers,
    )
    plan_idempotency_key = payload.get("idempotency_key")
    if not isinstance(plan_idempotency_key, str):
        plan_idempotency_key = None

    await article_store.create_research_plan(
        library,
        title=title,
        kind=kind,
        status=ResearchPlanStatus.active,
        topic=topic,
        article_revision_id=action_plan.article_revision_id,
        skill_id=action_plan.skill_id,
        skill_slug=action_plan.skill_slug,
        idempotency_key=plan_idempotency_key,
        payload_hash=None,
        candidate_papers=candidate_papers,
        reading_outline=reading_outline,
        payload={
            **(payload.get("payload") if isinstance(payload.get("payload"), Mapping) else {}),
            "source_action_plan_id": action_plan.id,
            "skill_provenance": payload.get("skill_provenance"),
        },
        preview=payload.get("preview") if isinstance(payload.get("preview"), Mapping) else None,
        result=action_plan.result if isinstance(action_plan.result, Mapping) else None,
    )


async def fail_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    error: Mapping[str, Any] | None = None,
    message: str = "Action plan failed",
    payload: Mapping[str, Any] | None = None,
) -> AgentActionPlan:
    return await _transition_agent_action_plan(
        library,
        action_plan_id,
        target_status=AgentActionPlanStatus.failed,
        allowed_statuses={AgentActionPlanStatus.running},
        message=message,
        event_payload=payload,
        error=error,
        finished_at=True,
    )


async def _transition_agent_action_plan(
    library: Library,
    action_plan_id: str,
    *,
    target_status: AgentActionPlanStatus,
    allowed_statuses: set[AgentActionPlanStatus],
    message: str,
    expected_payload_hash: str | None = None,
    event_payload: Mapping[str, Any] | None = None,
    result: Mapping[str, Any] | None = None,
    error: Mapping[str, Any] | None = None,
    clear_error: bool = False,
    approved_at: bool = False,
    started_at: bool = False,
    finished_at: bool = False,
) -> AgentActionPlan:
    db_path = await article_store.ensure_library_database(library)
    now = utc_now()
    async with open_db(db_path) as conn:
        await conn.execute("BEGIN IMMEDIATE")
        try:
            cursor = await conn.execute(
                """
                SELECT id, status, payload_hash
                FROM agent_action_plans
                WHERE id = ?
                """,
                (action_plan_id,),
            )
            row = await cursor.fetchone()
            if row is None:
                raise ActionPlanNotFoundError(f"Action plan not found: {action_plan_id}")

            current_status = AgentActionPlanStatus(row["status"])
            if expected_payload_hash is not None and row["payload_hash"] != expected_payload_hash:
                raise ActionPlanPayloadHashMismatchError(
                    "Action plan payload hash did not match approval precondition"
                )
            if current_status not in allowed_statuses:
                allowed = ", ".join(sorted(status.value for status in allowed_statuses))
                raise ActionPlanTransitionError(
                    f"Cannot transition action plan {action_plan_id} "
                    f"from {current_status.value} to {target_status.value}; "
                    f"allowed from: {allowed}"
                )

            assignments = ["status = ?", "updated_at = ?"]
            params: list[Any] = [target_status.value, now]
            if result is not None:
                assignments.append("result_json = ?")
                params.append(json.dumps(dict(result)))
            if error is not None:
                assignments.append("error_json = ?")
                params.append(json.dumps(dict(error)))
            elif clear_error:
                assignments.append("error_json = NULL")
            if approved_at:
                assignments.append("approved_at = COALESCE(approved_at, ?)")
                params.append(now)
            if started_at:
                assignments.append("started_at = COALESCE(started_at, ?)")
                params.append(now)
            if finished_at:
                assignments.append("finished_at = COALESCE(finished_at, ?)")
                params.append(now)
            params.append(action_plan_id)

            await conn.execute(
                f"""
                UPDATE agent_action_plans
                SET {", ".join(assignments)}
                WHERE id = ?
                """,
                tuple(params),
            )
            transition_payload = {
                "from_status": current_status.value,
                "to_status": target_status.value,
            }
            transition_payload.update(dict(event_payload or {}))
            await conn.execute(
                """
                INSERT INTO agent_action_plan_events(
                  id, action_plan_id, kind, status, message, payload_json, created_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """,
                (
                    str(uuid4()),
                    action_plan_id,
                    AgentActionPlanEventKind.status_recorded.value,
                    target_status.value,
                    message,
                    json.dumps(transition_payload),
                    now,
                ),
            )
            await conn.commit()
        except Exception:
            await conn.rollback()
            raise

    action_plan = await article_store.get_agent_action_plan(library, action_plan_id)
    if action_plan is None:
        raise ActionPlanNotFoundError(f"Action plan not found: {action_plan_id}")
    if (
        target_status == AgentActionPlanStatus.succeeded
        and action_plan.kind == AgentActionPlanKind.generate_research_outline
    ):
        await _materialize_research_plan_from_generation_action(library, action_plan)
    return action_plan
