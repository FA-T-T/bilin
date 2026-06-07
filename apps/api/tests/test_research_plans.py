from __future__ import annotations

from datetime import UTC, datetime
from pathlib import Path

import aiosqlite
import pytest

from bilin_api.article_store import (
    append_agent_action_plan_event,
    bundle_path_for_arxiv,
    create_agent_action_plan,
    create_research_plan,
    get_agent_action_plan,
    get_research_plan,
    list_agent_action_plans,
    list_research_plans,
    upsert_arxiv_revision,
)
from bilin_api.database import init_library_db
from bilin_api.schemas import (
    AgentActionPlan,
    AgentActionPlanEvent,
    AgentActionPlanEventKind,
    AgentActionPlanKind,
    AgentActionPlanStatus,
    AgentActionPlanStep,
    Library,
    LibraryStatus,
    ReadingOutline,
    ResearchPlan,
    ResearchPlanKind,
    ResearchPlanStatus,
    ResearchSkillPermission,
)


@pytest.mark.asyncio
async def test_research_plan_migration_creates_storage_tables(tmp_path: Path) -> None:
    db_path = await init_library_db(tmp_path / "library")

    async with aiosqlite.connect(db_path) as conn:
        cursor = await conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        tables = {row[0] for row in await cursor.fetchall()}
        cursor = await conn.execute("PRAGMA table_info(agent_action_plans)")
        action_columns = {row[1] for row in await cursor.fetchall()}
        cursor = await conn.execute("PRAGMA table_info(research_plans)")
        plan_columns = {row[1] for row in await cursor.fetchall()}

    assert {
        "research_plans",
        "agent_action_plans",
        "agent_action_plan_steps",
        "agent_action_plan_events",
    } <= tables
    assert {
        "article_revision_id",
        "skill_id",
        "skill_slug",
        "job_id",
        "idempotency_key",
        "payload_hash",
        "reading_outline_json",
        "preview_json",
        "result_json",
        "error_json",
    } <= plan_columns
    assert {
        "research_plan_id",
        "article_revision_id",
        "job_id",
        "idempotency_key",
        "payload_hash",
        "required_permissions_json",
        "preview_json",
        "result_json",
        "error_json",
    } <= action_columns


def test_research_plan_and_action_plan_models_serialize_json() -> None:
    now = datetime.now(UTC)
    outline = ReadingOutline(
        title="Reader path",
        summary="Follow the proof before implementation details.",
        sections=[{"title": "Assumption", "block_uid": "p-1"}],
        questions=["Where does convexity enter?"],
        source_refs=["p-1"],
    )
    plan = ResearchPlan(
        id="plan-1",
        kind=ResearchPlanKind.paper_reading,
        status=ResearchPlanStatus.active,
        title="Read a seed paper",
        article_revision_id="rev-1",
        skill_slug="lit-scout",
        job_id="job-1",
        idempotency_key="plan-key",
        payload_hash="hash-plan",
        candidate_papers=[{"title": "Candidate", "score": 0.91}],
        reading_outline=outline,
        payload={"seed": {"arxiv_id": "2401.00001"}},
        preview={"sections": 1},
        result={"accepted": False},
        error={"warnings": []},
        created_at=now,
        updated_at=now,
    )

    dumped_plan = plan.model_dump(mode="json")
    restored_plan = ResearchPlan.model_validate(dumped_plan)

    assert dumped_plan["kind"] == "paper_reading"
    assert restored_plan.reading_outline is not None
    assert restored_plan.reading_outline.sections[0]["block_uid"] == "p-1"
    assert restored_plan.candidate_papers[0]["score"] == 0.91

    step = AgentActionPlanStep(
        id="step-1",
        action_plan_id="action-1",
        position=0,
        kind="write_preview",
        title="Preview Markdown write",
        required_permissions=[ResearchSkillPermission.write_obsidian],
        payload={"target": "notes/paper.md"},
        preview={"markdown": "- claim"},
        result={"dry_run": True},
        error={"warnings": []},
        created_at=now,
        updated_at=now,
    )
    event = AgentActionPlanEvent(
        id="event-1",
        action_plan_id="action-1",
        kind=AgentActionPlanEventKind.status_recorded,
        status=AgentActionPlanStatus.pending,
        message="Preview stored",
        payload={"preview_hash": "abc"},
        created_at=now,
    )
    action_plan = AgentActionPlan(
        id="action-1",
        research_plan_id="plan-1",
        article_revision_id="rev-1",
        skill_slug="lit-scout",
        job_id="job-2",
        kind=AgentActionPlanKind.write_obsidian,
        status=AgentActionPlanStatus.pending,
        title="Write note preview",
        idempotency_key="action-key",
        payload_hash="hash-action",
        required_permissions=[ResearchSkillPermission.write_obsidian],
        payload={"note": "paper.md"},
        preview={"diff": "+ claim"},
        result={"path": "paper.md"},
        error={"warnings": []},
        steps=[step],
        events=[event],
        created_at=now,
        updated_at=now,
    )

    dumped_action = action_plan.model_dump(mode="json")
    restored_action = AgentActionPlan.model_validate(dumped_action)

    assert dumped_action["kind"] == "write_obsidian"
    assert dumped_action["required_permissions"] == ["write_obsidian"]
    assert restored_action.steps[0].preview == {"markdown": "- claim"}
    assert restored_action.events[0].status == AgentActionPlanStatus.pending


@pytest.mark.asyncio
async def test_research_plan_repository_create_list_get_and_idempotency(
    tmp_path: Path,
) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    outline = ReadingOutline(
        title="Proof map",
        sections=[{"title": "Setup", "block_uid": "s-1"}],
        source_refs=["s-1"],
    )

    created = await create_research_plan(
        library,
        title="Trace the theorem",
        kind=ResearchPlanKind.paper_reading,
        status=ResearchPlanStatus.active,
        topic="Bilinear optimization",
        article_revision_id=revision_id,
        skill_slug="lit-scout",
        job_id="job-plan",
        idempotency_key="research-plan-key",
        candidate_papers=[{"title": "A related paper", "metadata": {"year": 2025}}],
        reading_outline=outline,
        payload={"seed": {"article_revision_id": revision_id}},
        preview={"outline_sections": 1},
        result={"ready": True},
        error={"warnings": ["none"]},
    )
    duplicate = await create_research_plan(
        library,
        title="Mutated title",
        kind=ResearchPlanKind.custom,
        idempotency_key="research-plan-key",
        payload={"mutated": True},
    )
    listed = await list_research_plans(library, article_revision_id=revision_id)
    fetched = await get_research_plan(library, created.id)

    assert duplicate.id == created.id
    assert duplicate.title == "Trace the theorem"
    assert len(listed) == 1
    assert fetched == created
    assert fetched is not None
    assert fetched.article_revision_id == revision_id
    assert fetched.payload["seed"]["article_revision_id"] == revision_id
    assert fetched.preview == {"outline_sections": 1}
    assert fetched.result == {"ready": True}
    assert fetched.error == {"warnings": ["none"]}
    assert fetched.reading_outline is not None
    assert fetched.reading_outline.sections[0]["block_uid"] == "s-1"


@pytest.mark.asyncio
async def test_action_plan_repository_persists_steps_events_json_and_idempotency(
    tmp_path: Path,
) -> None:
    library, revision_id = await _library_with_revision(tmp_path)
    research_plan = await create_research_plan(
        library,
        title="Prepare note bridge",
        kind=ResearchPlanKind.skill_invocation,
        article_revision_id=revision_id,
        idempotency_key="note-plan-key",
        payload={"goal": "note preview"},
    )

    action = await create_agent_action_plan(
        library,
        research_plan_id=research_plan.id,
        article_revision_id=revision_id,
        skill_slug="note-bridge",
        job_id="job-action",
        kind=AgentActionPlanKind.write_obsidian,
        title="Preview Obsidian write",
        description="Prepare a patch without touching the vault.",
        idempotency_key="action-plan-key",
        required_permissions=[ResearchSkillPermission.write_obsidian],
        payload={"target_note": "Papers/Bilinear.md"},
        preview={"patch": "## Claim\nText"},
        result={"dry_run": True},
        error={"warnings": ["none"]},
        steps=[
            {
                "kind": "render_patch",
                "title": "Render Markdown patch",
                "required_permissions": [ResearchSkillPermission.write_obsidian],
                "payload": {"block_uid": "p-1"},
                "preview": {"markdown": "Text"},
                "result": {"lines": 2},
                "error": {"warnings": []},
            }
        ],
    )
    event = await append_agent_action_plan_event(
        library,
        action.id,
        kind=AgentActionPlanEventKind.status_recorded,
        status=AgentActionPlanStatus.pending,
        step_id=action.steps[0].id,
        message="Preview is ready for review",
        payload={"preview_hash": "abc123"},
    )
    duplicate = await create_agent_action_plan(
        library,
        kind=AgentActionPlanKind.export_article,
        title="Mutated action",
        idempotency_key="action-plan-key",
        payload={"mutated": True},
    )
    listed = await list_agent_action_plans(
        library,
        article_revision_id=revision_id,
        status=AgentActionPlanStatus.pending,
    )
    fetched = await get_agent_action_plan(library, action.id)

    assert duplicate.id == action.id
    assert duplicate.title == "Preview Obsidian write"
    assert len(listed) == 1
    assert fetched is not None
    assert fetched.research_plan_id == research_plan.id
    assert fetched.required_permissions == [ResearchSkillPermission.write_obsidian]
    assert fetched.payload == {"target_note": "Papers/Bilinear.md"}
    assert fetched.preview == {"patch": "## Claim\nText"}
    assert fetched.result == {"dry_run": True}
    assert fetched.error == {"warnings": ["none"]}
    assert len(fetched.steps) == 1
    assert fetched.steps[0].payload == {"block_uid": "p-1"}
    assert fetched.steps[0].preview == {"markdown": "Text"}
    assert fetched.steps[0].result == {"lines": 2}
    assert fetched.steps[0].error == {"warnings": []}
    assert event.payload == {"preview_hash": "abc123"}
    assert [stored_event.message for stored_event in fetched.events] == [
        "Action plan created",
        "Preview is ready for review",
    ]
    assert fetched.events[-1].step_id == action.steps[0].id


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
