from __future__ import annotations

import ast
import hashlib
import json
import re
from pathlib import Path
from typing import Any
from uuid import NAMESPACE_URL, uuid5

from bilin_api.repositories import (
    enable_research_skill as persist_enabled_research_skill,
    get_research_skill,
    list_research_skills,
    upsert_research_skill,
)
from bilin_api.schemas import (
    ResearchSkill,
    ResearchSkillInstallStatus,
    ResearchSkillPermission,
    ResearchSkillProvenance,
    ResearchSkillStatus,
    ResearchSkillUpsert,
)

JsonDict = dict[str, Any]

_RESEARCH_PLAN_TASKS = (
    "paper_reading",
    "literature_review",
)

_PERMISSION_MANIFEST_KEYS = {
    "permission_manifest",
    "permission_manifest_version",
    "permissions",
    "declared_permissions",
    "required_permissions",
}


class ResearchSkillEnableError(ValueError):
    pass


class ResearchSkillDigestMismatchError(ResearchSkillEnableError):
    pass


class ResearchSkillPermissionError(ResearchSkillEnableError):
    pass


def discover_local_research_skill_metadata(
    *,
    project_root: Path | None = None,
    codex_skills_root: Path | None = None,
) -> list[ResearchSkillUpsert]:
    """Read local SKILL.md metadata without invoking any skill code."""

    project_root = (project_root or Path.cwd()).expanduser().resolve()
    codex_skills_root = (
        codex_skills_root.expanduser().resolve()
        if codex_skills_root is not None
        else Path.home().expanduser().resolve() / ".codex" / "skills"
    )
    roots = [
        ("codex_user", codex_skills_root),
        ("project", project_root / ".agents" / "skills"),
    ]
    discovered: dict[str, ResearchSkillUpsert] = {}
    for source_kind, root in roots:
        if not root.exists():
            continue
        for skill_markdown_path in sorted(root.glob("*/SKILL.md")):
            skill = research_skill_from_markdown(
                skill_markdown_path,
                source_kind=source_kind,
                source_root=root,
            )
            discovered[skill.slug] = skill
    return sorted(discovered.values(), key=lambda skill: skill.slug)


async def index_local_research_skills(
    *,
    project_root: Path | None = None,
    codex_skills_root: Path | None = None,
) -> list[ResearchSkill]:
    skills = discover_local_research_skill_metadata(
        project_root=project_root,
        codex_skills_root=codex_skills_root,
    )
    return [await upsert_research_skill(skill) for skill in skills]


async def enable_research_skill(
    identifier: str,
    *,
    expected_digest: str | None = None,
    granted_permissions: list[ResearchSkillPermission] | None = None,
) -> ResearchSkill | None:
    skill = await get_research_skill(identifier)
    if skill is None:
        return None

    if expected_digest is not None and expected_digest != skill.digest:
        raise ResearchSkillDigestMismatchError(
            f"Research skill digest changed from {expected_digest} to {skill.digest}."
        )

    permissions = granted_permissions if granted_permissions is not None else skill.declared_permissions
    declared_permission_values = {permission.value for permission in skill.declared_permissions}
    unknown_permissions = [
        permission
        for permission in permissions
        if declared_permission_values and permission.value not in declared_permission_values
    ]
    if unknown_permissions:
        raise ResearchSkillPermissionError(
            "Granted permissions must be a subset of declared permissions."
        )

    return await persist_enabled_research_skill(
        identifier,
        granted_permissions=permissions,
    )


def _normalize_task_name(value: str) -> str:
    return re.sub(r"[^a-z0-9]", "", value.lower())


def _skill_supports_task(skill: ResearchSkill, task: str) -> bool:
    if not skill.supported_tasks:
        return True
    normalized_target = _normalize_task_name(task)
    for supported_task in skill.supported_tasks:
        if _normalize_task_name(supported_task) == normalized_target:
            return True
    return False


def _skill_is_enabled(skill: ResearchSkill) -> bool:
    return skill.enabled or skill.status == ResearchSkillStatus.enabled


async def resolve_research_plan_skill_provenance(
    *, requested_slug: str | None = None
) -> tuple[ResearchSkill | None, ResearchSkillProvenance | None]:
    if requested_slug is not None:
        skill = await get_research_skill(requested_slug)
        if skill is not None and _skill_is_enabled(skill) and any(
            _skill_supports_task(skill, task) for task in _RESEARCH_PLAN_TASKS
        ):
            provenance = ResearchSkillProvenance(
                skill_slug=skill.slug,
                source=skill.source_path,
                version=skill.version,
                digest=skill.digest,
            )
            return skill, provenance

    available_skills = await list_research_skills()
    for task in _RESEARCH_PLAN_TASKS:
        for skill in available_skills:
            if _skill_is_enabled(skill) and _skill_supports_task(skill, task):
                provenance = ResearchSkillProvenance(
                    skill_slug=skill.slug,
                    source=skill.source_path,
                    version=skill.version,
                    digest=skill.digest,
                )
                return skill, provenance

    return None, None


def research_skill_from_markdown(
    skill_markdown_path: Path,
    *,
    source_kind: str,
    source_root: Path,
) -> ResearchSkillUpsert:
    source_path = skill_markdown_path.expanduser().resolve()
    source_root = source_root.expanduser().resolve()
    content = source_path.read_bytes()
    text = content.decode("utf-8")
    frontmatter, body = _split_frontmatter(text)
    digest = hashlib.sha256(content).hexdigest()
    raw_slug = _first_string(frontmatter, "slug", "name") or source_path.parent.name
    slug = _normalize_slug(raw_slug)
    title = _first_string(frontmatter, "title", "name") or _title_from_slug(slug)
    description = _first_string(frontmatter, "description", "summary") or _first_paragraph(body)
    version = _string_or_none(frontmatter.get("version"))
    manifest_version = _int_or_default(
        frontmatter.get("manifest_version", frontmatter.get("schema_version")),
        default=1,
    )
    declared_permissions, unknown_permissions = _coerce_permissions(
        _first_present(frontmatter, "permissions", "declared_permissions", "required_permissions")
    )
    has_permission_manifest = any(key in frontmatter for key in _PERMISSION_MANIFEST_KEYS)
    input_shape = _dict_or_empty(_first_present(frontmatter, "input_shape", "inputs"))
    output_shape = _dict_or_empty(_first_present(frontmatter, "output_shape", "outputs"))
    supported_tasks = _string_list(
        _first_present(frontmatter, "supported_tasks", "tasks", "capabilities", "tags")
    )
    capability_tags = sorted(
        {
            *_string_list(frontmatter.get("capabilities")),
            *_string_list(frontmatter.get("tags")),
            *supported_tasks,
        }
    )
    frontmatter_metadata = _dict_or_empty(frontmatter.get("metadata"))
    metadata = {
        **frontmatter_metadata,
        "capability_tags": capability_tags,
        "has_permission_manifest": has_permission_manifest,
        "source_kind": source_kind,
        "source_root": str(source_root),
        "skill_markdown_path": str(source_path),
        "unknown_permissions": unknown_permissions,
    }
    status = (
        ResearchSkillStatus.disabled
        if has_permission_manifest
        else ResearchSkillStatus.metadata_only
    )
    return ResearchSkillUpsert(
        id=_stable_skill_id(slug),
        slug=slug,
        title=title,
        description=description,
        source_path=str(source_path),
        cache_path=_string_or_none(frontmatter.get("cache_path")),
        digest=digest,
        digest_algorithm="sha256",
        version=version,
        manifest_version=manifest_version,
        install_status=ResearchSkillInstallStatus.discovered,
        status=status,
        enabled=False,
        declared_permissions=declared_permissions,
        granted_permissions=[],
        input_shape=input_shape,
        output_shape=output_shape,
        supported_tasks=supported_tasks,
        metadata=metadata,
    )


def _split_frontmatter(text: str) -> tuple[JsonDict, str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, text
    for index, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return _parse_frontmatter("\n".join(lines[1:index])), "\n".join(lines[index + 1 :])
    return {}, text


def _parse_frontmatter(raw: str) -> JsonDict:
    parsed: JsonDict = {}
    current_key: str | None = None
    for line in raw.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if line[0].isspace():
            if current_key is None:
                continue
            if stripped.startswith("- "):
                if not isinstance(parsed.get(current_key), list):
                    parsed[current_key] = []
                parsed[current_key].append(_parse_scalar(stripped[2:].strip()))
                continue
            if ":" in stripped:
                if not isinstance(parsed.get(current_key), dict):
                    parsed[current_key] = {}
                key, value = stripped.split(":", 1)
                parsed[current_key][key.strip()] = _parse_scalar(value.strip())
            continue
        if ":" not in line:
            continue
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if value:
            parsed[key] = _parse_scalar(value)
            current_key = None
        else:
            parsed[key] = None
            current_key = key
    return parsed


def _parse_scalar(raw: str) -> Any:
    if raw == "":
        return ""
    lowered = raw.lower()
    if lowered == "true":
        return True
    if lowered == "false":
        return False
    if lowered in {"null", "none"}:
        return None
    if raw.startswith("[") and raw.endswith("]"):
        for parser in (json.loads, ast.literal_eval):
            try:
                return parser(raw)
            except (ValueError, SyntaxError, json.JSONDecodeError):
                pass
        return [
            _parse_scalar(part.strip())
            for part in raw.removeprefix("[").removesuffix("]").split(",")
            if part.strip()
        ]
    if raw.startswith("{") and raw.endswith("}"):
        for parser in (json.loads, ast.literal_eval):
            try:
                value = parser(raw)
            except (ValueError, SyntaxError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                return value
        return raw
    if raw.startswith(("'", '"')) and raw.endswith(("'", '"')):
        try:
            return ast.literal_eval(raw)
        except (ValueError, SyntaxError):
            return raw[1:-1]
    try:
        return int(raw)
    except ValueError:
        return raw


def _coerce_permissions(
    value: Any,
) -> tuple[list[ResearchSkillPermission], list[str]]:
    permissions: list[ResearchSkillPermission] = []
    unknown: list[str] = []
    for item in _string_list(value):
        canonical = item.strip().lower().replace("-", "_")
        try:
            permission = ResearchSkillPermission(canonical)
        except ValueError:
            unknown.append(item)
            continue
        if permission not in permissions:
            permissions.append(permission)
    return permissions, unknown


def _first_present(values: JsonDict, *keys: str) -> Any:
    for key in keys:
        if key in values:
            return values[key]
    return None


def _first_string(values: JsonDict, *keys: str) -> str | None:
    value = _first_present(values, *keys)
    return _string_or_none(value)


def _string_or_none(value: Any) -> str | None:
    if value is None:
        return None
    if isinstance(value, str):
        stripped = value.strip()
        return stripped or None
    return str(value)


def _string_list(value: Any) -> list[str]:
    if value is None:
        return []
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    if isinstance(value, str):
        parts = value.split(",") if "," in value else [value]
        return [part.strip() for part in parts if part.strip()]
    return [str(value).strip()] if str(value).strip() else []


def _dict_or_empty(value: Any) -> JsonDict:
    return value if isinstance(value, dict) else {}


def _int_or_default(value: Any, *, default: int) -> int:
    if isinstance(value, int):
        return value
    if isinstance(value, str):
        try:
            return int(value)
        except ValueError:
            return default
    return default


def _first_paragraph(body: str) -> str:
    lines: list[str] = []
    for line in body.splitlines():
        stripped = line.strip()
        if not stripped:
            if lines:
                break
            continue
        if stripped.startswith("#"):
            continue
        lines.append(stripped)
    return " ".join(lines)


def _normalize_slug(value: str) -> str:
    slug = re.sub(r"[^a-z0-9._-]+", "-", value.strip().lower()).strip(".-_")
    return slug or "skill"


def _title_from_slug(slug: str) -> str:
    return slug.replace("-", " ").replace("_", " ").title()


def _stable_skill_id(slug: str) -> str:
    return str(uuid5(NAMESPACE_URL, f"bilin:research-skill:v1:{slug}"))
