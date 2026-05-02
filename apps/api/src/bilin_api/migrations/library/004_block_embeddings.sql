CREATE TABLE IF NOT EXISTS block_embeddings (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  block_id TEXT NOT NULL,
  block_uid TEXT NOT NULL,
  provider TEXT NOT NULL,
  model TEXT NOT NULL,
  dimensions INTEGER NOT NULL,
  source_hash TEXT NOT NULL,
  vector_json TEXT NOT NULL,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(block_id) REFERENCES blocks(id) ON DELETE CASCADE,
  UNIQUE(block_id, provider, model)
);

CREATE INDEX IF NOT EXISTS idx_block_embeddings_revision_provider
ON block_embeddings(article_revision_id, provider, model);
