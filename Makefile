SHELL := /bin/zsh

.PHONY: dev api worker web doctor generate-api-client test lint format-check typecheck release-package

dev:
	$(MAKE) -j3 api worker web

api:
	cd apps/api && uv run uvicorn bilin_api.main:app --reload --host 127.0.0.1 --port 8000

worker:
	cd apps/api && uv run bilin jobs run-worker

web:
	pnpm --filter @bilin/web dev --host 127.0.0.1 --port 5173

doctor:
	cd apps/api && uv run bilin doctor

generate-api-client:
	cd apps/api && uv run python -m bilin_api.openapi > ../../apps/web/openapi.json
	pnpm --filter @bilin/web generate-api-client

test:
	cd apps/api && uv run pytest
	pnpm --filter @bilin/web test:run

lint:
	cd apps/api && uv run ruff check .
	pnpm --filter @bilin/web lint

format-check:
	cd apps/api && uv run ruff format --check .
	pnpm --filter @bilin/web format:check

typecheck:
	cd apps/api && uv run basedpyright
	pnpm --filter @bilin/web typecheck

release-package:
	./scripts/package-release.sh
