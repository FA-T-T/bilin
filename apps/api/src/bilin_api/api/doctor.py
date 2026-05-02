from __future__ import annotations

from fastapi import APIRouter

from bilin_api.doctor import build_doctor_report
from bilin_api.schemas import DoctorReport

router = APIRouter(tags=["doctor"])


@router.get("/doctor", response_model=DoctorReport)
async def doctor() -> DoctorReport:
    return build_doctor_report()
