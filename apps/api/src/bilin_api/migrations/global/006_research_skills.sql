CREATE TABLE IF NOT EXISTS research_skills (
  id TEXT PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  source_path TEXT NOT NULL,
  cache_path TEXT,
  digest TEXT NOT NULL,
  digest_algorithm TEXT NOT NULL DEFAULT 'sha256',
  version TEXT,
  manifest_version INTEGER NOT NULL DEFAULT 1,
  install_status TEXT NOT NULL DEFAULT 'discovered',
  status TEXT NOT NULL DEFAULT 'metadata_only',
  enabled INTEGER NOT NULL DEFAULT 0,
  declared_permissions_json TEXT NOT NULL DEFAULT '[]',
  granted_permissions_json TEXT NOT NULL DEFAULT '[]',
  input_shape_json TEXT NOT NULL DEFAULT '{}',
  output_shape_json TEXT NOT NULL DEFAULT '{}',
  supported_tasks_json TEXT NOT NULL DEFAULT '[]',
  metadata_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_research_skills_status
ON research_skills(status, enabled, install_status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_research_skills_source_path
ON research_skills(source_path);
