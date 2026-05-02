CREATE VIRTUAL TABLE IF NOT EXISTS block_fts USING fts5(
  block_id UNINDEXED,
  article_revision_id UNINDEXED,
  block_uid UNINDEXED,
  source_markdown,
  tokenize = 'unicode61'
);

INSERT INTO block_fts(block_id, article_revision_id, block_uid, source_markdown)
SELECT id, article_revision_id, block_uid, source_markdown
FROM blocks
WHERE source_markdown <> ''
  AND id NOT IN (SELECT block_id FROM block_fts);
