# WP-5 跨版本行为回归

前置实现：`479839d6`，通过 `git archive` 放入 `/tmp/zeta-wp5-before` 的独立目录。只追加同一个 `agent_management_detection_regression_test.dart`，使用两个内存仓储与内存 Provider 设置，不扫描真实 CLI。

| 场景 | 前置实现 | 当前实现 |
|---|---|---|
| A 异常后仍检测并确认 B | 失败：B 调用次数 0，预期 1 | 通过 |
| partial 期间保留旧确认版本 | 失败：显示 partial，预期 old-a | 通过 |
| 等待探测期间用户修改配置 | 失败：enabled 被回写 true，预期 false | 通过，arguments/extra 也保留 |

前置运行：3 失败、0 通过；当前运行：3 通过、0 失败。原始日志 `/tmp/wp5-regression-before.log`、`/tmp/wp5-regression-after.log`；当前版另被受影响及完整门禁覆盖。

用于前置运行的测试 SHA-256：`de3fe85d271177d71ee49f9ca61baca9fee7fe40a4a0f02e7d5c8f124446437e`。当前文件后来只由统一格式化调整排版，测试逻辑与断言未改变。

本证据证明上述三个行为修复；不代表已执行真实 CLI 或操作系统手工验收。


## 初始化旧 Future 的补充回归

最终审查发现 Provider settings owner 会缓存第一次 `loadSettings()` 的 Future。先初始化设置、再修改设置、最后构建 Management 时，读取 Future 的结果会把管理快照覆盖回旧 enabled/缓存版本。新增 `initialization reads current settings after the cached load future resolves` 在修复前失败（预期 false，实际 true）；修复改为等待加载完成后读端口的当前 settings，不改 Provider settings owner。本条已在最终受影响 880 条及完整门禁 3,194 条中通过。红阶段日志 `/tmp/wp5-initialize-red.log`。
