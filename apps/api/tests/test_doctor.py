from __future__ import annotations

from pathlib import Path

from bilin_api.doctor import build_doctor_report
from bilin_api.schemas import DoctorCapabilityStatus


def test_doctor_reports_missing_tools_without_error(bilin_home: Path) -> None:
    report = build_doctor_report(resolver=lambda _tool: None)
    assert report.bilin_home == str(bilin_home)
    assert report.capabilities
    assert all(cap.status == DoctorCapabilityStatus.missing for cap in report.capabilities)
    by_tool = {cap.tool_name: cap for cap in report.capabilities}
    assert "TeX parse jobs will fail" in by_tool["latexml"].message
    assert "latexmlpost" in by_tool
    assert "EPS/PDF asset conversion" in by_tool["magick"].message
