#!/usr/bin/env python3
"""Render the English migration manifest."""
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

import i18n

rows = json.loads(Path("rows.json").read_text(encoding="utf-8"))


def esc(s: str) -> str:
    return s.replace("|", "\\|")


def has_cjk(s: str) -> bool:
    return any("\u4e00" <= c <= "\u9fff" for c in s)


def note_en(s: str) -> str:
    return i18n.NOTES.get(s, s) if s else "—"


def tgt(s: str) -> str:
    if s == "—":
        return s
    t = i18n.TARGETS.get(s, s)
    if has_cjk(s):
        return esc(t)
    return f"`{esc(t)}`"


def table(subset, strip: str = "") -> list[str]:
    out = ["| Source | Action | Target | Note |", "| --- | --- | --- | --- |"]
    for r in subset:
        p = r["path"]
        disp = p[len(strip):] if strip and p.startswith(strip) else p
        out.append(f"| `{esc(disp)}` | {r['action']} | {tgt(r['target'])} | {esc(note_en(r['note']))} |")
    return out


def common_prefix(paths: list[str]) -> str:
    if len(paths) == 1:
        return paths[0]
    parts = [p.split("/") for p in paths]
    pre: list[str] = []
    for i in range(min(len(p) for p in parts)):
        if len({p[i] for p in parts}) == 1:
            pre.append(parts[0][i])
        else:
            break
    return "/".join(pre) + "/**" if pre else "**"


def grouped(subset) -> list[str]:
    groups: OrderedDict[tuple[str, str, str], list[str]] = OrderedDict()
    for r in subset:
        groups.setdefault((r["action"], r["target"], r["note"]), []).append(r["path"])
    out = ["| Rule | Files | Action | Target | Note |", "| --- | ---: | --- | --- | --- |"]
    rendered = [(common_prefix(p), len(p), a, t, n) for (a, t, n), p in groups.items()]
    rendered.sort(key=lambda x: (-len(x[0]), x[0]))
    for prefix, n, action, target, note in rendered:
        out.append(f"| `{esc(prefix)}` | {n} | {action} | {tgt(target)} | {esc(note_en(note))} |")
    return out


def sel(pred):
    return [r for r in rows if pred(r["path"])]


L: list[str] = []
w = L.append

w("# Migration manifest (source -> target)")
w("")
w("[中文](../../zh/architecture/migration_manifest.md) ｜ English")
w("")
w("This manifest implements [migration tasks, step 1](./migration_tasks.md): every Git-tracked file")
w("in the old repository is classified exactly once. Use it together with the")
w("[migration topology](./migration_topology.md), the [ownership map](./ownership_map.md) and the")
w("[package API contracts](./package_api_contracts.md).")
w("")
w("---")
w("")
w("## 1. Baseline")
w("")
w("| Item | Value |")
w("| --- | --- |")
w("| Source repository | `D:\\Development\\Workspace\\zeta` |")
w("| Final migration baseline SHA | `b5c2f3e8a9ac544e9832866e86ff633661c46053` |")
w("| Working tree | tracked clean (the only untracked path, `.workflow/feature/2026-08-18-PC端构建与版本检查/`, is explicitly excluded) |")
w(f"| Git-tracked files | **{len(rows):,}** |")
w("| Flutter / Dart | Flutter 3.44.4 stable / Dart 3.12.2 |")
w("| `pubspec.lock` SHA-256 | `70877b47b9097ac3449a5885b83faea073e4688a3c66187941f4bfd02728ec6f` |")
w("| Manifest generated | 2026-08-19 |")
w("| Target repository | `D:\\Development\\Workspace\\vgv\\zeta`, version `1.0.0+1` |")
w("")
w("> [!IMPORTANT]")
w("> **This is the final migration baseline after Step 0.** The five retired Cursor source, test, and")
w("> fixture files are gone from the Git index and therefore no longer appear in this manifest. The")
w("> migration must not switch to another legacy-repository commit.")
w("")
w("## 2. Action definitions")
w("")
w("| Action | Meaning | Verification |")
w("| --- | --- | --- |")
w("| `move` | Content unchanged, or only paths/links adjusted; comparable byte-for-byte or line-by-line | diff or checksum |")
w("| `rewrite` | Rewritten for the new architecture; functionally equivalent, structurally different | tests at the target cover the equivalent behaviour |")
w("| `regenerate` | Produced by tooling, never migrated by hand | the generating command is repeatable |")
w("| `delete` | Explicitly dropped; does not enter the new repository | the note column states the reason |")
w("| `out-of-scope` | Not a migration input | the note column states the exclusion basis |")
w("")
w("**One-to-many splits**: a target of `split`, or several targets joined by ` + `, means the source file")
w("is divided across multiple destinations. Every such file must have a per-item ruling in the")
w("[ownership map](./ownership_map.md); this manifest only records where the pieces go.")
w("")
w("## 3. Overview")
w("")

counts: dict[str, int] = {}
for r in rows:
    counts[r["action"]] = counts.get(r["action"], 0) + 1
w("| Action | Files | Share |")
w("| --- | ---: | ---: |")
for k in ["move", "rewrite", "regenerate", "delete", "out-of-scope"]:
    w(f"| `{k}` | {counts.get(k, 0)} | {counts.get(k, 0) / len(rows) * 100:.1f}% |")
w(f"| **Total** | **{len(rows)}** | **100%** |")
w("")

areas = [
    ("lib/", lambda p: p.startswith("lib/")),
    ("test/", lambda p: p.startswith("test/")),
    ("third_party/", lambda p: p.startswith("third_party/")),
    ("macos/ + windows/ + linux/", lambda p: p.split("/")[0] in ("macos", "windows", "linux")),
    ("assets/", lambda p: p.startswith("assets/")),
    ("tool/", lambda p: p.startswith("tool/")),
    ("docs/", lambda p: p.startswith("docs/")),
    (".github/", lambda p: p.startswith(".github/")),
    (".claude/ + .agents/ + .workflow/", lambda p: p.split("/")[0] in (".claude", ".agents", ".workflow")),
    ("root files", lambda p: "/" not in p),
]
w("| Area | Files | Actions |")
w("| --- | ---: | --- |")
covered = 0
for name, pred in areas:
    s = sel(pred)
    covered += len(s)
    c: dict[str, int] = {}
    for r in s:
        c[r["action"]] = c.get(r["action"], 0) + 1
    w(f"| `{name}` | {len(s)} | " + ", ".join(f"{k} {v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1])) + " |")
w(f"| **Total** | **{covered}** | coverage check: {covered} = {len(rows)} |")
w("")
assert covered == len(rows)

w("## 4. Differences from the topology document's counts")
w("")
w("[Migration topology §2](./migration_topology.md) counts filesystem entries; this manifest counts")
w("Git-tracked files, so the two differ:")
w("")
w("| Item | Topology §2 | This manifest (git-tracked) | Reason |")
w("| --- | ---: | ---: | --- |")
for plat, topo in [("macOS", 33), ("Windows", 69), ("Linux", 15)]:
    n = len(sel(lambda p, d=plat.lower(): p.startswith(d + "/")))
    reason = "match" if n == topo else "the difference is gitignored build output (plugin registrants, intermediates)"
    w(f"| {plat} | {topo} | {n} | {reason} |")
w(f"| assets | 13 | {len(sel(lambda p: p.startswith('assets/')))} | match |")
w("")
w("**Step 1 uses this manifest's git-tracked counting.** Untracked files are not migration inputs;")
w("generated output is handled as `regenerate`.")
w("")
w("---")
w("")
w("## 5. Scope rulings: two approved adjustments")
w("")
w("> **Status: ruled 2026-08-19, already reflected in [migration topology §1](./migration_topology.md)")
w("> and [task list §0](./migration_tasks.md).**")
w("")
w("Topology §1 originally listed all of `third_party/` as \"explicitly not migrated\", alongside")
w("`tool/packaging/`. On review, **the `third_party/` entry was too broad** and the `tool/` exclusion was")
w("imprecise. The two adjustments below must be formally registered in the")
w("[step 2 ADRs](./migration_tasks.md).")
w("")
w("### 5.1 `third_party/codex_app_server_schema/` is migrated")
w("")
n_tp = len(sel(lambda p: p.startswith("third_party/")))
w(f"- **Content**: {n_tp} files / 2.8 MB — the stable JSON Schema snapshot of Codex CLI `0.144.5`.")
w("- **Rationale**: the [Codex protocol doc](../protocols/codex_app_server_protocol.md) §2 defines it as")
w("  \"the human- and CI-diffable source of protocol truth\", and [step 12](./migration_tasks.md) requires")
w("  a contract test for `codex_app_server_client`. Dropping the snapshot removes that test's baseline.")
w("- **Ruling**: `move`, same path. It is not a runtime dependency, only a diffable protocol contract, and")
w("  it adds no build-time or runtime cost.")
w("- **Still excluded**: anything else that may later appear under `third_party/` stays out by default;")
w("  this ruling covers `codex_app_server_schema/` only.")
w("")
w("### 5.2 The smoke and gate scripts under `tool/` are migrated")
w("")
w("The exclusion narrows to `tool/packaging/`. Everything in that directory the acceptance criteria")
w("depend on directly is migrated:")
w("")
tool_rows = sorted(sel(lambda p: p.startswith("tool/")), key=lambda r: r["path"])
L.extend(table([r for r in tool_rows if r["action"] != "out-of-scope"]))
w("")
w("The five `smoke_*.py` scripts back [step 17](./migration_tasks.md) (\"read-only capability probe")
w("smoke against the real CLI\"), [step 33](./migration_tasks.md) (\"real Codex/Claude/Grok CLI session")
w("smoke\") and [step 36](./migration_tasks.md) (\"three-way real-CLI end-to-end smoke\"). Without them")
w("those three steps cannot be checked off.")
w("")
w("`check_localized_ui_strings.dart` and `localization_literal_allowlist.json` are the l10n literal gate,")
w("whose rules must be updated once [step 28](./migration_tasks.md) removes TextCatalog;")
w("`gen_codex_schema.{sh,ps1}` are the generation entry points for the §5.1 schema snapshot. The four")
w("`test_fast/test_full` scripts are replaced by the four VGV gates and marked `delete`.")
w("")
w("---")
w("")
w(f"## 6. `lib/`, file by file ({len(sel(lambda p: p.startswith('lib/')))})")
w("")
w("The `lib/src/` prefix is stripped. `packages/` and `lib/` targets are relative to the new repo root.")
w("")

lib_sections = [
    ("6.1 Entrypoint and app layer", lambda p: p == "lib/main.dart" or p.startswith("lib/src/app/")),
    ("6.2 core", lambda p: p.startswith("lib/src/core/")),
    ("6.3 agent · domain -> `agent_provider_contracts`", lambda p: p.startswith("lib/src/features/agent/domain/")),
    ("6.4 agent · data · transport and vendor clients", lambda p: p.startswith("lib/src/features/agent/data/datasources/")),
    ("6.5 agent · data · mappers", lambda p: p.startswith("lib/src/features/agent/data/mappers/")),
    ("6.6 agent · data · top level", lambda p: p.startswith("lib/src/features/agent/data/")),
    ("6.7 agent · application (highest risk, ruled file by file)", lambda p: p.startswith("lib/src/features/agent/application/")),
    ("6.8 agent · presentation", lambda p: p.startswith("lib/src/features/agent/presentation/")),
]
for feat in ["agent_management", "desktop_notifications", "ide_session", "project_threads",
             "settings", "usage_statistics", "workspace"]:
    lib_sections.append((f"6.x {feat}", lambda p, f=feat: p.startswith(f"lib/src/features/{f}/")))
lib_sections.append(("6.y ui", lambda p: p.startswith("lib/src/ui/")))

seen: set[str] = set()
idx = 8
for title, pred in lib_sections:
    s = sorted([r for r in sel(pred) if r["path"] not in seen], key=lambda r: r["path"])
    for r in s:
        seen.add(r["path"])
    if not s:
        continue
    if title.startswith(("6.x", "6.y")):
        idx += 1
        title = f"6.{idx} " + title.split(" ", 1)[1]
    w(f"### {title}")
    w("")
    L.extend(table(s, strip="lib/src/" if s[0]["path"] != "lib/main.dart" else "lib/"))
    w("")

lib_total = len(sel(lambda p: p.startswith("lib/")))
w(f"**`lib/` coverage check**: {len(seen)} / {lib_total}")
w("")
assert len(seen) == lib_total

w("---")
w("")
n_test = len(sel(lambda p: p.startswith("test/")))
w(f"## 7. `test/` ({n_test}) — grouped by rule")
w("")
w("Tests follow the ownership of what they test, so they are grouped by rule rather than listed one by")
w("one; each rule's hit count is verified and the totals equal every tracked file under `test/`.")
w("**Rules match longest-prefix-first**: the more specific rules near the top win, and the generic rules")
w("below only cover what is left.")
w("")
L.extend(grouped(sorted(sel(lambda p: p.startswith("test/")), key=lambda r: r["path"])))
w("")
w("> **Fixture ownership is a hard constraint.** [Step 17](./migration_tasks.md) requires \"existing")
w("> protocol fixtures assigned per package, with no cross-package test imports\". The four directories")
w("> under `test/fixtures/` — `agent_file_change_evidence`, `agent_permission_runtime_architecture`,")
w("> `agent_stream_identity` and `grok` — must be split per provider first, then migrate with their")
w("> vendor package. Shared harnesses are copied, never cross-imported.")
w("")
w("---")
w("")
nat = sorted(sel(lambda p: p.split("/")[0] in ("macos", "windows", "linux")), key=lambda r: r["path"])
w(f"## 8. Desktop platforms ({len(nat)})")
w("")
w("All three platforms unify on `cn.easii.zeta` / product name `Zeta`, with no identity suffix per flavor")
w("([step 3](./migration_tasks.md)). Generated plugin registrants can be regenerated; hand-written")
w("Runners, MethodChannels and icons must be confirmed individually.")
w("")
L.extend(table(nat))
w("")
w("> **Linux note**: the new repo has **no** `linux/` directory yet. The correct order is to run")
w("> `flutter create --platforms=linux .` to generate the scaffold first, then migrate the hand-written")
w("> parts above — do not copy the old repo's `linux/` wholesale, or Flutter version drift will break the build.")
w("")
w("---")
w("")
w("## 9. Assets, protocol snapshot and CI")
w("")
ass = sorted(sel(lambda p: p.startswith("assets/")), key=lambda r: r["path"])
w(f"### 9.1 `assets/` ({len(ass)})")
w("")
L.extend(table(ass))
w("")
w(f"### 9.2 `third_party/` ({n_tp})")
w("")
w("Migrated as a single unit with `move`, same path. Rationale in §5.1.")
w("")
w("| Rule | Files | Action | Target |")
w("| --- | ---: | --- | --- |")
w(f"| `third_party/codex_app_server_schema/**` | {n_tp} | move | `third_party/codex_app_server_schema/` |")
w("")
gh = sorted(sel(lambda p: p.startswith(".github/")), key=lambda r: r["path"])
w(f"### 9.3 `.github/` ({len(gh)})")
w("")
L.extend(table(gh))
w("")
w("---")
w("")
root = sorted(sel(lambda p: "/" not in p), key=lambda r: r["path"])
w(f"## 10. Root files ({len(root)})")
w("")
L.extend(table(root))
w("")
w("---")
w("")
docs = sorted(sel(lambda p: p.startswith("docs/")), key=lambda r: r["path"])
w(f"## 11. `docs/` ({len(docs)})")
w("")
L.extend(table(docs))
w("")
w("---")
w("")
oos = sel(lambda p: p.split("/")[0] in (".claude", ".agents", ".workflow"))
w(f"## 12. Explicitly excluded ({len(oos)})")
w("")
w("| Rule | Files | Basis |")
w("| --- | ---: | --- |")
for pre in [".claude/", ".agents/", ".workflow/", "tool/packaging/", "docs/history/", "docs/prompts/", "docs/reference/"]:
    s = sel(lambda p, q=pre: p.startswith(q))
    if s:
        w(f"| `{pre}**` | {len(s)} | {note_en(s[0]['note'])} |")
s = [r for r in rows if r["path"] == "skills-lock.json"]
w(f"| `skills-lock.json` | 1 | {note_en(s[0]['note'])} |")
w("")
w("In addition, the **untracked** `.workflow/feature/2026-08-18-PC端构建与版本检查/` is explicitly not a")
w("migration input per the [topology appendix](./migration_topology.md).")
w("")
w("---")
w("")
dels = sorted([r for r in rows if r["action"] == "delete"], key=lambda r: r["path"])
w(f"## 13. Deletion list ({len(dels)})")
w("")
w("Every entry states a reason and a verification method — a hard requirement of")
w("[step 1](./migration_tasks.md).")
w("")
L.extend(table(dels))
w("")
w("**Verification**: once migration completes, assert path non-existence in the new repo for every row")
w("above, and confirm the corresponding capability either has no UI entry point or is covered by a")
w("replacement. The TextCatalog deletions are additionally asserted by two")
w("[step 28](./migration_tasks.md) metrics: \"packages imports of `AppLocalizations` = 0\" and")
w("\"TextCatalog/Fallback remnants = 0\".")
w("")
w("---")
w("")
w("## 14. Closure check")
w("")
w("[Step 36](./migration_tasks.md) requires \"every file in the manifest closed out\". Closure means:")
w("")
w("| Action | Closure condition |")
w("| --- | --- |")
w("| `move` | the target path exists and the diff contains only link/path adjustments |")
w("| `rewrite` | the target path exists and tests there cover the source file's equivalent behaviour |")
w("| `regenerate` | the generating command runs repeatably in CI with stable output |")
w("| `delete` | the path does not exist in the new repo and the reason is recorded here |")
w("| `out-of-scope` | the path does not exist in the new repo |")
w("")
w("The generator should run in CI and assert, during P8, that this manifest's row count equals the final")
w("baseline's git-tracked file count with zero `UNCLASSIFIED` entries.")
w("")

Path(sys.argv[1]).write_text("\n".join(L) + "\n", encoding="utf-8")
print(f"wrote {sys.argv[1]}: {len(L)} lines")
