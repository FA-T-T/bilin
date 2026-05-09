CREATE TABLE IF NOT EXISTS reader_cards (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT NOT NULL,
  card_type TEXT NOT NULL,
  anchor_block_uid TEXT NOT NULL,
  anchor_text TEXT NOT NULL,
  canonical_key TEXT NOT NULL,
  abbreviation TEXT,
  full_form TEXT,
  title TEXT NOT NULL,
  body_markdown TEXT NOT NULL DEFAULT '',
  target_language TEXT NOT NULL,
  source_type TEXT NOT NULL,
  source_url TEXT,
  position TEXT NOT NULL DEFAULT 'right',
  status TEXT NOT NULL DEFAULT 'candidate',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_reader_cards_revision_block
ON reader_cards(article_revision_id, anchor_block_uid);

CREATE INDEX IF NOT EXISTS idx_reader_cards_canonical_language
ON reader_cards(canonical_key, target_language);

CREATE UNIQUE INDEX IF NOT EXISTS idx_reader_cards_revision_canonical_language
ON reader_cards(article_revision_id, canonical_key, target_language)
WHERE status != 'archived';
