CREATE TABLE IF NOT EXISTS reading_progress (
  article_revision_id TEXT PRIMARY KEY,
  active_block_uid TEXT,
  segment_count INTEGER NOT NULL DEFAULT 0,
  block_seconds_json TEXT NOT NULL DEFAULT '{}',
  total_seconds INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id) ON DELETE CASCADE
);
