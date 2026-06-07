from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from bilin_api.main import app


def test_research_skill_api_indexes_local_metadata(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "project"
    skill_markdown = project_root / ".agents" / "skills" / "paper-outline" / "SKILL.md"
    skill_markdown.parent.mkdir(parents=True)
    skill_markdown.write_text(
        """---
name: paper-outline
title: Paper Outline
description: Build a paper-specific reading outline.
permissions:
  - provider_call
supported_tasks:
  - paper_reading
---

# Paper Outline
""",
        encoding="utf-8",
    )

    with TestClient(app) as client:
        index_response = client.post(
            "/research-skills/index-local",
            json={"project_root": str(project_root), "codex_skills_root": str(tmp_path / "empty")},
        )
        list_response = client.get("/research-skills")
        get_response = client.get("/research-skills/paper-outline")
        missing_response = client.get("/research-skills/missing-skill")
        enable_response = client.post(
            "/research-skills/paper-outline/enable",
            json={
                "expected_digest": index_response.json()[0]["digest"],
                "granted_permissions": ["provider_call"],
            },
        )
        stale_enable_response = client.post(
            "/research-skills/paper-outline/enable",
            json={
                "expected_digest": "sha256:stale",
                "granted_permissions": ["provider_call"],
            },
        )

    assert index_response.status_code == 200
    assert index_response.json()[0]["slug"] == "paper-outline"
    assert index_response.json()[0]["status"] == "disabled"
    assert index_response.json()[0]["enabled"] is False
    assert index_response.json()[0]["declared_permissions"] == ["provider_call"]
    assert list_response.status_code == 200
    assert [skill["slug"] for skill in list_response.json()] == ["paper-outline"]
    assert get_response.status_code == 200
    assert get_response.json()["title"] == "Paper Outline"
    assert missing_response.status_code == 404
    assert enable_response.status_code == 200
    assert enable_response.json()["status"] == "enabled"
    assert enable_response.json()["enabled"] is True
    assert enable_response.json()["granted_permissions"] == ["provider_call"]
    assert stale_enable_response.status_code == 409


def test_generate_research_plan_action_requires_confirmation_then_materializes_plan(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "project"
    paper_skill = project_root / ".agents" / "skills" / "paper-outline" / "SKILL.md"
    paper_skill.parent.mkdir(parents=True)
    paper_skill.write_text(
        """---
name: paper-outline
title: Paper Outline
description: Build a review-ready paper outline.
version: "1.0.0"
permissions:
  - provider_call
supported_tasks:
  - paper_reading
---

# Paper Outline
""",
        encoding="utf-8",
    )

    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Research", "path": str(tmp_path / "library")},
        )
        library_id = library_response.json()["id"]

        index_response = client.post(
            "/research-skills/index-local",
            json={
                "project_root": str(project_root),
                "codex_skills_root": str(tmp_path / "codex"),
            },
        )
        disabled_generate_response = client.post(
            f"/libraries/{library_id}/research-plans/generate",
            json={
                "title": "Draft from candidate papers",
                "kind": "paper_reading",
                "topic": "adaptive optimization",
                "skill_slug": "paper-outline",
                "candidate_papers": [],
                "payload": {},
            },
        )
        enable_response = client.post(
            "/research-skills/paper-outline/enable",
            json={
                "expected_digest": index_response.json()[0]["digest"],
                "granted_permissions": ["provider_call"],
            },
        )

        generate_response = client.post(
            f"/libraries/{library_id}/research-plans/generate",
            json={
                "title": "Draft from candidate papers",
                "kind": "paper_reading",
                "topic": "adaptive optimization",
                "skill_slug": "paper-outline",
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
                "payload": {
                    "seed": "2401.00001",
                },
            },
        )

        action_payload = generate_response.json()
        draft_plans = client.get(f"/libraries/{library_id}/research-plans")
        approve_action_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/approve",
            json={
                "expected_payload_hash": action_payload["payload_hash"],
                "payload": {"reviewer": "user"},
            },
        )
        draft_plans_after_approve = client.get(f"/libraries/{library_id}/research-plans")
        start_action_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/start",
            json={"payload": {"runner": "local"}},
        )
        succeed_action_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/succeed",
            json={
                "result": {
                    "reading_outline": {
                        "title": "Skill generated paper outline",
                        "summary": "Read the paper through its convergence claim.",
                        "sourceRefs": ["2401.00001"],
                        "paperMasteryOutlines": [
                            {
                                "paper_id": "2401.00001",
                                "paper_title": "A sample paper from skill",
                                "claim": ["The agent-selected claim."],
                                "method": ["Agent-selected proof path"],
                                "followUp": ["Compare against a stronger baseline"],
                            }
                        ],
                    },
                },
            },
        )
        active_plans = client.get(
            f"/libraries/{library_id}/research-plans",
            params={"kind": "paper_reading", "status": "active"},
        )

    assert library_response.status_code == 201
    assert index_response.status_code == 200
    assert index_response.json()[0]["slug"] == "paper-outline"
    assert disabled_generate_response.status_code == 400
    assert enable_response.status_code == 200
    assert enable_response.json()["enabled"] is True
    assert generate_response.status_code == 201
    assert action_payload["kind"] == "generate_research_outline"
    assert action_payload["status"] == "pending"
    assert action_payload["skill_slug"] == "paper-outline"
    assert draft_plans.status_code == 200
    assert draft_plans.json() == []
    assert approve_action_response.status_code == 200
    assert draft_plans_after_approve.status_code == 200
    assert draft_plans_after_approve.json() == []
    assert start_action_response.status_code == 200
    assert succeed_action_response.status_code == 200
    assert succeed_action_response.json()["status"] == "succeeded"
    assert active_plans.status_code == 200
    plans = active_plans.json()
    assert len(plans) == 1
    reading_outline = plans[0]["reading_outline"]
    assert reading_outline["title"] == "Skill generated paper outline"
    assert reading_outline["summary"] == "Read the paper through its convergence claim."
    assert reading_outline["source_refs"] == ["2401.00001"]
    assert len(reading_outline["paperMasteryOutlines"]) == 1
    assert reading_outline["paperMasteryOutlines"][0]["paper_id"] == "2401.00001"
    assert reading_outline["paperMasteryOutlines"][0]["paper_title"] == "A sample paper from skill"
    assert reading_outline["paperMasteryOutlines"][0]["claim"] == ["The agent-selected claim."]
    assert reading_outline["paperMasteryOutlines"][0]["followUp"] == [
        "Compare against a stronger baseline"
    ]
    assert plans[0]["payload"]["skill_provenance"]["skill_slug"] == "paper-outline"
    assert plans[0]["payload"]["skill_provenance"]["version"] == "1.0.0"


def test_research_plan_and_action_plan_api_confirmation_flow(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Research", "path": str(tmp_path / "library")},
        )
        library_id = library_response.json()["id"]
        plan_response = client.post(
            f"/libraries/{library_id}/research-plans",
            json={
                "title": "Read the seed paper",
                "kind": "paper_reading",
                "status": "active",
                "topic": "Bilinear optimization",
                "candidate_papers": [{"title": "A related paper", "score": 0.91}],
                "reading_outline": {
                    "title": "Master the proof path",
                    "sections": [{"title": "Setup", "block_uid": "s-1"}],
                    "questions": ["Where is convexity used?"],
                    "source_refs": ["s-1"],
                },
                "payload": {"seed": "2401.00001"},
            },
        )
        plan_id = plan_response.json()["id"]
        action_response = client.post(
            f"/libraries/{library_id}/agent-action-plans",
            json={
                "research_plan_id": plan_id,
                "kind": "write_obsidian",
                "title": "Preview Obsidian note write",
                "description": "Prepare a Markdown patch before touching the vault.",
                "required_permissions": ["write_obsidian"],
                "payload": {"target_note": "Papers/Seed.md"},
                "preview": {"patch": "## Claim\nText"},
                "steps": [
                    {
                        "kind": "render_patch",
                        "title": "Render Markdown patch",
                        "required_permissions": ["write_obsidian"],
                        "payload": {"block_uid": "s-1"},
                    }
                ],
            },
        )
        action_payload = action_response.json()
        approve_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/approve",
            json={
                "expected_payload_hash": action_payload["payload_hash"],
                "payload": {"reviewer": "user"},
            },
        )
        start_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/start",
            json={"payload": {"executor": "local-worker"}},
        )
        succeed_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_payload['id']}/succeed",
            json={"result": {"path": "Papers/Seed.md"}},
        )
        listed_plans_response = client.get(
            f"/libraries/{library_id}/research-plans",
            params={"status": "active", "kind": "paper_reading"},
        )
        listed_actions_response = client.get(
            f"/libraries/{library_id}/agent-action-plans",
            params={"status": "succeeded", "kind": "write_obsidian"},
        )

    assert library_response.status_code == 201
    assert plan_response.status_code == 201
    assert plan_response.json()["reading_outline"]["sections"][0]["block_uid"] == "s-1"
    assert action_response.status_code == 201
    assert action_payload["status"] == "pending"
    assert action_payload["steps"][0]["kind"] == "render_patch"
    assert approve_response.status_code == 200
    assert approve_response.json()["status"] == "approved"
    assert start_response.status_code == 200
    assert start_response.json()["status"] == "running"
    assert succeed_response.status_code == 200
    assert succeed_response.json()["status"] == "succeeded"
    assert succeed_response.json()["payload"] == {"target_note": "Papers/Seed.md"}
    assert succeed_response.json()["result"] == {"path": "Papers/Seed.md"}
    assert [event["status"] for event in succeed_response.json()["events"]] == [
        "pending",
        "approved",
        "running",
        "succeeded",
    ]
    assert listed_plans_response.status_code == 200
    assert [plan["id"] for plan in listed_plans_response.json()] == [plan_id]
    assert listed_actions_response.status_code == 200
    assert [action["id"] for action in listed_actions_response.json()] == [action_payload["id"]]


def test_agent_action_plan_api_guards_confirmation_boundary(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    with TestClient(app) as client:
        library_response = client.post(
            "/libraries",
            json={"name": "Research", "path": str(tmp_path / "library")},
        )
        library_id = library_response.json()["id"]
        rejected_create = client.post(
            f"/libraries/{library_id}/agent-action-plans",
            json={
                "kind": "write_obsidian",
                "status": "approved",
                "title": "Unsafe direct approval",
            },
        )
        action_response = client.post(
            f"/libraries/{library_id}/agent-action-plans",
            json={
                "kind": "write_obsidian",
                "title": "Guarded write",
                "payload": {"target_note": "Papers/Seed.md"},
            },
        )
        mismatch_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/{action_response.json()['id']}/approve",
            json={"expected_payload_hash": "wrong-hash"},
        )
        missing_response = client.post(
            f"/libraries/{library_id}/agent-action-plans/missing-action/approve",
            json={},
        )

    assert rejected_create.status_code == 400
    assert "pending" in rejected_create.json()["detail"]
    assert action_response.status_code == 201
    assert mismatch_response.status_code == 409
    assert missing_response.status_code == 404
