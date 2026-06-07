from __future__ import annotations

from pathlib import Path
from typing import Annotated

from fastapi import APIRouter, HTTPException, Query, status

from bilin_api.action_plan_service import (
    ActionPlanNotFoundError,
    ActionPlanPayloadHashMismatchError,
    ActionPlanTransitionError,
    approve_agent_action_plan,
    cancel_agent_action_plan,
    create_agent_action_plan,
    fail_agent_action_plan,
    get_agent_action_plan,
    list_agent_action_plans,
    reject_agent_action_plan,
    start_agent_action_plan,
    succeed_agent_action_plan,
)
from bilin_api.article_store import (
    create_research_plan,
    get_research_plan,
    list_research_plans,
)
from bilin_api.repositories import get_library, get_research_skill, list_research_skills
from bilin_api.research_skill_service import (
    ResearchSkillDigestMismatchError,
    ResearchSkillPermissionError,
    enable_research_skill,
    index_local_research_skills,
    resolve_research_plan_skill_provenance,
)
from bilin_api.schemas import (
    AgentActionPlan,
    AgentActionPlanCreate,
    AgentActionPlanKind,
    AgentActionPlanStatus,
    AgentActionPlanTransitionRequest,
    Library,
    ResearchPlan,
    ResearchPlanCreate,
    ResearchPlanGenerationRequest,
    ResearchPlanKind,
    ResearchPlanStatus,
    ResearchSkill,
    ResearchSkillEnableRequest,
    ResearchSkillIndexRequest,
)

router = APIRouter(tags=["research"])


@router.get("/research-skills", response_model=list[ResearchSkill])
async def get_research_skills() -> list[ResearchSkill]:
    return await list_research_skills()


@router.post("/research-skills/index-local", response_model=list[ResearchSkill])
async def post_index_local_research_skills(
    payload: ResearchSkillIndexRequest,
) -> list[ResearchSkill]:
    return await index_local_research_skills(
        project_root=_optional_path(payload.project_root),
        codex_skills_root=_optional_path(payload.codex_skills_root),
    )


@router.get("/research-skills/{skill_identifier}", response_model=ResearchSkill)
async def get_research_skill_by_identifier(skill_identifier: str) -> ResearchSkill:
    skill = await get_research_skill(skill_identifier)
    if skill is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Research skill not found",
        )
    return skill


@router.post("/research-skills/{skill_identifier}/enable", response_model=ResearchSkill)
async def post_enable_research_skill(
    skill_identifier: str,
    payload: ResearchSkillEnableRequest,
) -> ResearchSkill:
    try:
        skill = await enable_research_skill(
            skill_identifier,
            expected_digest=payload.expected_digest,
            granted_permissions=payload.granted_permissions,
        )
    except ResearchSkillDigestMismatchError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=str(exc),
        ) from exc
    except ResearchSkillPermissionError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        ) from exc
    if skill is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Research skill not found",
        )
    return skill


@router.get("/libraries/{library_id}/research-plans", response_model=list[ResearchPlan])
async def get_library_research_plans(
    library_id: str,
    article_revision_id: str | None = None,
    plan_status: Annotated[ResearchPlanStatus | None, Query(alias="status")] = None,
    kind: ResearchPlanKind | None = None,
) -> list[ResearchPlan]:
    library = await _library_or_404(library_id)
    return await list_research_plans(
        library,
        article_revision_id=article_revision_id,
        status=plan_status,
        kind=kind,
    )


@router.post(
    "/libraries/{library_id}/research-plans",
    response_model=ResearchPlan,
    status_code=status.HTTP_201_CREATED,
)
async def post_library_research_plan(
    library_id: str,
    payload: ResearchPlanCreate,
) -> ResearchPlan:
    library = await _library_or_404(library_id)
    return await create_research_plan(
        library,
        title=payload.title,
        kind=payload.kind,
        status=payload.status,
        topic=payload.topic,
        article_revision_id=payload.article_revision_id,
        skill_id=payload.skill_id,
        skill_slug=payload.skill_slug,
        job_id=payload.job_id,
        idempotency_key=payload.idempotency_key,
        payload_hash=payload.payload_hash,
        candidate_papers=payload.candidate_papers,
        reading_outline=payload.reading_outline,
        payload=payload.payload,
        preview=payload.preview,
        result=payload.result,
        error=payload.error,
    )


@router.post(
    "/libraries/{library_id}/research-plans/generate",
    response_model=AgentActionPlan,
    status_code=status.HTTP_201_CREATED,
)
async def post_generate_research_plan(
    library_id: str,
    payload: ResearchPlanGenerationRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    skill, provenance = await resolve_research_plan_skill_provenance(
        requested_slug=payload.skill_slug,
    )
    if skill is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Enable a paper-reading research skill before generating a research outline.",
        )

    action_payload = {
        "title": payload.title,
        "kind": payload.kind.value,
        "topic": payload.topic,
        "article_revision_id": payload.article_revision_id,
        "candidate_papers": payload.candidate_papers,
        "payload": payload.payload,
        "skill_provenance": (
            provenance.model_dump(mode="json") if provenance is not None else None
        ),
        "idempotency_key": payload.idempotency_key,
    }
    selected_skill_slug = skill.slug if skill is not None else None

    return await create_agent_action_plan(
        library,
        kind=AgentActionPlanKind.generate_research_outline,
        title=f"Generate reading outline: {payload.title}",
        article_revision_id=payload.article_revision_id,
        skill_id=skill.id if skill is not None else None,
        skill_slug=selected_skill_slug,
        description="Generate an auditable research plan outline from candidate papers.",
        idempotency_key=payload.idempotency_key,
        payload=action_payload,
        preview={
            "paper_count": len(payload.candidate_papers),
            "kind": payload.kind.value,
            "topic": payload.topic,
            "title": payload.title,
        },
    )


@router.get("/libraries/{library_id}/research-plans/{plan_id}", response_model=ResearchPlan)
async def get_library_research_plan(library_id: str, plan_id: str) -> ResearchPlan:
    library = await _library_or_404(library_id)
    plan = await get_research_plan(library, plan_id)
    if plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Research plan not found")
    return plan


@router.get("/libraries/{library_id}/agent-action-plans", response_model=list[AgentActionPlan])
async def get_library_agent_action_plans(
    library_id: str,
    research_plan_id: str | None = None,
    article_revision_id: str | None = None,
    action_status: Annotated[AgentActionPlanStatus | None, Query(alias="status")] = None,
    kind: AgentActionPlanKind | None = None,
) -> list[AgentActionPlan]:
    library = await _library_or_404(library_id)
    return await list_agent_action_plans(
        library,
        research_plan_id=research_plan_id,
        article_revision_id=article_revision_id,
        status=action_status,
        kind=kind,
    )


@router.post(
    "/libraries/{library_id}/agent-action-plans",
    response_model=AgentActionPlan,
    status_code=status.HTTP_201_CREATED,
)
async def post_library_agent_action_plan(
    library_id: str,
    payload: AgentActionPlanCreate,
) -> AgentActionPlan:
    if payload.status != AgentActionPlanStatus.pending:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Agent action plans created through the API must start as pending.",
        )
    library = await _library_or_404(library_id)
    return await create_agent_action_plan(
        library,
        kind=payload.kind,
        title=payload.title,
        research_plan_id=payload.research_plan_id,
        article_revision_id=payload.article_revision_id,
        skill_id=payload.skill_id,
        skill_slug=payload.skill_slug,
        job_id=payload.job_id,
        status=payload.status,
        description=payload.description,
        idempotency_key=payload.idempotency_key,
        payload_hash=payload.payload_hash,
        required_permissions=payload.required_permissions,
        payload=payload.payload,
        preview=payload.preview,
        result=payload.result,
        error=payload.error,
        steps=[step.model_dump(mode="json") for step in payload.steps],
    )


@router.get(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}",
    response_model=AgentActionPlan,
)
async def get_library_agent_action_plan(
    library_id: str,
    action_plan_id: str,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    action_plan = await get_agent_action_plan(library, action_plan_id)
    if action_plan is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Action plan not found")
    return action_plan


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/approve",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_approve(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await approve_agent_action_plan(
            library,
            action_plan_id,
            expected_payload_hash=payload.expected_payload_hash,
            message=payload.message or "Action plan approved",
            payload=payload.payload,
        )
    except ActionPlanPayloadHashMismatchError as exc:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc)) from exc
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/reject",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_reject(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await reject_agent_action_plan(
            library,
            action_plan_id,
            message=payload.message or "Action plan rejected",
            payload=payload.payload,
        )
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/cancel",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_cancel(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await cancel_agent_action_plan(
            library,
            action_plan_id,
            message=payload.message or "Action plan cancelled",
            payload=payload.payload,
        )
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/start",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_start(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await start_agent_action_plan(
            library,
            action_plan_id,
            message=payload.message or "Action plan started",
            payload=payload.payload,
        )
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/succeed",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_succeed(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await succeed_agent_action_plan(
            library,
            action_plan_id,
            result=payload.result,
            message=payload.message or "Action plan succeeded",
            payload=payload.payload,
        )
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


@router.post(
    "/libraries/{library_id}/agent-action-plans/{action_plan_id}/fail",
    response_model=AgentActionPlan,
)
async def post_agent_action_plan_fail(
    library_id: str,
    action_plan_id: str,
    payload: AgentActionPlanTransitionRequest,
) -> AgentActionPlan:
    library = await _library_or_404(library_id)
    try:
        return await fail_agent_action_plan(
            library,
            action_plan_id,
            error=payload.error,
            message=payload.message or "Action plan failed",
            payload=payload.payload,
        )
    except (ActionPlanNotFoundError, ActionPlanTransitionError) as exc:
        raise _action_plan_http_error(exc) from exc


def _optional_path(value: str | None) -> Path | None:
    return Path(value).expanduser().resolve() if value else None


async def _library_or_404(library_id: str) -> Library:
    library = await get_library(library_id)
    if library is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Library not found")
    return library


def _action_plan_http_error(exc: Exception) -> HTTPException:
    if isinstance(exc, ActionPlanNotFoundError):
        return HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc))
    return HTTPException(status_code=status.HTTP_409_CONFLICT, detail=str(exc))
