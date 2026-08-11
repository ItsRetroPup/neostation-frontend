@CLAUDE.md

## Local build secrets

When creating a NeoStation build, always pass `SCREENSCRAPER_DEV_ID` and
`SCREENSCRAPER_DEV_PASSWORD` from the local `.env` file as `--dart-define`
arguments. Never print their values in commands, logs, or responses.
