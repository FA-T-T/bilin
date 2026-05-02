from __future__ import annotations

import asyncio
import json

from fastapi import APIRouter, Request
from fastapi.responses import StreamingResponse

from bilin_api.repositories import list_jobs

router = APIRouter(tags=["events"])


@router.get("/events")
async def events(request: Request) -> StreamingResponse:
    async def stream():
        last_payload = ""
        while not await request.is_disconnected():
            jobs = await list_jobs()
            payload = json.dumps([job.model_dump(mode="json") for job in jobs])
            if payload != last_payload:
                yield f"event: jobs\ndata: {payload}\n\n"
                last_payload = payload
            else:
                yield ": ping\n\n"
            await asyncio.sleep(1)

    return StreamingResponse(stream(), media_type="text/event-stream")
