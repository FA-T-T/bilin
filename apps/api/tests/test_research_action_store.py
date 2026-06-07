from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import pytest

from bilin_api.action_plan_service import (
    ActionPlanPayloadHashMismatchError,
    ActionPlanTransitionError,
    approve_agent_action_plan,
    cancel_agent_action_plan,
    create_agent_action_plan,
    fail_agent_action_plan,
    get_agent_action_plan,
    reject_agent_action_plan,
    start_agent_action_plan,
    succeed_agent_action_plan,
)
from bilin_api.article_store import (
    bundle_path_for_arxiv,
    list_research_plans,
    upsert_arxiv_revision,
)
from bilin_api.repositories import upsert_research_skill
from bilin_api.schemas import (
    AgentActionPlanKind,
    AgentActionPlanStatus,
    Library,
    LibraryStatus,
    ResearchPlanKind,
    ResearchSkillInstallStatus,
    ResearchSkillPermission,
    ResearchSkillStatus,
    ResearchSkillUpsert,
)


@pytest.mark.asyncio
async def test_action_plan_service_valid_transitions_append_events(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.write_obsidian,
        title="Write an Obsidian preview",
        idempotency_key="valid-transition-key",
        required_permissions=[ResearchSkillPermission.write_obsidian],
        payload={"target_note": "Papers/Bilinear.md"},
        preview={"patch": "## Claim\nText"},
    )

    approved = await approve_agent_action_plan(
        library,
        action.id,
        expected_payload_hash=action.payload_hash,
        payload={"reviewer": "test"},
    )
    running = await start_agent_action_plan(library, action.id)
    succeeded = await succeed_agent_action_plan(
        library,
        action.id,
        result={"path": "Papers/Bilinear.md"},
    )

    assert approved.status == AgentActionPlanStatus.approved
    assert running.status == AgentActionPlanStatus.running
    assert succeeded.status == AgentActionPlanStatus.succeeded
    assert succeeded.approved_at is not None
    assert succeeded.started_at is not None
    assert succeeded.finished_at is not None
    assert succeeded.payload == {"target_note": "Papers/Bilinear.md"}
    assert succeeded.result == {"path": "Papers/Bilinear.md"}
    assert [event.status for event in succeeded.events] == [
        AgentActionPlanStatus.pending,
        AgentActionPlanStatus.approved,
        AgentActionPlanStatus.running,
        AgentActionPlanStatus.succeeded,
    ]
    assert succeeded.events[-1].payload == {
        "from_status": "running",
        "to_status": "succeeded",
    }


@pytest.mark.asyncio
async def test_action_plan_service_reject_cancel_and_fail_transitions(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    rejected_action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.export_article,
        title="Reject export",
        payload={"format": "markdown"},
    )
    cancelled_action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.run_external_tool,
        title="Cancel tool run",
        payload={"tool": "latexml"},
    )
    failed_action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.provider_call,
        title="Fail provider call",
        payload={"provider": "local"},
    )

    rejected = await reject_agent_action_plan(library, rejected_action.id)
    approved_for_cancel = await approve_agent_action_plan(library, cancelled_action.id)
    cancelled = await cancel_agent_action_plan(library, approved_for_cancel.id)
    approved_for_failure = await approve_agent_action_plan(library, failed_action.id)
    running = await start_agent_action_plan(library, approved_for_failure.id)
    failed = await fail_agent_action_plan(
        library,
        running.id,
        error={"code": "provider_timeout"},
    )

    assert rejected.status == AgentActionPlanStatus.rejected
    assert rejected.finished_at is not None
    assert cancelled.status == AgentActionPlanStatus.cancelled
    assert cancelled.finished_at is not None
    assert failed.status == AgentActionPlanStatus.failed
    assert failed.finished_at is not None
    assert failed.error == {"code": "provider_timeout"}
    assert failed.events[-1].status == AgentActionPlanStatus.failed


@pytest.mark.asyncio
async def test_action_plan_service_rejects_invalid_transitions(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    rejected_action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.export_article,
        title="Rejected action",
        payload={"format": "markdown"},
    )
    succeeded_action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.write_obsidian,
        title="Succeeded action",
        payload={"target_note": "Papers/Bilinear.md"},
    )

    await reject_agent_action_plan(library, rejected_action.id)
    await approve_agent_action_plan(library, succeeded_action.id)
    await start_agent_action_plan(library, succeeded_action.id)
    await succeed_agent_action_plan(library, succeeded_action.id)

    with pytest.raises(ActionPlanTransitionError):
        await start_agent_action_plan(library, rejected_action.id)
    with pytest.raises(ActionPlanTransitionError):
        await reject_agent_action_plan(library, succeeded_action.id)

    still_rejected = await get_agent_action_plan(library, rejected_action.id)
    still_succeeded = await get_agent_action_plan(library, succeeded_action.id)
    assert still_rejected is not None
    assert still_rejected.status == AgentActionPlanStatus.rejected
    assert still_succeeded is not None
    assert still_succeeded.status == AgentActionPlanStatus.succeeded


@pytest.mark.asyncio
async def test_approve_agent_action_plan_rejects_payload_hash_mismatch(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.write_obsidian,
        title="Hash guarded action",
        payload={"target_note": "Papers/Bilinear.md"},
    )

    with pytest.raises(ActionPlanPayloadHashMismatchError):
        await approve_agent_action_plan(
            library,
            action.id,
            expected_payload_hash="not-the-stored-hash",
        )

    stored = await get_agent_action_plan(library, action.id)
    assert stored is not None
    assert stored.status == AgentActionPlanStatus.pending
    assert [event.message for event in stored.events] == ["Action plan created"]


@pytest.mark.asyncio
async def test_action_plan_payload_is_immutable_after_approval(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    payload = {"target_note": "Papers/Bilinear.md", "anchor": "p-1"}
    action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.write_obsidian,
        title="Immutable payload action",
        payload=payload,
    )

    await approve_agent_action_plan(library, action.id)
    await start_agent_action_plan(
        library,
        action.id,
        payload={"target_note": "Mutated.md"},
    )
    await succeed_agent_action_plan(
        library,
        action.id,
        result={"target_note": "Mutated.md"},
        payload={"target_note": "AlsoMutated.md"},
    )

    stored = await get_agent_action_plan(library, action.id)
    assert stored is not None
    assert stored.payload == payload
    assert stored.payload_hash == action.payload_hash
    assert stored.events[-2].payload["target_note"] == "Mutated.md"
    assert stored.events[-1].payload["target_note"] == "AlsoMutated.md"


@pytest.mark.asyncio
async def test_action_plan_service_preserves_idempotent_create(tmp_path: Path) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    created = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.write_obsidian,
        title="Original action",
        idempotency_key="idempotent-service-key",
        payload={"target_note": "Papers/Bilinear.md"},
    )
    duplicate = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.export_article,
        title="Mutated action",
        idempotency_key="idempotent-service-key",
        payload={"format": "markdown"},
    )

    assert duplicate.id == created.id
    assert duplicate.title == "Original action"
    assert duplicate.kind == AgentActionPlanKind.write_obsidian
    assert duplicate.payload == {"target_note": "Papers/Bilinear.md"}


@pytest.mark.asyncio
async def test_generate_research_outline_action_materializes_research_plan_after_success(
    tmp_path: Path,
) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    skill = await upsert_research_skill(
        ResearchSkillUpsert(
            id="skill-paper-outline",
            slug="paper-outline",
            title="Paper Outline",
            description="Build per-paper mastery outlines.",
            source_path="/tmp/paper-outline/SKILL.md",
            digest="sha256:paper-outline",
            install_status=ResearchSkillInstallStatus.discovered,
            status=ResearchSkillStatus.disabled,
            supported_tasks=["paper_reading"],
            enabled=False,
            declared_permissions=[ResearchSkillPermission.provider_call],
            granted_permissions=[],
            input_shape={},
            output_shape={},
            metadata={},
        )
    )

    action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.generate_research_outline,
        title="Generate plan for candidate papers",
        skill_id=skill.id,
        skill_slug=skill.slug,
        payload={
            "title": "Generate plan for candidate papers",
            "kind": "paper_reading",
            "topic": "adaptive optimization",
            "candidate_papers": [
                {
                    "id": "2401.00001",
                    "title": "A sample paper",
                    "claim": ["The method converges."],
                    "method": ["Constructive proof"],
                    "equation": ["x >= y"],
                    "evidence": ["benchmark A"],
                    "limitation": ["single dataset"],
                    "follow_up": ["test on larger baselines"],
                }
            ],
            "payload": {"seed": "2401.00001"},
            "skill_provenance": {
                "skill_slug": skill.slug,
                "source": skill.source_path,
                "version": skill.version,
                "digest": skill.digest,
            },
        },
    )

    assert (
        await list_research_plans(
            library,
            article_revision_id=revision_id,
            kind=ResearchPlanKind.paper_reading,
        )
        == []
    )

    await approve_agent_action_plan(
        library,
        action.id,
        expected_payload_hash=action.payload_hash,
    )
    assert (
        await list_research_plans(
            library,
            article_revision_id=revision_id,
            kind=ResearchPlanKind.paper_reading,
        )
        == []
    )

    await start_agent_action_plan(library, action.id)
    succeeded = await succeed_agent_action_plan(
        library,
        action.id,
        result={"status": "done"},
    )

    plans = await list_research_plans(
        library,
        article_revision_id=revision_id,
        kind=ResearchPlanKind.paper_reading,
    )
    assert succeeded.status == AgentActionPlanStatus.succeeded
    assert len(plans) == 1
    assert plans[0].reading_outline is not None
    mastery = plans[0].reading_outline.paper_mastery_outlines
    assert len(mastery) == 1
    assert mastery[0].claim == ["The method converges."]
    assert mastery[0].follow_up == ["test on larger baselines"]
    assert plans[0].payload["source_action_plan_id"] == action.id
    provenance = plans[0].payload["skill_provenance"]
    assert provenance["skill_slug"] == "paper-outline"
    assert provenance["digest"] == skill.digest


@pytest.mark.asyncio
async def test_generate_research_outline_materializes_agent_result_outline(
    tmp_path: Path,
) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    action = await create_agent_action_plan(
        library,
        article_revision_id=revision_id,
        kind=AgentActionPlanKind.generate_research_outline,
        title="Generate result-backed outline",
        payload={
            "title": "Fallback title",
            "kind": "paper_reading",
            "topic": "adaptive optimization",
            "candidate_papers": [
                {
                    "id": "2401.00001",
                    "title": "Fallback paper",
                    "claim": ["Fallback claim"],
                }
            ],
        },
    )

    await approve_agent_action_plan(
        library,
        action.id,
        expected_payload_hash=action.payload_hash,
    )
    await start_agent_action_plan(library, action.id)
    await succeed_agent_action_plan(
        library,
        action.id,
        result={
            "reading_outline": {
                "title": "Agent generated outline",
                "summary": "Read this paper through the convergence argument.",
                "sourceRefs": ["2401.00001"],
                "paperMasteryOutlines": [
                    {
                        "paper_id": "2401.00001",
                        "paper_title": "Agent selected paper",
                        "claim": ["Agent claim"],
                        "method": ["Agent method"],
                        "followUp": ["Agent next step"],
                    }
                ],
                "metadata": {"generated_by": "paper-outline"},
            },
        },
    )

    plans = await list_research_plans(
        library,
        article_revision_id=revision_id,
        kind=ResearchPlanKind.paper_reading,
    )
    assert len(plans) == 1
    assert plans[0].result is not None
    assert plans[0].reading_outline is not None
    assert plans[0].reading_outline.title == "Agent generated outline"
    assert plans[0].reading_outline.source_refs == ["2401.00001"]
    assert plans[0].reading_outline.metadata == {
        "generated_by": "paper-outline",
        "topic": "adaptive optimization",
    }
    mastery = plans[0].reading_outline.paper_mastery_outlines
    assert len(mastery) == 1
    assert mastery[0].paper_title == "Agent selected paper"
    assert mastery[0].claim == ["Agent claim"]
    assert mastery[0].follow_up == ["Agent next step"]


async def _library_with_revision(tmp_path: Path) -> tuple[Library, str]:
    now = datetime.now(UTC)
    library = Library(
        id="library-id",
        name="Research",
        path=str(tmp_path / "library"),
        status=LibraryStatus.active,
        metadata={},
        created_at=now,
        updated_at=now,
    )
    _, revision = await upsert_arxiv_revision(
        library,
        "2401.00001",
        "v1",
        "A storage paper",
        bundle_path_for_arxiv(library, "2401.00001", "v1"),
        {"fixture": True},
    )
    return library, revision.id
