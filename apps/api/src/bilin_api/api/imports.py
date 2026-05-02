from __future__ import annotations

from fastapi import APIRouter, HTTPException, Query, Request, status

from bilin_api.article_store import resolve_library
from bilin_api.importer import import_local_file
from bilin_api.repositories import create_job
from bilin_api.schemas import ImportArxivRequest, ImportLocalKind, ImportLocalResult, Job, JobType

router = APIRouter(prefix="/libraries/{library_id}/imports", tags=["imports"])
LOCAL_IMPORT_KIND_QUERY = Query(...)
LOCAL_IMPORT_FILE_NAME_QUERY = Query(..., min_length=1)
LOCAL_IMPORT_PARSE_AFTER_QUERY = Query(True)


@router.post("/arxiv", response_model=Job, status_code=status.HTTP_201_CREATED)
async def import_arxiv(library_id: str, payload: ImportArxivRequest) -> Job:
    try:
        library = await resolve_library(library_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    return await create_job(
        JobType.import_arxiv,
        payload={
            "library_id": library.id,
            "arxiv_id": payload.arxiv_id,
            "version": payload.version,
            "download_pdf": payload.download_pdf,
            "parse_after_import": payload.parse_after_import,
        },
    )


@router.post("/file", response_model=ImportLocalResult, status_code=status.HTTP_201_CREATED)
async def import_file(
    library_id: str,
    request: Request,
    kind: ImportLocalKind = LOCAL_IMPORT_KIND_QUERY,
    file_name: str = LOCAL_IMPORT_FILE_NAME_QUERY,
    parse_after_import: bool = LOCAL_IMPORT_PARSE_AFTER_QUERY,
) -> ImportLocalResult:
    try:
        library = await resolve_library(library_id)
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)) from exc
    try:
        content = await request.body()
        return await import_local_file(
            library,
            file_name=file_name,
            content=content,
            kind=kind,
            parse_after_import=parse_after_import,
        )
    except ValueError as exc:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)) from exc
