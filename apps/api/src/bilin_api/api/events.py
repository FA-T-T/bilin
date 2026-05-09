from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from bilin_api.repositories import get_job_summary

router = APIRouter(tags=["events"])


@router.get("/events")
async def events(request: Request) -> StreamingResponse:
    async def stream():
        last_payload = ""
        while not await request.is_disconnected():
            summary = await get_job_summary()
            payload = json.dumps(summary.model_dump(mode="json"))
            if payload != last_payload:
                yield f"event: jobs\ndata: {payload}\n\n"
                last_payload = payload
            else:
                yield ": ping\n\n"
            await asyncio.sleep(1)

    return StreamingResponse(stream(), media_type="text/event-stream")
