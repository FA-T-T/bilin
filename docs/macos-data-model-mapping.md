# macOS Data Model Mapping

This document maps the native macOS app model to the existing Bilin web/API data model.
It is the contract for the first `BilinStore` implementation.

## Source Of Truth

The canonical backend models live in:

- `apps/api/src/bilin_api/schemas.py`
- `apps/api/src/bilin_api/repositories.py`
- `apps/api/src/bilin_api/article_store.py`
- `apps/api/src/bilin_api/migrations/global/*.sql`
- `apps/api/src/bilin_api/migrations/library/*.sql`

The web app consumes the generated OpenAPI schema through:

- `apps/web/src/api/generated/schema.ts`
- `apps/web/src/api/types.ts`

The native app should not infer fields from the React component tree. It should map from
the backend schema and library database.

## Database Boundary

Bilin currently has two SQLite scopes.

| Scope | Path | Purpose |
| --- | --- | --- |
| Global app database | `BILIN_HOME/bilin.sqlite` | Registered libraries, provider profiles, jobs, app settings, translation memory, note templates. |
| Per-library database | `<library.path>/library.sqlite` | Article families, revisions, blocks, translations, glossary terms, chat, notes, assets, cards, reading progress. |

The first native prototype may bypass the global database when a user directly opens a
library directory. In that path, `<library.path>/library.sqlite` is enough to list and
open articles.

## Core Entity Mapping

| macOS model | Existing source | Required fields | Optional / derived fields |
| --- | --- | --- | --- |
| `Library` | global `libraries`; backend `Library` | `id`, `name`, `path`, `status`, `created_at`, `updated_at` | `metadata_json` |
| `Article` | aggregate of `article_families` + `article_revisions` | `family.id`, `family.source`, `family.external_id`, `revision.id`, `revision.version`, `revision.bundle_path`, `revision.status` | `family.title`, `manifest`, block/asset counts, reading progress |
| `ArticleRevision` | library `article_revisions`; backend `ArticleRevision` | `id`, `family_id`, `version`, `bundle_path`, `status`, `manifest_version`, timestamps | `metadata_json` |
| `DocumentBlock` | library `blocks`; backend `DocumentBlock` | `id`, `article_revision_id`, `block_uid`, `structural_path`, `block_type`, `content_hash`, `source_markdown`, timestamps | `parent_uid`, `context_hash`, `source_latex`, `metadata_json` |
| `Translation` | library `translation_variants`; backend `TranslationVariant` | `id`, `block_id`, `target_language`, `raw_markdown`, `validation_status`, `is_default`, timestamps | `provider_profile_id`, `model`, `render_ast_json`, `glossary_version`, `metadata_json` |
| `Citation` | backend `CitationEntry`; extracted from bundle content | `id`, `label`, `title`, `raw_text`, `source`, `scholar_query`, `scholar_url` | `authors`, `year`, `arxiv_id`, `doi`, `url`, `citation_key`, `metadata` |
| `ReaderNote` | no exact existing table; closest are `reader_cards` and `note_patches` | note id, article revision id, title/body, timestamps | block anchor, source refs, accepted/rejected/generated state |
| `ArticleTask` | global `jobs` aggregated into `ArticleTaskProgress` | `id`, `status`, aggregate counts | `library_id`, `article_revision_id`, `article_title`, `source_id`, `stage`, `message`, `progress`, `error`, `updated_at` |

## Minimum Read Path

The first `BilinStore` implementation should support this read-only path:

1. Open a selected library directory.
2. Verify `<library.path>/library.sqlite` exists.
3. Read `schema_migrations` and reject unsupported schema versions.
4. Query article list by joining `article_revisions` to `article_families`.
5. Query `blocks` for a selected revision, sorted by `structural_path`.
6. Query `assets` for figure/table metadata.
7. Query `translation_variants` by `target_language`, joined to `blocks`.
8. Optionally query `reading_progress` for the selected revision.

The first write path should be notes or reading progress only. It must be protected by
schema compatibility checks.

## Citation Handling

Citation data is not a dedicated SQLite table today. Existing code extracts citation
entries from article bundle artifacts, especially LaTeXML HTML and BibTeX/BibLaTeX
sources. The macOS app should initially treat citation extraction as an import/bundle
adapter concern, not as a direct database query.

## Fixtures

Use repository fixtures before inventing new Swift-only payloads:

- `fixtures/golden/minimal-paper/expected.json`
- `fixtures/golden/public-arxiv-2408.13687/expected.json`
- `apps/web/tests/render.test.tsx` payloads for `documentPayload`, `translationsPayload`,
  `readerCardsPayload`, and `notePatchesPayload`

For native development, use the stable fixture that avoids TypeScript inline constants:

- `fixtures/native-reader/minimal-reader.json`

The native Swift package currently uses a smaller package-local fixture for the first
reader skeleton. That fixture is a bootstrap convenience, not the long-term compatibility
fixture.

## Swift Naming Guidance

Use compatibility-oriented names in `BilinStore` and reader-oriented aggregates in
`BilinReaderKit`.

- `Library` can remain simple in the prototype, but the store implementation should keep
  the backend fields intact.
- `Article` is a reader aggregate, not a database table. The store should preserve
  `ArticleFamily` and `ArticleRevision` internally.
- `DocumentBlock` must keep `block_uid` as the stable reader identity. Do not use list
  index as identity.
- Metadata should eventually decode into a JSON value type, not `[String: String]`.
  The current prototype uses strings only because the bundled fixture is intentionally
  narrow.
- String-backed enums need unknown fallback behavior. Database strings may expand before
  the macOS app is updated.
