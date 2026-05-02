from __future__ import annotations

from fastapi import APIRouter, HTTPException, status

from bilin_api.repositories import (
    cancel_job,
    get_job,
    list_jobs,
    pause_job,
    resume_job,
)
from bilin_api.schemas import Job

router = APIRouter(prefix="/jobs", tags=["jobs"])


@router.get("", response_model=list[Job])
async def get_jobs() -> list[Job]:
    return await list_jobs()


@router.get("/{job_id}", response_model=Job)
async def get_job_by_id(job_id: str) -> Job:
    job = await get_job(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    return job


@router.post("/{job_id}/pause", response_model=Job)
async def pause_job_by_id(job_id: str) -> Job:
    job = await pause_job(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    return job


@router.post("/{job_id}/resume", response_model=Job)
async def resume_job_by_id(job_id: str) -> Job:
    job = await resume_job(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    return job


@router.post("/{job_id}/cancel", response_model=Job)
async def cancel_job_by_id(job_id: str) -> Job:
    job = await cancel_job(job_id)
    if job is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Job not found")
    return job
