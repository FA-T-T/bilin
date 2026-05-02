CREATE TABLE IF NOT EXISTS translation_memory (
  id TEXT PRIMARY KEY,
  source_hash TEXT NOT NULL,
  source_markdown TEXT NOT NULL,
  target_language TEXT NOT NULL,
  raw_markdown TEXT NOT NULL,
  provider_profile_id TEXT,
  model TEXT,
  validation_status TEXT NOT NULL DEFAULT 'ok',
  glossary_version TEXT,
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_translation_memory_lookup
ON translation_memory(source_hash, target_language, glossary_version, validation_status, updated_at DESC);
