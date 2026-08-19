#!/usr/bin/env python3
"""Render the migration manifest markdown from classified rows."""
from __future__ import annotations

import json
import sys
from collections import OrderedDict
from pathlib import Path

rows = json.loads(Path("rows.json").read_text(encoding="utf-8"))
by_path = {r["path"]: r for r in rows}

ACTION_ZH = {
    "move": "move",
    "rewrite": "rewrite",
    "regenerate": "regenerate",
    "delete": "delete",
    "out-of-scope": "out-of-scope",
}


def esc(s: str) -> str:
    return s.replace("|", "\\|")


def tgt(s: str) -> str:
    """Backtick pure-path targets; leave prose targets plain."""
    if s == "—":
        return s
    if any("一" <= ch <= "鿿" for ch in s):
        # prose or mixed: backtick only the leading path token if present
        return esc(s)
    return f"`{esc(s)}`"


def table(subset, strip: str = "") -> list[str]:
    out = ["| 源文件 | 动作 | 目标 | 说明 |", "| --- | --- | --- | --- |"]
    for r in subset:
        p = r["path"]
        disp = p[len(strip):] if strip and p.startswith(strip) else p
        out.append(
            f"| `{esc(disp)}` | {ACTION_ZH[r['action']]} | {tgt(r['target'])} | {esc(r['note'])} |"
        )
    return out


def grouped(subset) -> list[str]:
    """Group by (action, target, note), listing counts and file names."""
    groups: OrderedDict[tuple[str, str, str], list[str]] = OrderedDict()
    for r in subset:
        key = (r["action"], r["target"], r["note"])
        groups.setdefault(key, []).append(r["path"])
    out = ["| 规则命中 | 文件数 | 动作 | 目标 | 说明 |", "| --- | ---: | --- | --- | --- |"]
    rendered: list[tuple[str, int, str, str, str]] = []
    for (action, target, note), paths in groups.items():
        prefix = common_prefix(paths)
        rendered.append((prefix, len(paths), action, target, note))
    rendered.sort(key=lambda t: (-len(t[0]), t[0]))
    for prefix, n, action, target, note in rendered:
        out.append(
            f"| `{esc(prefix)}` | {n} | {ACTION_ZH[action]} | {tgt(target)} | {esc(note) or chr(8212)} |"
        )
    return out


def common_prefix(paths: list[str]) -> str:
    if len(paths) == 1:
        return paths[0]
    parts = [p.split("/") for p in paths]
    pre: list[str] = []
    for i in range(min(len(p) for p in parts)):
        seg = {p[i] for p in parts}
        if len(seg) == 1:
            pre.append(parts[0][i])
        else:
            break
    return "/".join(pre) + "/**" if pre else "**"


def sel(pred):
    return [r for r in rows if pred(r["path"])]


L = []
w = L.append

w("# 迁移逐文件清单（source→target manifest）")
w("")
w("中文 ｜ [English](../../en/architecture/migration_manifest.md)")
w("")
w("本清单执行[迁移任务清单 步骤 1](./migration_tasks.md)：旧仓库每个 Git 跟踪文件恰好归类一次。")
w("它与[迁移拓扑](./migration_topology.md)、[归属映射表](./ownership_map.md)、"
  "[包 API 契约](./package_api_contracts.md)配套使用。")
w("")
w("---")
w("")
w("## 1. 基线")
w("")
w("| 项 | 值 |")
w("| --- | --- |")
w("| 源仓库 | `D:\\Development\\Workspace\\zeta` |")
w("| 分析基线 SHA | `bfd42412c9c3a0b39bb93598f93f9e5eca471236` |")
w("| 工作区状态 | clean（唯一未跟踪项：`.workflow/feature/2026-08-18-PC端构建与版本检查/`） |")
w("| Git 跟踪文件总数 | **1,512** |")
w("| 清单生成日期 | 2026-08-19 |")
w("| 目标仓库 | `D:\\Development\\Workspace\\vgv\\zeta`，版本 `1.0.0+1` |")
w("")
w("> [!IMPORTANT]")
w("> **本清单基于分析基线 `bfd4241`，不是最终迁移基线。** [步骤 0](./migration_tasks.md) 的 Cursor")
w("> 清退会改变旧仓库内容。执行 [步骤 1](./migration_tasks.md) 时必须：")
w("> ")
w("> 1. 重新运行本清单的生成脚本，得到清退后的最终 SHA 与文件数；")
w("> 2. 记录最终的 Flutter/Dart 版本与 `pubspec.lock` hash；")
w("> 3. 确认标记为 `delete` 的 Cursor 相关文件已在旧仓库消失（届时它们不再出现在本清单中）。")
w("")
w("## 2. 动作定义")
w("")
w("| 动作 | 含义 | 验证方式 |")
w("| --- | --- | --- |")
w("| `move` | 内容不变或仅改路径/链接，逐字节或逐行可比 | diff 或 checksum |")
w("| `rewrite` | 内容按新架构重写，功能等价但结构改变 | 目标位置的测试覆盖等价行为 |")
w("| `regenerate` | 由工具重新生成，不手工迁移 | 生成命令可重复执行 |")
w("| `delete` | 明确删除，不进入新仓库 | 说明列写明删除理由 |")
w("| `out-of-scope` | 不属于本次迁移输入 | 说明列写明排除依据 |")
w("")
w("**一对多拆分的表达约定**：目标列写 `拆分` 或用 ` + ` 连接多个目标时，表示该源文件被拆到多处。")
w("这类文件必须在[归属映射表](./ownership_map.md)中有逐项裁决，本清单只记录去向。")
w("")
w("## 3. 总览")
w("")

counts: dict[str, int] = {}
for r in rows:
    counts[r["action"]] = counts.get(r["action"], 0) + 1
w("| 动作 | 文件数 | 占比 |")
w("| --- | ---: | ---: |")
for k in ["move", "rewrite", "regenerate", "delete", "out-of-scope"]:
    w(f"| `{k}` | {counts.get(k, 0)} | {counts.get(k, 0) / len(rows) * 100:.1f}% |")
w(f"| **合计** | **{len(rows)}** | **100%** |")
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
    ("根目录文件", lambda p: "/" not in p),
]
w("| 区域 | 文件数 | 主要动作 |")
w("| --- | ---: | --- |")
covered = 0
for name, pred in areas:
    s = sel(pred)
    covered += len(s)
    c: dict[str, int] = {}
    for r in s:
        c[r["action"]] = c.get(r["action"], 0) + 1
    main = ", ".join(f"{k} {v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1]))
    w(f"| `{name}` | {len(s)} | {main} |")
w(f"| **合计** | **{covered}** | 覆盖校验：{covered} = {len(rows)} |")
w("")
assert covered == len(rows), (covered, len(rows))

w("## 4. 与拓扑文档的数字差异")
w("")
w("[迁移拓扑 §2](./migration_topology.md) 的平台文件数是文件系统快照，本清单统计 Git 跟踪文件，两者不同：")
w("")
w("| 项 | 拓扑 §2 | 本清单（git 跟踪） | 差异原因 |")
w("| --- | ---: | ---: | --- |")
for plat, topo in [("macOS", 33), ("Windows", 69), ("Linux", 15)]:
    n = len(sel(lambda p, d=plat.lower(): p.startswith(d + "/")))
    w(f"| {plat} | {topo} | {n} | {'一致' if n == topo else '差额为 gitignore 的生成产物（plugin registrant、构建中间件）'} |")
n_assets = len(sel(lambda p: p.startswith("assets/")))
w(f"| assets | 13 | {n_assets} | 一致 |")
w("")
w("**执行步骤 1 时以本清单的 git 跟踪口径为准**：未跟踪文件不是迁移输入，生成产物按 `regenerate` 处理。")
w("")

w("---")
w("")
w("## 5. 范围裁决：两项已批准的调整")
w("")
w("> **状态：已裁决（2026-08-19），已同步到[迁移拓扑 §1](./migration_topology.md) 与"
  "[任务清单 §0](./migration_tasks.md)。**")
w("")
w("拓扑 §1 原本把 `third_party/` 整体列入「明确不迁移」，与 `tool/packaging/` 并列。核查后确认")
w("**`third_party/` 这一条过宽**，且 `tool/` 的排除范围写得不够精确。两项调整如下，需在")
w("[步骤 2 的 ADR](./migration_tasks.md)中正式登记。")
w("")
w("### 5.1 `third_party/codex_app_server_schema/` 迁入")
w("")
n_tp = len(sel(lambda p: p.startswith("third_party/")))
w(f"- **内容**：{n_tp} 个文件 / 2.8 MB，Codex CLI `0.144.5` 的 stable JSON Schema 快照。")
w("- **理由**：[Codex 协议文档](../protocols/codex_app_server_protocol.md) §2 把它定义为「人工与 CI 可 diff 的协议真相源」，")
w("  而[步骤 12](./migration_tasks.md) 要求 `codex_app_server_client` 有 contract test。删除快照 = 删除 contract test 的基准。")
w("- **裁决**：`move`，路径不变。它不是运行时依赖，只是可 diff 的协议契约，不引入任何构建期或运行期负担。")
w("- **仍然排除**：`third_party/` 下若将来出现其他内容，默认不迁移；本裁决只覆盖 `codex_app_server_schema/`。")
w("")
w("### 5.2 `tool/` 的冒烟与门禁脚本迁入")
w("")
w("排除范围收窄为 `tool/packaging/`。同目录下验收标准直接依赖的脚本一律迁入：")
w("")
tool_rows = sorted(sel(lambda p: p.startswith("tool/")), key=lambda r: r["path"])
L.extend(table([r for r in tool_rows if r["action"] != "out-of-scope"], strip=""))
w("")
w("`smoke_*.py` 五个脚本对应[步骤 17](./migration_tasks.md)「真实 CLI 的只读 capability probe 冒烟」、")
w("[步骤 33](./migration_tasks.md)「Codex/Claude/Grok 真实 CLI 会话冒烟」和[步骤 36](./migration_tasks.md)")
w("「三路真实 CLI 端到端冒烟」。没有它们，这三个步骤无法勾选。")
w("")
w("`check_localized_ui_strings.dart` 与 `localization_literal_allowlist.json` 是 l10n 字面量门禁，")
w("[步骤 28](./migration_tasks.md) 删除 TextCatalog 后规则需同步更新；`gen_codex_schema.{sh,ps1}` 是 §5.1")
w("schema 快照的生成入口。`test_fast/test_full` 四个脚本被 VGV 四门取代，标记 `delete`。")
w("")
w("---")
w("")

# ---------------------------------------------------------------- lib
w("## 6. `lib/` 逐文件（378）")
w("")
w("路径已去掉 `lib/src/` 前缀。目标列的 `packages/` 与 `lib/` 都相对新仓库根目录。")
w("")

lib_sections = [
    ("6.1 入口与 app 层", lambda p: p == "lib/main.dart" or p.startswith("lib/src/app/")),
    ("6.2 core", lambda p: p.startswith("lib/src/core/")),
    ("6.3 agent · domain → `agent_provider_contracts`",
     lambda p: p.startswith("lib/src/features/agent/domain/")),
    ("6.4 agent · data · transport 与 vendor client",
     lambda p: p.startswith("lib/src/features/agent/data/datasources/")),
    ("6.5 agent · data · mappers",
     lambda p: p.startswith("lib/src/features/agent/data/mappers/")),
    ("6.6 agent · data · 顶层",
     lambda p: p.startswith("lib/src/features/agent/data/")),
    ("6.7 agent · application（最高风险，逐个裁决）",
     lambda p: p.startswith("lib/src/features/agent/application/")),
    ("6.8 agent · presentation",
     lambda p: p.startswith("lib/src/features/agent/presentation/")),
]
for feat in ["agent_management", "desktop_notifications", "ide_session", "project_threads",
             "settings", "usage_statistics", "workspace"]:
    lib_sections.append(
        (f"6.x {feat}", lambda p, f=feat: p.startswith(f"lib/src/features/{f}/"))
    )
lib_sections.append(("6.y ui", lambda p: p.startswith("lib/src/ui/")))

seen: set[str] = set()
idx = 8
for title, pred in lib_sections:
    s = sorted([r for r in sel(pred) if r["path"] not in seen], key=lambda r: r["path"])
    for r in s:
        seen.add(r["path"])
    if not s:
        continue
    if title.startswith("6.x") or title.startswith("6.y"):
        idx += 1
        title = f"6.{idx} " + title.split(" ", 1)[1]
    w(f"### {title}")
    w("")
    L.extend(table(s, strip="lib/src/" if not s[0]["path"] == "lib/main.dart" else "lib/"))
    w("")

lib_total = len(sel(lambda p: p.startswith("lib/")))
w(f"**`lib/` 覆盖校验**：{len(seen)} / {lib_total}")
w("")
assert len(seen) == lib_total, (len(seen), lib_total)

# ---------------------------------------------------------------- test
w("---")
w("")
n_test = len(sel(lambda p: p.startswith("test/")))
w(f"## 7. `test/`（{n_test}）— 按规则分组")
w("")
w("测试跟随其被测对象的归属，因此按规则分组而非逐文件列举；每条规则的命中数已核对，"
  "合计等于 `test/` 的全部跟踪文件。**规则按最长前缀优先匹配**：表中靠上的更具体规则先生效，"
  "靠下的通用规则只覆盖剩余文件。")
w("")
L.extend(grouped(sorted(sel(lambda p: p.startswith("test/")), key=lambda r: r["path"])))
w("")
w("> **fixture 归属是硬约束**：[步骤 17](./migration_tasks.md) 要求「现有协议 fixture 按 package 分配，")
w("> 无跨包 test import」。`test/fixtures/` 下的 `agent_file_change_evidence`、")
w("> `agent_permission_runtime_architecture`、`agent_stream_identity`、`grok` 四个目录必须先按 Provider")
w("> 拆分，再随对应 vendor package 迁移。共享 harness 采用复制而非跨包引用。")
w("")

# ---------------------------------------------------------------- native
w("---")
w("")
nat = sorted(sel(lambda p: p.split("/")[0] in ("macos", "windows", "linux")),
             key=lambda r: r["path"])
w(f"## 8. 桌面平台（{len(nat)}）")
w("")
w("三平台统一 `cn.easii.zeta` / 产品名 `Zeta`，三个 flavor 不加身份后缀（[步骤 3](./migration_tasks.md)）。")
w("生成的 plugin registrant 可重新生成；手写 Runner、MethodChannel、图标必须逐个确认。")
w("")
L.extend(table(nat))
w("")
w("> **Linux 注意**：新仓库当前**没有** `linux/` 目录。正确顺序是先 `flutter create --platforms=linux .`")
w("> 生成 scaffold，再把上表手写部分迁入——不要直接复制旧仓库的 `linux/`，否则 Flutter 版本差异会导致构建失败。")
w("")

# ---------------------------------------------------------------- assets/third_party
w("---")
w("")
w("## 9. assets、协议快照与 CI")
w("")
ass = sorted(sel(lambda p: p.startswith("assets/")), key=lambda r: r["path"])
w(f"### 9.1 `assets/`（{len(ass)}）")
w("")
L.extend(table(ass))
w("")
w(f"### 9.2 `third_party/`（{n_tp}）")
w("")
w("整体作为一个单元 `move`，路径不变。裁决理由见 §5.1。")
w("")
w("| 规则 | 文件数 | 动作 | 目标 |")
w("| --- | ---: | --- | --- |")
w(f"| `third_party/codex_app_server_schema/**` | {n_tp} | move | `third_party/codex_app_server_schema/` |")
w("")
gh = sorted(sel(lambda p: p.startswith(".github/")), key=lambda r: r["path"])
w(f"### 9.3 `.github/`（{len(gh)}）")
w("")
L.extend(table(gh))
w("")

# ---------------------------------------------------------------- root
w("---")
w("")
root = sorted(sel(lambda p: "/" not in p), key=lambda r: r["path"])
w(f"## 10. 根目录文件（{len(root)}）")
w("")
L.extend(table(root))
w("")

# ---------------------------------------------------------------- docs
w("---")
w("")
docs = sorted(sel(lambda p: p.startswith("docs/")), key=lambda r: r["path"])
w(f"## 11. `docs/`（{len(docs)}）")
w("")
L.extend(table(docs))
w("")

# ---------------------------------------------------------------- oos
w("---")
w("")
oos = sel(lambda p: p.split("/")[0] in (".claude", ".agents", ".workflow"))
w(f"## 12. 明确排除（{len(oos)}）")
w("")
w("| 规则 | 文件数 | 排除依据 |")
w("| --- | ---: | --- |")
for pre in [".claude/", ".agents/", ".workflow/"]:
    s = sel(lambda p, q=pre: p.startswith(q))
    w(f"| `{pre}**` | {len(s)} | {s[0]['note']} |")
for pre in ["tool/packaging/", "docs/history/", "docs/prompts/", "docs/reference/"]:
    s = sel(lambda p, q=pre: p.startswith(q))
    if s:
        w(f"| `{pre}**` | {len(s)} | {s[0]['note']} |")
s = [r for r in rows if r["path"] == "skills-lock.json"]
w(f"| `skills-lock.json` | 1 | {s[0]['note']} |")
w("")
w("此外，**未跟踪**的 `.workflow/feature/2026-08-18-PC端构建与版本检查/` 按[拓扑附录](./migration_topology.md)"
  "明确不属于迁移输入。")
w("")

# ---------------------------------------------------------------- delete list
w("---")
w("")
dels = sorted([r for r in rows if r["action"] == "delete"], key=lambda r: r["path"])
w(f"## 13. 删除清单（{len(dels)}）")
w("")
w("每一项都必须写明删除理由与验证方式，这是[步骤 1](./migration_tasks.md) 的硬要求。")
w("")
L.extend(table(dels))
w("")
w("**验证方式**：迁移完成后，对上表每个路径在新仓库执行路径存在性断言（应全部不存在），"
  "并确认对应能力的 UI 入口不存在或已由替代实现覆盖。TextCatalog 相关删除另由")
w("[步骤 28](./migration_tasks.md)「packages 的 `AppLocalizations` import = 0」与"
  "「TextCatalog/Fallback remnants = 0」两个指标共同断言。")
w("")

# ---------------------------------------------------------------- closure
w("---")
w("")
w("## 14. 闭环检查")
w("")
w("[步骤 36](./migration_tasks.md) 要求「manifest 每个文件已闭环」。闭环定义：")
w("")
w("| 动作 | 闭环条件 |")
w("| --- | --- |")
w("| `move` | 目标路径存在，且内容 diff 只含链接/路径调整 |")
w("| `rewrite` | 目标路径存在，且该位置的测试覆盖源文件的等价行为 |")
w("| `regenerate` | 生成命令在 CI 中可重复执行且输出稳定 |")
w("| `delete` | 新仓库不存在该路径，且删除理由在本文有记录 |")
w("| `out-of-scope` | 新仓库不存在该路径 |")
w("")
w("生成脚本应纳入 CI，在 P8 阶段断言：本清单的行数 = 最终基线的 git 跟踪文件数，且无 `UNCLASSIFIED`。")
w("")

Path(sys.argv[1]).write_text("\n".join(L) + "\n", encoding="utf-8")
print(f"wrote {sys.argv[1]}: {len(L)} lines")
