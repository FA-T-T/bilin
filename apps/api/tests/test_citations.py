from __future__ import annotations

from pathlib import Path

import httpx
import pytest

from bilin_api.article_store import upsert_arxiv_revision
from bilin_api.citation_service import (
    clear_scholar_cache,
    extract_latexml_citations,
    lookup_citation_scholar,
    queue_citation_library_import,
)
from bilin_api.repositories import create_library, list_jobs
from bilin_api.schemas import CitationLibraryImportRequest, JobType, LibraryCreate

LATEXML_BIBLIOGRAPHY = """
<section id="bib" class="ltx_bibliography">
<ul class="ltx_biblist">
<li id="bib.bib1" class="ltx_bibitem">
<span class="ltx_tag ltx_role_refnum ltx_tag_bibitem">[1]</span>
<span class="ltx_bibblock">Jimmy Lei Ba, Jamie Ryan Kiros, and Geoffrey E Hinton.</span>
<span class="ltx_bibblock">Layer normalization.</span>
<span class="ltx_bibblock">
<span class="ltx_text ltx_font_italic">arXiv preprint arXiv:1607.06450</span>, 2016.
</span>
</li>
<li id="bib.bib2" class="ltx_bibitem">
<span class="ltx_tag ltx_role_refnum ltx_tag_bibitem">[2]</span>
<span class="ltx_bibblock">Dzmitry Bahdanau, Kyunghyun Cho, and Yoshua Bengio.</span>
<span class="ltx_bibblock">
Neural machine translation by jointly learning to align and translate.
</span>
<span class="ltx_bibblock">
<span class="ltx_text ltx_font_italic">CoRR</span>, abs/1409.0473, 2014.
</span>
</li>
</ul>
</section>
"""

ARXIV_SEARCH_RESPONSE = """<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <id>https://arxiv.org/abs/1409.0473v7</id>
    <updated>2016-05-19T00:00:00Z</updated>
    <published>2014-09-01T00:00:00Z</published>
    <title> Neural machine translation by jointly learning to align and translate </title>
    <summary> A compact abstract. </summary>
    <author><name>Dzmitry Bahdanau</name></author>
    <author><name>Kyunghyun Cho</name></author>
    <author><name>Yoshua Bengio</name></author>
  </entry>
</feed>
"""


def test_extract_latexml_citations() -> None:
    citations = extract_latexml_citations(LATEXML_BIBLIOGRAPHY)

    assert [citation.id for citation in citations] == ["bib.bib1", "bib.bib2"]
    assert citations[0].label == "1"
    assert citations[0].title == "Layer normalization"
    assert citations[0].authors == "Jimmy Lei Ba, Jamie Ryan Kiros, and Geoffrey E Hinton."
    assert citations[0].year == "2016"
    assert citations[0].arxiv_id == "1607.06450"
    assert citations[0].scholar_url.startswith("https://scholar.google.com/scholar?")


@pytest.mark.asyncio
async def test_lookup_citation_scholar_parses_first_result(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    clear_scholar_cache()
    library = await create_library(LibraryCreate(name="Citations", path=str(tmp_path / "library")))
    bundle_path = Path(library.path) / "articles" / "arxiv" / "2401.00001" / "v1"
    document_dir = bundle_path / "document"
    document_dir.mkdir(parents=True)
    (document_dir / "latexml.html").write_text(LATEXML_BIBLIOGRAPHY, encoding="utf-8")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00001",
        version="v1",
        title="Citation API",
        bundle_path=bundle_path,
        metadata={},
    )

    scholar_html = """
    <html><body>
      <div class="gs_r gs_or gs_scl">
        <div class="gs_ri">
          <h3 class="gs_rt">
            <a href="https://example.org/layer-normalization">Layer Normalization</a>
          </h3>
          <div class="gs_rs">A normalization method for deep networks.</div>
        </div>
      </div>
    </body></html>
    """

    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, request=request, text=scholar_html)
    )
    async with httpx.AsyncClient(transport=transport, follow_redirects=True) as client:
        result = await lookup_citation_scholar(
            library,
            revision.id,
            "bib.bib1",
            client=client,
        )

    assert result.status == "ok"
    assert result.first_result is not None
    assert result.first_result.title == "Layer Normalization"
    assert result.first_result.url == "https://example.org/layer-normalization"
    assert result.first_result.snippet == "A normalization method for deep networks."


@pytest.mark.asyncio
async def test_lookup_citation_scholar_falls_back_to_semantic_scholar(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    clear_scholar_cache()
    library = await create_library(
        LibraryCreate(name="Citation fallback", path=str(tmp_path / "library"))
    )
    bundle_path = Path(library.path) / "articles" / "arxiv" / "2401.00002" / "v1"
    document_dir = bundle_path / "document"
    document_dir.mkdir(parents=True)
    (document_dir / "latexml.html").write_text(LATEXML_BIBLIOGRAPHY, encoding="utf-8")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00002",
        version="v1",
        title="Citation fallback API",
        bundle_path=bundle_path,
        metadata={},
    )

    def handler(request: httpx.Request) -> httpx.Response:
        if request.url.host == "scholar.google.com":
            return httpx.Response(403, request=request)
        return httpx.Response(
            200,
            request=request,
            json={
                "data": [
                    {
                        "title": "Layer Normalization",
                        "url": "https://www.semanticscholar.org/paper/example",
                        "abstract": "A normalization method for deep networks.",
                        "paperId": "example",
                    }
                ]
            },
        )

    async with httpx.AsyncClient(
        transport=httpx.MockTransport(handler),
        follow_redirects=True,
    ) as client:
        result = await lookup_citation_scholar(
            library,
            revision.id,
            "bib.bib1",
            client=client,
        )

    assert result.status == "ok"
    assert result.message == "Google Scholar blocked preview; showing Semantic Scholar fallback."
    assert result.first_result is not None
    assert result.first_result.source == "semantic_scholar"
    assert result.first_result.title == "Layer Normalization"


@pytest.mark.asyncio
async def test_queue_citation_import_searches_arxiv_and_adds_import_job(
    bilin_home: Path,
    tmp_path: Path,
) -> None:
    library = await create_library(
        LibraryCreate(name="Citation import", path=str(tmp_path / "library"))
    )
    bundle_path = Path(library.path) / "articles" / "arxiv" / "2401.00003" / "v1"
    document_dir = bundle_path / "document"
    document_dir.mkdir(parents=True)
    (document_dir / "latexml.html").write_text(LATEXML_BIBLIOGRAPHY, encoding="utf-8")
    _, revision = await upsert_arxiv_revision(
        library,
        bare_id="2401.00003",
        version="v1",
        title="Citation import API",
        bundle_path=bundle_path,
        metadata={},
    )

    transport = httpx.MockTransport(
        lambda request: httpx.Response(200, request=request, text=ARXIV_SEARCH_RESPONSE)
    )
    async with httpx.AsyncClient(transport=transport) as client:
        result = await queue_citation_library_import(
            library,
            revision.id,
            "bib.bib2",
            CitationLibraryImportRequest(
                translate_after_import=True,
                provider_profile_id="provider-1",
                model="model-1",
            ),
            client=client,
        )

    assert result.candidate.arxiv_id == "1409.0473v7"
    assert result.candidate.source == "arxiv_search"
    assert result.translate_after_import is True
    assert result.job.type == JobType.import_arxiv
    assert result.job.payload["arxiv_id"] == "1409.0473v7"
    assert result.job.payload["source_citation_id"] == "bib.bib2"
    assert result.job.payload["translate_after_parse"] == {
        "target_language": "zh-CN",
        "provider_profile_id": "provider-1",
        "model": "model-1",
        "force": False,
        "block_uids": None,
        "custom_prompt": None,
    }

    jobs = await list_jobs()
    assert any(job.id == result.job.id for job in jobs)
