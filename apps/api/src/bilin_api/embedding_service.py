from __future__ import annotations

import hashlib
import json
import math
import re
from collections import Counter
from dataclasses import dataclass
from datetime import datetime
from uuid import uuid4

import aiosqlite

from bilin_api.article_store import ensure_library_database, list_blocks, search_blocks
from bilin_api.database import open_db, utc_now
from bilin_api.repositories import create_job
from bilin_api.schemas import (
    ArticleEmbeddingStatus,
    BlockEmbedding,
    DocumentBlock,
    EmbedArticleRequest,
    EmbedArticleResult,
    Job,
    JobType,
    Library,
)

LOCAL_EMBEDDING_PROVIDER = "local-hash"
LOCAL_EMBEDDING_MODEL = "hashing-64-v1"
LOCAL_EMBEDDING_DIMENSIONS = 64
TOKEN_RE = re.compile(r"[\w]+", flags=re.UNICODE)


@dataclass(frozen=True)
class HybridSearchMatch:
    block: DocumentBlock
    score: float
    fts_score: float | None = None
    vector_score: float | None = None
    retrieval_method: str = "hybrid"


async def build_article_embeddings(
    library: Library,
    revision_id: str,
    request: EmbedArticleRequest | None = None,
) -> EmbedArticleResult:
    active_request = request or EmbedArticleRequest()
    provider = active_request.provider
    model = active_request.model
    dimensions = dimensions_for_model(model)
    blocks = [
        block for block in await list_blocks(library, revision_id) if is_embedding_eligible(block)
    ]
    existing = await list_block_embeddings(library, revision_id, provider, model)
    existing_by_block_id = {embedding.block_id: embedding for embedding in existing}
    embedded_blocks = 0
    skipped_blocks = 0
    for block in blocks:
        current = existing_by_block_id.get(block.id)
        if (
            current is not None
            and not active_request.force
            and current.source_hash == block.content_hash
            and current.dimensions == dimensions
        ):
            skipped_blocks += 1
            continue
        await upsert_block_embedding(
            library=library,
            block=block,
            provider=provider,
            model=model,
            dimensions=dimensions,
            vector=embed_text(block.source_markdown, dimensions),
            metadata={"algorithm": "signed_hashing_bow", "source": "local"},
        )
        embedded_blocks += 1
    stale_deleted = await delete_stale_block_embeddings(
        library,
        revision_id,
        provider,
        model,
        {block.id for block in blocks},
    )
    return EmbedArticleResult(
        library_id=library.id,
        article_revision_id=revision_id,
        provider=provider,
        model=model,
        dimensions=dimensions,
        eligible_blocks=len(blocks),
        embedded_blocks=embedded_blocks,
        skipped_blocks=skipped_blocks,
        stale_blocks_deleted=stale_deleted,
    )


async def queue_article_embedding(
    library: Library,
    revision_id: str,
    request: EmbedArticleRequest | None = None,
) -> Job:
    active_request = request or EmbedArticleRequest()
    return await create_job(
        JobType.embed_article,
        {
            "library_id": library.id,
            "article_revision_id": revision_id,
            "request": active_request.model_dump(mode="json"),
        },
    )


async def get_article_embedding_status(
    library: Library,
    revision_id: str,
    request: EmbedArticleRequest | None = None,
) -> ArticleEmbeddingStatus:
    active_request = request or EmbedArticleRequest()
    dimensions = dimensions_for_model(active_request.model)
    blocks = [
        block for block in await list_blocks(library, revision_id) if is_embedding_eligible(block)
    ]
    block_hashes = {block.id: block.content_hash for block in blocks}
    embeddings = await list_block_embeddings(
        library,
        revision_id,
        active_request.provider,
        active_request.model,
    )
    current = [
        embedding
        for embedding in embeddings
        if block_hashes.get(embedding.block_id) == embedding.source_hash
        and embedding.dimensions == dimensions
    ]
    stale = len(embeddings) - len(current)
    updated_at = max((embedding.updated_at for embedding in current), default=None)
    return ArticleEmbeddingStatus(
        article_revision_id=revision_id,
        provider=active_request.provider,
        model=active_request.model,
        dimensions=dimensions,
        eligible_blocks=len(blocks),
        embedded_blocks=len(current),
        stale_blocks=stale,
        updated_at=updated_at,
    )


async def hybrid_search_blocks(
    library: Library,
    revision_id: str,
    query: str,
    limit: int = 8,
    request: EmbedArticleRequest | None = None,
) -> list[HybridSearchMatch]:
    active_request = request or EmbedArticleRequest()
    dimensions = dimensions_for_model(active_request.model)
    query_vector = embed_text(query, dimensions)
    if not any(query_vector):
        return []
    fts_matches = await search_blocks(library, revision_id, query, max(limit * 4, 20))
    vector_matches = await vector_search_blocks(
        library,
        revision_id,
        query_vector,
        max(limit * 4, 20),
        active_request,
    )
    combined: dict[str, HybridSearchMatch] = {}
    for rank, (block, fts_score) in enumerate(fts_matches, start=1):
        weight = block_type_search_weight(block)
        combined[block.block_uid] = HybridSearchMatch(
            block=block,
            score=-(weight * reciprocal_rank(rank)),
            fts_score=fts_score,
            retrieval_method="fts",
        )
    for rank, match in enumerate(vector_matches, start=1):
        fts_component = (
            -combined[match.block.block_uid].score if match.block.block_uid in combined else 0.0
        )
        vector_component = max(match.vector_score or 0.0, 0.0) + reciprocal_rank(rank)
        score = -(
            block_type_search_weight(match.block) * (0.65 * fts_component + 0.35 * vector_component)
        )
        combined[match.block.block_uid] = HybridSearchMatch(
            block=match.block,
            score=score,
            fts_score=combined.get(match.block.block_uid, match).fts_score,
            vector_score=match.vector_score,
            retrieval_method="hybrid",
        )
    return sorted(combined.values(), key=lambda item: item.score)[:limit]


async def vector_search_blocks(
    library: Library,
    revision_id: str,
    query_vector: list[float],
    limit: int,
    request: EmbedArticleRequest,
) -> list[HybridSearchMatch]:
    blocks = {block.id: block for block in await list_blocks(library, revision_id)}
    matches: list[HybridSearchMatch] = []
    embeddings = await list_block_embeddings(
        library,
        revision_id,
        request.provider,
        request.model,
    )
    for embedding in embeddings:
        block = blocks.get(embedding.block_id)
        if block is None or block.content_hash != embedding.source_hash:
            continue
        vector_score = cosine_similarity(
            query_vector,
            embedding.vector,
        ) * block_type_search_weight(block)
        if vector_score <= 0:
            continue
        matches.append(
            HybridSearchMatch(
                block=block,
                score=-vector_score,
                vector_score=vector_score,
                retrieval_method="vector",
            )
        )
    return sorted(matches, key=lambda item: item.score)[:limit]


async def upsert_block_embedding(
    *,
    library: Library,
    block: DocumentBlock,
    provider: str,
    model: str,
    dimensions: int,
    vector: list[float],
    metadata: dict[str, object] | None = None,
) -> BlockEmbedding:
    db_path = await ensure_library_database(library)
    now = utc_now()
    embedding_id = str(uuid4())
    async with open_db(db_path) as conn:
        await conn.execute(
            """
            INSERT INTO block_embeddings(
              id, article_revision_id, block_id, block_uid, provider, model,
              dimensions, source_hash, vector_json, metadata_json, created_at, updated_at
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(block_id, provider, model) DO UPDATE SET
              article_revision_id = excluded.article_revision_id,
              block_uid = excluded.block_uid,
              dimensions = excluded.dimensions,
              source_hash = excluded.source_hash,
              vector_json = excluded.vector_json,
              metadata_json = excluded.metadata_json,
              updated_at = excluded.updated_at
            """,
            (
                embedding_id,
                block.article_revision_id,
                block.id,
                block.block_uid,
                provider,
                model,
                dimensions,
                block.content_hash,
                json.dumps(vector),
                json.dumps(metadata or {}),
                now,
                now,
            ),
        )
        await conn.commit()
    embedding = await get_block_embedding(library, block.id, provider, model)
    if embedding is None:
        msg = "Created block embedding could not be read back"
        raise RuntimeError(msg)
    return embedding


async def get_block_embedding(
    library: Library,
    block_id: str,
    provider: str,
    model: str,
) -> BlockEmbedding | None:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT *
            FROM block_embeddings
            WHERE block_id = ? AND provider = ? AND model = ?
            """,
            (block_id, provider, model),
        )
        row = await cursor.fetchone()
    return block_embedding_from_row(row) if row else None


async def list_block_embeddings(
    library: Library,
    revision_id: str,
    provider: str,
    model: str,
) -> list[BlockEmbedding]:
    db_path = await ensure_library_database(library)
    async with open_db(db_path) as conn:
        cursor = await conn.execute(
            """
            SELECT *
            FROM block_embeddings
            WHERE article_revision_id = ? AND provider = ? AND model = ?
            ORDER BY block_uid
            """,
            (revision_id, provider, model),
        )
        rows = await cursor.fetchall()
    return [block_embedding_from_row(row) for row in rows]


async def delete_stale_block_embeddings(
    library: Library,
    revision_id: str,
    provider: str,
    model: str,
    valid_block_ids: set[str],
) -> int:
    embeddings = await list_block_embeddings(library, revision_id, provider, model)
    stale_ids = [
        embedding.id for embedding in embeddings if embedding.block_id not in valid_block_ids
    ]
    if not stale_ids:
        return 0
    db_path = await ensure_library_database(library)
    placeholders = ",".join("?" for _ in stale_ids)
    async with open_db(db_path) as conn:
        await conn.execute(
            f"DELETE FROM block_embeddings WHERE id IN ({placeholders})",
            tuple(stale_ids),
        )
        await conn.commit()
    return len(stale_ids)


def embed_text(text: str, dimensions: int = LOCAL_EMBEDDING_DIMENSIONS) -> list[float]:
    counts = Counter(tokenize(text))
    vector = [0.0] * dimensions
    for token, count in counts.items():
        digest = hashlib.sha256(token.encode("utf-8")).digest()
        index = int.from_bytes(digest[:4], "big") % dimensions
        sign = -1.0 if digest[4] & 1 else 1.0
        vector[index] += sign * (1.0 + math.log(count))
    norm = math.sqrt(sum(value * value for value in vector))
    if norm == 0:
        return vector
    return [value / norm for value in vector]


def cosine_similarity(left: list[float], right: list[float]) -> float:
    if len(left) != len(right):
        return 0.0
    return sum(
        left_value * right_value for left_value, right_value in zip(left, right, strict=True)
    )


def tokenize(text: str) -> list[str]:
    return [token.casefold() for token in TOKEN_RE.findall(text) if len(token) > 1]


def is_embedding_eligible(block: DocumentBlock) -> bool:
    return bool(block.source_markdown.strip()) and block.block_type in {
        "paragraph",
        "section",
        "figure",
        "table",
        "equation",
    }


def block_type_search_weight(block: DocumentBlock) -> float:
    if block.block_type == "section":
        return 0.35
    return 1.0


def dimensions_for_model(model: str) -> int:
    if model == LOCAL_EMBEDDING_MODEL:
        return LOCAL_EMBEDDING_DIMENSIONS
    match = re.search(r"(\d+)", model)
    if match:
        return max(8, min(int(match.group(1)), 4096))
    return LOCAL_EMBEDDING_DIMENSIONS


def reciprocal_rank(rank: int) -> float:
    return 1.0 / (rank + 1)


def block_embedding_from_row(row: aiosqlite.Row) -> BlockEmbedding:
    return BlockEmbedding(
        id=row["id"],
        article_revision_id=row["article_revision_id"],
        block_id=row["block_id"],
        block_uid=row["block_uid"],
        provider=row["provider"],
        model=row["model"],
        dimensions=row["dimensions"],
        source_hash=row["source_hash"],
        vector=json.loads(row["vector_json"]),
        metadata=json.loads(row["metadata_json"]),
        created_at=datetime.fromisoformat(row["created_at"]),
        updated_at=datetime.fromisoformat(row["updated_at"]),
    )
