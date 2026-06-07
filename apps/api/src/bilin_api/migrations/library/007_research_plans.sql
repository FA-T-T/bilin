CREATE TABLE IF NOT EXISTS research_plans (
  id TEXT PRIMARY KEY,
  article_revision_id TEXT,
  skill_id TEXT,
  skill_slug TEXT,
  job_id TEXT,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'draft',
  title TEXT NOT NULL,
  topic TEXT,
  idempotency_key TEXT,
  payload_hash TEXT NOT NULL,
  candidate_papers_json TEXT NOT NULL DEFAULT '[]',
  reading_outline_json TEXT,
  payload_json TEXT NOT NULL DEFAULT '{}',
  preview_json TEXT,
  result_json TEXT,
  error_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_research_plans_idempotency_key
ON research_plans(idempotency_key)
WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_research_plans_revision_status
ON research_plans(article_revision_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_research_plans_skill_slug
ON research_plans(skill_slug, updated_at DESC);

CREATE TABLE IF NOT EXISTS agent_action_plans (
  id TEXT PRIMARY KEY,
  research_plan_id TEXT,
  article_revision_id TEXT,
  skill_id TEXT,
  skill_slug TEXT,
  job_id TEXT,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  idempotency_key TEXT,
  payload_hash TEXT NOT NULL,
  required_permissions_json TEXT NOT NULL DEFAULT '[]',
  payload_json TEXT NOT NULL DEFAULT '{}',
  preview_json TEXT,
  result_json TEXT,
  error_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  approved_at TEXT,
  started_at TEXT,
  finished_at TEXT,
  FOREIGN KEY(research_plan_id) REFERENCES research_plans(id) ON DELETE SET NULL,
  FOREIGN KEY(article_revision_id) REFERENCES article_revisions(id) ON DELETE SET NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_agent_action_plans_idempotency_key
ON agent_action_plans(idempotency_key)
WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_agent_action_plans_research_plan
ON agent_action_plans(research_plan_id, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_action_plans_revision_status
ON agent_action_plans(article_revision_id, status, updated_at DESC);

CREATE INDEX IF NOT EXISTS idx_agent_action_plans_kind_status
ON agent_action_plans(kind, status, updated_at DESC);

CREATE TABLE IF NOT EXISTS agent_action_plan_steps (
  id TEXT PRIMARY KEY,
  action_plan_id TEXT NOT NULL,
  position INTEGER NOT NULL,
  kind TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending',
  title TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  required_permissions_json TEXT NOT NULL DEFAULT '[]',
  payload_json TEXT NOT NULL DEFAULT '{}',
  preview_json TEXT,
  result_json TEXT,
  error_json TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(action_plan_id) REFERENCES agent_action_plans(id) ON DELETE CASCADE,
  UNIQUE(action_plan_id, position)
);

CREATE INDEX IF NOT EXISTS idx_agent_action_plan_steps_plan
ON agent_action_plan_steps(action_plan_id, position);

CREATE TABLE IF NOT EXISTS agent_action_plan_events (
  id TEXT PRIMARY KEY,
  action_plan_id TEXT NOT NULL,
  step_id TEXT,
  kind TEXT NOT NULL,
  status TEXT,
  message TEXT NOT NULL DEFAULT '',
  payload_json TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL,
  FOREIGN KEY(action_plan_id) REFERENCES agent_action_plans(id) ON DELETE CASCADE,
  FOREIGN KEY(step_id) REFERENCES agent_action_plan_steps(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_agent_action_plan_events_plan
ON agent_action_plan_events(action_plan_id, created_at ASC);

CREATE INDEX IF NOT EXISTS idx_agent_action_plan_events_status
ON agent_action_plan_events(status, created_at DESC);
