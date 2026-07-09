# Codex app-server JSON Schema snapshot

This directory holds the **pinned** JSON Schema export used by Zeta's Codex
adapter (`lib/src/features/agent`).

## Regenerate

```sh
# macOS / Linux / Git Bash
./tool/gen_codex_schema.sh

# Windows PowerShell
./tool/gen_codex_schema.ps1
```

Optional flags:

| Flag | Meaning |
| --- | --- |
| `--diff` / `-Diff` | Compare a fresh export to this snapshot without writing |
| `--force` / `-Force` | Allow regenerating when the local CLI version differs from `PINNED_VERSION` |
| `--experimental` / `-Experimental` | Pass `--experimental` to `codex app-server generate-json-schema` |

Point at a specific binary with `CODEX_BIN` or `-CodexBin`.

The generator drops `codex_app_server_protocol.v2.schemas.json` because the CLI
emits nondeterministic `definitions` key order; per-method files under `v2/`
already cover the same surface.

## Review workflow

1. Upgrade or select the target Codex CLI.
2. Run the generator with `--force` / `-Force` if the pin changes.
3. `git diff --stat third_party/codex_app_server_schema`
4. Update adapter code and `docs/codex_app_server_protocol.md` before merging.

Do not edit schema JSON by hand.
