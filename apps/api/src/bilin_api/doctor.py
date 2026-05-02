from __future__ import annotations

import shutil
import subprocess
from collections.abc import Callable

from bilin_api.credentials import keychain_status_message
from bilin_api.schemas import (
    DoctorCapability,
    DoctorCapabilityLevel,
    DoctorCapabilityStatus,
    DoctorReport,
)
from bilin_api.settings import get_settings

Resolver = Callable[[str], str | None]


TOOLS: tuple[tuple[str, DoctorCapabilityLevel], ...] = (
    ("latexml", DoctorCapabilityLevel.recommended),
    ("latexmlpost", DoctorCapabilityLevel.recommended),
    ("pandoc", DoctorCapabilityLevel.recommended),
    ("tectonic", DoctorCapabilityLevel.optional),
    ("pdflatex", DoctorCapabilityLevel.optional),
    ("magick", DoctorCapabilityLevel.optional),
    ("gs", DoctorCapabilityLevel.optional),
    ("pdfinfo", DoctorCapabilityLevel.optional),
)

TOOL_MESSAGES: dict[str, tuple[str, str]] = {
    "latexml": (
        "LaTeXML is available for TeX source parsing.",
        "latexml was not found on PATH. TeX parse jobs will fail with "
        "missing_dependency:latexml until LaTeXML is installed; Markdown imports, PDF save-only "
        "imports, and fixture tests still work.",
    ),
    "latexmlpost": (
        "latexmlpost is available for HTML generation after LaTeXML XML conversion.",
        "latexmlpost was not found on PATH. TeX parse jobs need both latexml and latexmlpost; "
        "run `bilin doctor` after installing LaTeXML to confirm the parser path.",
    ),
    "pandoc": (
        "pandoc is available for future document conversion helpers.",
        "pandoc was not found on PATH. Current MVP parsing does not fall back to pandoc, so this "
        "only limits optional conversion workflows.",
    ),
    "tectonic": (
        "tectonic is available for future controlled TeX rendering helpers.",
        "tectonic was not found on PATH. Code-generated figures can keep structured fallback "
        "records, but controlled rendering may be unavailable.",
    ),
    "pdflatex": (
        "pdflatex is available for optional TeX rendering helpers.",
        "pdflatex was not found on PATH. Optional controlled rendering paths may degrade.",
    ),
    "magick": (
        "ImageMagick is available for optional asset conversion.",
        "magick was not found on PATH. Existing PNG/JPEG/SVG assets still display, but EPS/PDF "
        "asset conversion to web images may degrade.",
    ),
    "gs": (
        "Ghostscript is available for optional PDF/EPS asset conversion.",
        "gs was not found on PATH. EPS/PDF asset conversion may degrade when ImageMagick needs "
        "Ghostscript.",
    ),
    "pdfinfo": (
        "pdfinfo is available for future PDF metadata checks.",
        "pdfinfo was not found on PATH. PDF files can still be saved into bundles, but PDF "
        "metadata diagnostics may be unavailable.",
    ),
}


def detect_version(path: str) -> str | None:
    command_name = path.rsplit("/", 1)[-1]
    version_args = ((path, "-v"),) if command_name == "pdfinfo" else ()
    for args in (*version_args, (path, "--version"), (path, "-version")):
        try:
            completed = subprocess.run(
                args,
                check=False,
                capture_output=True,
                text=True,
                timeout=2,
            )
        except (OSError, subprocess.TimeoutExpired):
            continue
        output = (completed.stdout or completed.stderr).strip()
        if output and completed.returncode == 0:
            return output.splitlines()[0][:200]
    return None


def build_doctor_report(resolver: Resolver | None = None) -> DoctorReport:
    settings = get_settings()
    command_resolver = resolver or shutil.which
    keychain_is_available, keychain_path, keychain_message = keychain_status_message()
    capabilities: list[DoctorCapability] = [
        DoctorCapability(
            tool_name="macos-keychain",
            status=DoctorCapabilityStatus.available
            if keychain_is_available
            else DoctorCapabilityStatus.missing,
            detected_version=None,
            path=keychain_path,
            level=DoctorCapabilityLevel.optional,
            message=keychain_message,
        )
    ]
    for tool_name, level in TOOLS:
        path = command_resolver(tool_name)
        available_message, missing_message = TOOL_MESSAGES[tool_name]
        if path:
            capabilities.append(
                DoctorCapability(
                    tool_name=tool_name,
                    status=DoctorCapabilityStatus.available,
                    detected_version=detect_version(path),
                    path=path,
                    level=level,
                    message=available_message,
                )
            )
        else:
            capabilities.append(
                DoctorCapability(
                    tool_name=tool_name,
                    status=DoctorCapabilityStatus.missing,
                    detected_version=None,
                    path=None,
                    level=level,
                    message=missing_message,
                )
            )
    return DoctorReport(bilin_home=str(settings.bilin_home), capabilities=capabilities)
