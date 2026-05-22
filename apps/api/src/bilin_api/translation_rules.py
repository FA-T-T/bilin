from __future__ import annotations

import re

TRANSLATABLE_BLOCK_TYPES = frozenset({"paragraph", "list", "figure", "table"})

_INLINE_MATH_RE = re.compile(r"(?<!\\)\$(?:\\.|[^$])+(?<!\\)\$", re.DOTALL)
_DISPLAY_MATH_PATTERNS = (
    re.compile(r"\$\$.*?\$\$", re.DOTALL),
    re.compile(r"\\\[.*?\\\]", re.DOTALL),
    re.compile(r"\\\(.*?\\\)", re.DOTALL),
    re.compile(r"\\begin\{(?P<env>[A-Za-z*]+)\}.*?\\end\{(?P=env)\}", re.DOTALL),
)


def is_translatable_source(block_type: str, source_markdown: str) -> bool:
    return (
        block_type in TRANSLATABLE_BLOCK_TYPES
        and bool(source_markdown.strip())
        and not is_translation_invariant_markdown(source_markdown)
    )


def is_translation_invariant_markdown(markdown: str) -> bool:
    text = markdown.strip()
    if not text:
        return False
    visible = re.sub(r"!\[([^\]]*)]\([^)]*\)", r"\1", text)
    visible = re.sub(r"\[([^\]]+)]\([^)]*\)", r"\1", visible)
    visible = _remove_math_regions(visible)
    visible = re.sub(r"<[^>]+>", " ", visible)
    visible = re.sub(r"\\[A-Za-z]+\*?", " ", visible)
    visible = re.sub(r"\\.", " ", visible)
    visible = re.sub(r"[^A-Za-z0-9]+", " ", visible).strip()
    words = re.findall(r"[A-Za-z][A-Za-z0-9-]*", visible)
    if not words:
        return True
    return len(words) <= 4 and all(word.upper() == word for word in words)


def _remove_math_regions(text: str) -> str:
    cleaned = text
    for pattern in _DISPLAY_MATH_PATTERNS:
        cleaned = pattern.sub(" ", cleaned)
    return _INLINE_MATH_RE.sub(" ", cleaned)
