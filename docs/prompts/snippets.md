# 可拼接片段

基础模板管「做什么」，这里的片段管「注意什么」。按需粘到提示词末尾。

**别一次贴五个。** 提示词越长信噪比越低，挑真正相关的一到两个就够。

---

## 定位与理解

**用 CodeGraph 而不是 grep**

```text
用 codegraph explore "<符号或问题>" 定位，不要 grep + 逐个读文件。
```

**先摸清现状再动手**

```text
动手前先说清楚：这块现在是怎么工作的、关键符号有哪些、调用链是什么样。
我确认你理解正确了再改。
```

**只读，不改**

```text
这次只做分析，不要修改任何文件。
```

---

## 约束尾缀

**通用收尾**（大多数任务加这一条就够）

```text
遵守 AGENTS.md：动手前按 §2 路由表确认命中哪几条门禁，
完成后跑 §0 的收尾协议，末尾附提交信息。
```

**Provider 隔离**（碰 agent feature 时）

```text
守住 G1/G2/G4：Provider 协议只在 data 层；source id 只是 metadata，
entryId 和终态由该 Provider 的 adapter/reducer 决定；
UI 按 capability 渲染，不支持就 capability=false + 抛 UnsupportedError，不要静默降级。
完成后跑 G1 的自查命令并贴结果。
```

**流式与时序**（碰 reducer、pipeline、事件流时）

```text
守住 G3：reducer 保持纯同步，不引入 Timer / Future / Flutter scheduler / 外部回调，
副作用走 EffectRunner。live/history/replay 用独立 reducer 实例。
所有异步路径校验 listener generation、runtime/epoch 和 disposed 状态。
```

**权限与审批**（碰审批卡片、Plan、权限选项时）

```text
守住 G5：权限审批 / 用户提问 / Plan 审批 / Plan 执行交接是四种独立语义，
不共享 request/decision 模型。Plan 执行必须新建显式 Default 回合，
不得预授权任何命令、文件或网络操作。默认策略保持保守。
```

**UI 与主题**（碰任何 Widget 时）

```text
守住 G8：shadcn_flutter 只能 as sf 导入，语义色走 IdeColors.of(context)，
禁止裸 Color(0x...)、手写 BoxShadow、临时 BorderRadius.circular。
优先复用 ui/core 已有原语，不要新造视觉组件。
长文本一律有界布局 + 省略号。完成后跑 G8 的两条自查命令。
```

**持久化与隐私**（碰落盘的东西时）

```text
守住 G6/G7：Provider 私有数据读取只在自有 data adapter，原始结构和路径不上浮；
Zeta 自有数据只写 ~/.zeta，文件由 app 层注入，不在 presentation/application 拼路径；
JSON 版本化 + 宽容解码；不落盘 prompt、回复、工具输出、原始错误文本、
环境变量、凭证或 Provider raw payload。
```

**三端验证**（碰平台相关代码时）

```text
这是三端（macOS / Windows / Linux）都有实现的能力。
改完给验证矩阵：平台 | 验证结果（通过 / 失败 / 未验证）。
没条件验证的端如实写「未验证」，不要推断通过。
```

**性能热路径**（碰 resize、时间线渲染时）

```text
禁止 post-frame 测高、GlobalKey 查高、layout 后 setState 反馈环。
时间线保持 SliverList.builder 虚拟化，高频重绘区加 RepaintBoundary。
数据没变化的 resize，解析和构建增量必须为 0。
```

---

## 测试尾缀

**分层测试要求**

```text
按 AGENTS.md §3 补测试：domain/codec/mapper 走单测，
controller 的分页、恢复、竞态、错误路径走单测，用户可见行为走 widget 测试。
用 fake 不用 mock，AAA 结构，依赖构造函数注入。
```

**先写失败测试**

```text
先写一个能复现问题的失败测试，跑给我看它确实是红的，再动手修。
```

**共享层测试**

```text
共享层测试必须用 Provider 无关 fixture，并断言无具体 Provider import、
无 kind/id 分支、无 raw identity 推断。参考 test/src/features/agent/architecture/。
```

**只跑相关测试**（迭代期提速用；合并前仍要跑全量）

```text
这一轮只跑 <测试文件路径>，不用跑全量。
```

---

## 输出格式约定

**先列清单再动手**

```text
先给我改动清单（文件 + 各属哪一层 + 改什么），我确认后再写代码。
```

**分步执行，每步停**

```text
一步一步做，每步做完跑 analyze + 相关测试，把结果告诉我，等我确认再进下一步。
```

**给一个方案，不要列菜单**

```text
给一个方案 + 你的推荐理由，不要列三五个选项让我挑。
你考虑过但否决的方案，用一两句说明为什么否决。
```

**如实报告**

```text
测试没过就贴出失败输出，跳过的步骤明确说跳过了，别用「应该没问题」带过。
```

---

## 常见反模式禁令

按需追加，都是这个项目实际踩过的坑。

```text
不要为了让改动看起来简单，就在共享层加 Provider 分支。
```

```text
不要用 no-op 或空返回伪造不支持的能力 —— 静默成功比明确报错危害大得多。
```

```text
不要动 dart_test.yaml 的 concurrency: 2。
```

```text
不要为了让旧测试通过而保留兼容分支。行为变了，测试就该跟着变。
```

```text
不要在没复现的情况下猜着改 bug。
```

```text
不要顺手重构无关代码。这次只做 <范围内的事>。
```

```text
不要新建顶层宽泛目录，也不要建只放 .gitkeep 的空占位目录。
```
