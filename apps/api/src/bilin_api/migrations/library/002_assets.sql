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

