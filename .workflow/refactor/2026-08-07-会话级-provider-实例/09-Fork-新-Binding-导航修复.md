# Fork 新 Binding 导航修复

## 根因

fork 由源 `AgentConversationViewModel` 发起，但旧实现随后仍在同一个 ViewModel 上
`switchThread`。这与“真实 thread 的 Binding 不允许原地改绑”冲突：真实 Binding 会
fail-closed，而使用 draft Binding 的测试又掩盖了该问题。

## 修复边界

- ViewModel 只负责通过 global runtime 发起 fork，并把返回的 `AgentSession` 交给 Shell。
- Shell 把 fork 结果当作 Provider 新建的 thread：调用 `registerSession` 插入列表，再复用
  `selectProjectThread` 创建/选择独立 Entry/Binding 并读取历史；“编辑后重试”最后才由新
  ViewModel 提交编辑后的内容。
- 源 Entry/Binding 保持原 thread 身份，不转移 runtime、权限状态或事件 generation。
- 普通 fork 只读取新 thread 历史，不创建 session runtime；之后首次发送才通过
  `beginTurn()` 惰性启动。
- `AgentThreadWorkspaceController` 不再包含 fork 专用导航或 Projects 登记回调，只向每个
  ViewModel 注入同一个通用新 thread 入口。

## 回归约束

使用真实 thread Binding 覆盖 A → B fork：

- B 成为 Workspace 当前选择，A 仍绑定 A。
- fork 完成时只有 global runtime；在 B 首次发送后才创建 B 的 session runtime。
- 随后的 rename/send 只携带 B 的 thread id。
- 编辑后重试在 B 的新 ViewModel 上发送，A 不被改绑。

长期约束已同步到架构总览、工程规范、术语表、开发者指南与贡献指南。

## 验证结果

- `dart format .`：通过。
- `flutter analyze`：通过，无问题。
- Shell、Binding、ViewModel、Projects 与权限架构定向测试：154 项通过；覆盖普通 fork
  惰性切换、编辑后重试发送，以及后续 rename/send 只作用于新 thread。
- 完整 `flutter test`：1320 项通过、1 项跳过、19 项失败；其中多组 Widget 测试（包括本次
  涉及的 Widget 文件）在加载阶段被 `platform 3.0.0` 与当前 Dart SDK 的
  `Platform.packageRoot` 不兼容阻塞，另有与本次 fork 无关的字体选择用例失败。失败数量与
  本轮修改前的已有运行记录一致；由于缺少干净基线，不推断完整套件“未新增失败”，也不
  推断被阻塞的 Widget 回归通过。
- 真实 CLI/UI fork 冒烟：当前执行环境没有可用的桌面交互与账号验收条件，标记为待执行，
  不推断通过。
