from __future__ import annotations

import hashlib
from pathlib import Path

import aiosqlite
import pytest

from bilin_api.database import init_global_db
from bilin_api.repositories import (
    get_research_skill,
    list_research_skills,
    upsert_research_skill,
)
from bilin_api.research_skill_service import (
    discover_local_research_skill_metadata,
    enable_research_skill,
    index_local_research_skills,
    resolve_research_plan_skill_provenance,
    ResearchSkillDigestMismatchError,
    ResearchSkillPermissionError,
)
from bilin_api.schemas import (
    ResearchSkillInstallStatus,
    ResearchSkillPermission,
    ResearchSkillStatus,
    ResearchSkillUpsert,
)


@pytest.mark.asyncio
async def test_research_skill_migration_creates_catalog_table() -> None:
    db_path = await init_global_db()
    async with aiosqlite.connect(db_path) as conn:
        cursor = await conn.execute("SELECT name FROM sqlite_master WHERE type = 'table'")
        tables = {row[0] for row in await cursor.fetchall()}
        cursor = await conn.execute("PRAGMA table_info(research_skills)")
        columns = {row[1] for row in await cursor.fetchall()}

    assert "research_skills" in tables
    assert {
        "id",
        "slug",
        "title",
        "description",
        "source_path",
        "cache_path",
        "digest",
        "digest_algorithm",
        "version",
        "manifest_version",
        "install_status",
        "status",
        "enabled",
        "declared_permissions_json",
        "granted_permissions_json",
        "input_shape_json",
        "output_shape_json",
        "supported_tasks_json",
        "metadata_json",
        "created_at",
        "updated_at",
    } <= columns


@pytest.mark.asyncio
async def test_research_skill_repository_upsert_is_idempotent(tmp_path: Path) -> None:
    payload = ResearchSkillUpsert(
        id="skill-lit-scout",
        slug="lit-scout",
        title="Literature Scout",
        description="Finds related work.",
        source_path=str(tmp_path / "SKILL.md"),
        digest="sha256:first",
        install_status=ResearchSkillInstallStatus.discovered,
        status=ResearchSkillStatus.disabled,
        enabled=False,
        declared_permissions=[ResearchSkillPermission.network],
        granted_permissions=[],
        input_shape={"type": "object"},
        output_shape={"type": "object"},
        supported_tasks=["literature_review"],
        metadata={"source_kind": "test"},
    )

    created = await upsert_research_skill(payload)
    updated = await upsert_research_skill(
        payload.model_copy(update={"description": "Updated metadata.", "digest": "sha256:second"})
    )
    listed = await list_research_skills()

    assert len(listed) == 1
    assert updated.id == created.id
    assert updated.created_at == created.created_at
    assert updated.updated_at >= created.updated_at
    assert updated.description == "Updated metadata."
    assert updated.digest == "sha256:second"
    assert updated.declared_permissions == [ResearchSkillPermission.network]
    assert await get_research_skill(created.id) == updated
    assert await get_research_skill("lit-scout") == updated


@pytest.mark.asyncio
async def test_local_research_skill_discovery_indexes_metadata_only_legacy_skills(
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "project"
    project_skill = project_root / ".agents" / "skills" / "lit-scout" / "SKILL.md"
    project_skill.parent.mkdir(parents=True)
    project_skill.write_text(
        """---
name: lit-scout
title: Literature Scout
description: "Finds related papers without executing a script."
version: "0.1.0"
manifest_version: 2
permissions:
  - network
  - download_paper
  - unknown-danger
supported_tasks:
  - literature_review
tags: ["papers", "scouting"]
input_shape: {"type": "object", "required": ["topic"]}
output_shape: {"type": "object"}
metadata: {"domain": "research"}
---

# Literature Scout

This body should not be needed when frontmatter has a description.
""",
        encoding="utf-8",
    )

    codex_skills_root = tmp_path / "codex-skills"
    duplicate_user_skill = codex_skills_root / "lit-scout" / "SKILL.md"
    duplicate_user_skill.parent.mkdir(parents=True)
    duplicate_user_skill.write_text(
        """---
name: lit-scout
description: User-level duplicate that project metadata should replace.
---
""",
        encoding="utf-8",
    )
    legacy_skill = codex_skills_root / "legacy-skill" / "SKILL.md"
    legacy_skill.parent.mkdir(parents=True)
    legacy_skill.write_text(
        """# Legacy Skill

Run `python scripts/do_work.py` when asked.
""",
        encoding="utf-8",
    )

    discovered = discover_local_research_skill_metadata(
        project_root=project_root,
        codex_skills_root=codex_skills_root,
    )
    indexed = await index_local_research_skills(
        project_root=project_root,
        codex_skills_root=codex_skills_root,
    )

    assert {skill.slug for skill in discovered} == {"legacy-skill", "lit-scout"}
    assert {skill.slug for skill in indexed} == {"legacy-skill", "lit-scout"}

    lit_scout = await get_research_skill("lit-scout")
    assert lit_scout is not None
    assert lit_scout.title == "Literature Scout"
    assert lit_scout.source_path == str(project_skill.resolve())
    assert lit_scout.digest == hashlib.sha256(project_skill.read_bytes()).hexdigest()
    assert lit_scout.version == "0.1.0"
    assert lit_scout.manifest_version == 2
    assert lit_scout.status == ResearchSkillStatus.disabled
    assert lit_scout.enabled is False
    assert lit_scout.declared_permissions == [
        ResearchSkillPermission.network,
        ResearchSkillPermission.download_paper,
    ]
    assert lit_scout.granted_permissions == []
    assert lit_scout.input_shape == {"type": "object", "required": ["topic"]}
    assert lit_scout.output_shape == {"type": "object"}
    assert lit_scout.supported_tasks == ["literature_review"]
    assert lit_scout.metadata["domain"] == "research"
    assert lit_scout.metadata["source_kind"] == "project"
    assert lit_scout.metadata["has_permission_manifest"] is True
    assert lit_scout.metadata["unknown_permissions"] == ["unknown-danger"]

    legacy = await get_research_skill("legacy-skill")
    assert legacy is not None
    assert legacy.status == ResearchSkillStatus.metadata_only
    assert legacy.enabled is False
    assert legacy.declared_permissions == []
    assert legacy.granted_permissions == []
    assert legacy.metadata["has_permission_manifest"] is False


@pytest.mark.asyncio
async def test_enable_research_skill_requires_current_digest_and_declared_permissions(
    tmp_path: Path,
) -> None:
    payload = ResearchSkillUpsert(
        id="skill-paper-outline",
        slug="paper-outline",
        title="Paper Outline",
        description="Builds reading outlines.",
        source_path=str(tmp_path / "paper-outline" / "SKILL.md"),
        digest="sha256:current",
        install_status=ResearchSkillInstallStatus.discovered,
        status=ResearchSkillStatus.disabled,
        enabled=False,
        declared_permissions=[ResearchSkillPermission.provider_call],
        granted_permissions=[],
        supported_tasks=["paper_reading"],
    )
    await upsert_research_skill(payload)

    with pytest.raises(ResearchSkillDigestMismatchError):
        await enable_research_skill("paper-outline", expected_digest="sha256:stale")

    with pytest.raises(ResearchSkillPermissionError):
        await enable_research_skill(
            "paper-outline",
            granted_permissions=[ResearchSkillPermission.network],
        )

    enabled = await enable_research_skill(
        "paper-outline",
        expected_digest="sha256:current",
        granted_permissions=[ResearchSkillPermission.provider_call],
    )

    assert enabled is not None
    assert enabled.status == ResearchSkillStatus.enabled
    assert enabled.enabled is True
    assert enabled.granted_permissions == [ResearchSkillPermission.provider_call]


@pytest.mark.asyncio
async def test_resolve_research_plan_skill_provenance_prefers_reading_tasks(
    tmp_path: Path,
) -> None:
    project_root = tmp_path / "project"
    skill_markdown = project_root / ".agents" / "skills" / "paper-outline" / "SKILL.md"
    skill_markdown.parent.mkdir(parents=True)
    skill_markdown.write_text(
        """---
name: paper-outline
title: Paper Outline
description: Build paper outlines.
version: 0.2.0
supported_tasks:
  - paper_reading
---

# Paper Outline
""",
        encoding="utf-8",
    )

    indexed = await index_local_research_skills(
        project_root=project_root,
        codex_skills_root=tmp_path / "codex",
    )

    _, disabled_provenance = await resolve_research_plan_skill_provenance(
        requested_slug="paper-outline"
    )
    enabled = await enable_research_skill(
        "paper-outline",
        expected_digest=indexed[0].digest,
    )
    _, provenance = await resolve_research_plan_skill_provenance(requested_slug="paper-outline")

    assert len(indexed) == 1
    assert disabled_provenance is None
    assert enabled is not None
    assert enabled.enabled is True
    assert enabled.status == ResearchSkillStatus.enabled
    assert provenance is not None
    assert provenance.skill_slug == "paper-outline"
    assert provenance.version == "0.2.0"
    assert isinstance(provenance.source, str) and provenance.source


@pytest.mark.asyncio
async def test_resolve_research_plan_skill_provenance_prefers_supported_tasks_when_not_requested(
    tmp_path: Path,
) -> None:
    await upsert_research_skill(
        ResearchSkillUpsert(
            id="skill-literature-review",
            slug="literature-review",
            title="Literature Review",
            description="Collects related work with evidence tables.",
            source_path=str(tmp_path / "literature" / "SKILL.md"),
            digest="sha256:literature",
            install_status=ResearchSkillInstallStatus.discovered,
            status=ResearchSkillStatus.disabled,
            supported_tasks=["literature_review"],
            enabled=False,
            declared_permissions=[],
            granted_permissions=[],
            input_shape={},
            output_shape={},
            metadata={},
        )
    )
    enabled = await enable_research_skill("literature-review")

    _, provenance = await resolve_research_plan_skill_provenance(requested_slug=None)

    assert enabled is not None
    assert enabled.enabled is True
    assert provenance is not None
    assert provenance.skill_slug == "literature-review"
