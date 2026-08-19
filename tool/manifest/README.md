# 迁移清单生成器

生成 [`docs/zh/architecture/migration_manifest.md`](../../docs/zh/architecture/migration_manifest.md) 与
[`docs/en/architecture/migration_manifest.md`](../../docs/en/architecture/migration_manifest.md)。

## 用法

```sh
cd tool/manifest
python gen_manifest.py rows.json                                        # 分类 + 覆盖校验
python render_manifest.py ../../docs/zh/architecture/migration_manifest.md
python render_manifest_en.py ../../docs/en/architecture/migration_manifest.md
```

`gen_manifest.py` 对旧仓库执行 `git ls-files`，按 `RULES` 表逐文件分类。**存在任何未分类文件时
退出码为 1 并打印路径**——这就是「每个文件恰好归类一次」的机器断言。

## 文件

| 文件 | 作用 |
| --- | --- |
| `gen_manifest.py` | 分类规则表；改归属只改这里 |
| `render_manifest.py` | 中文 Markdown 渲染 |
| `render_manifest_en.py` | 英文 Markdown 渲染 |
| `i18n.py` | note / target 的中英对照；新增规则时必须同步补充，否则英文版会回落中文 |

## 修改归属时

1. 改 `gen_manifest.py` 的 `RULES`。
2. 在 `i18n.py` 补对应的英文译文（缺失时英文版会回落中文，务必同步）。
3. 重新生成中英两版并一起提交。

`OLD` 常量指向旧仓库路径，执行[步骤 1](../../docs/zh/architecture/migration_tasks.md) 时需要
改为清退 Cursor 之后的最终基线。

## CI

P8 阶段应在 CI 中断言：`gen_manifest.py` 退出码为 0，且行数等于最终基线的 git 跟踪文件数。
