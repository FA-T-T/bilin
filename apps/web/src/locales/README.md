# Ilios UI Translation Entry

This folder is the community entry point for UI language contributions. The runtime source of truth is still `apps/web/src/i18n.ts`, because the app currently ships static TypeScript dictionaries, but new or partial community languages should begin here as JSON files before they are reviewed and promoted into the bundled dictionary.

Core languages are Simplified Chinese and English. They must stay complete and synchronized with product behavior. Japanese is experimental. Korean, Spanish, French, German, and future languages are community-maintained unless a maintainer explicitly promotes them.

Use `example.locale.json` as the starting shape. Keep `schema_version` at `1`, set `locale` to a BCP-47 tag such as `zh-Hant`, `pt-BR`, or `it`, set `tier` to `community`, and translate only the keys you can verify. Missing keys are allowed for community files because the app can fall back to English during review.

Message keys must remain stable. Do not rename keys to make one language prettier. If English wording is wrong, change the English source and the core Chinese source together, then update community files only where the existing translation has become misleading.

Product names follow the project contract. Chinese UI uses `衔牍`, English and most other languages use `Ilios`, and Japanese uses `理紐`. Technical identifiers such as CLI commands, package names, environment variables, and API fields remain `bilin`.

Before opening a translation contribution, run the web checks from the repository root when possible: `pnpm --dir apps/web typecheck`, `pnpm --dir apps/web lint`, and `pnpm --dir apps/web test:run -- tests/render.test.tsx`. If you only changed JSON examples and cannot run the full app, at least validate that the JSON parses.
