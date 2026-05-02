CREATE TABLE IF NOT EXISTS schema_migrations (
  version TEXT PRIMARY KEY,
  applied_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS article_families (
  id TEXT PRIMARY KEY,
  source TEXT NOT NULL,
  external_id TEXT NOT NULL,
  title TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  UNIQUE(source, external_id)
);

CREATE TABLE IF NOT EXISTS article_revisions (
  id TEXT PRIMARY KEY,
  family_id TEXT NOT NULL,
  version TEXT NOT NULL,
  bundle_path TEXT NOT NULL,
  status TEXT NOT NULL,
  manifest_version INTEGER NOT NULL DEFAULT 1,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(family_id) REFERENCES article_families(id)
);

CREATE TABLE IF NOT EXISTS blocks (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  block_uid TEXT NOT NULL,
  structural_path TEXT NOT NULL,
  block_type TEXT NOT NULL,
  parent_uid TEXT,
  content_hash TEXT NOT NULL,
  context_hash TEXT,
  source_markdown TEXT NOT NULL,
  source_latex TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id),
  UNIQUE(article_revision_id, block_uid)
);

CREATE TABLE IF NOT EXISTS translation_variants (
  id TEXT PRIMARY KEY,
  block_id TEXT NOT NULL,
  target_language TEXT NOT NULL,
  provider_profile_id TEXT,
  model TEXT,
  raw_markdown TEXT NOT NULL,
  render_ast_json TEXT,
  validation_status TEXT NOT NULL DEFAULT 'unchecked',
  glossary_version TEXT,
  is_default INTEGER NOT NULL DEFAULT 0,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(block_id) REFERENCES blocks(id)
);

CREATE TABLE IF NOT EXISTS glossary_terms (
  id TEXT PRIMARY KEY,
  scope TEXT NOT NULL,
  source_term TEXT NOT NULL,
  target_term TEXT NOT NULL,
  language_direction TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'candidate',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS chat_messages (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  source_refs_json TEXT NOT NULL DEFAULT '[]',
  external_refs_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id)
);

CREATE TABLE IF NOT EXISTS note_patches (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  status TEXT NOT NULL,
  title TEXT NOT NULL,
  patch_markdown TEXT NOT NULL,
  source_refs_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id)
);

CREATE TABLE IF NOT EXISTS assets (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  asset_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  source_path TEXT,
  web_path TEXT,
  caption TEXT,
  label TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id),
  UNIQUE(article_revision_id, asset_id)
);

