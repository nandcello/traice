# Security

Traice reads your local Codex auth file and Cursor auth database and sends tokens only to their respective usage endpoints.

## Sensitive Data

- Do not commit `~/.codex/auth.json`.
- Do not commit Cursor's `state.vscdb` auth database.
- Do not paste tokens, account IDs, or raw auth files into issues.
- Do not add token values to logs, errors, crash reports, or screenshots.

## Reporting Issues

If you find a vulnerability, please report it privately to the maintainer instead of opening a public issue with exploit details. Include the affected version, macOS version, and reproduction steps that do not expose real tokens.
