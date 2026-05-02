ALTER TABLE provider_profiles
ADD COLUMN max_concurrent_requests INTEGER NOT NULL DEFAULT 1;

ALTER TABLE provider_profiles
ADD COLUMN requests_per_minute INTEGER;
