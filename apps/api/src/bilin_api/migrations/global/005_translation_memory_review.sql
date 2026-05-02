ALTER TABLE translation_memory
ADD COLUMN review_status TEXT NOT NULL DEFAULT 'approved';

ALTER TABLE translation_memory
ADD COLUMN reuse_enabled INTEGER NOT NULL DEFAULT 1;

CREATE INDEX IF NOT EXISTS idx_translation_memory_review
ON translation_memory(review_status, reuse_enabled, target_language, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_translation_memory_reuse
ON translation_memory(source_hash, target_language, glossary_version, validation_status, review_status, reuse_enabled, updated_at DESC);
