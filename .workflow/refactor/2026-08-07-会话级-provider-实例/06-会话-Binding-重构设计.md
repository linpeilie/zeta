# 06 · 会话 Binding 重构设计

本方案取代 04/05 中“每个 Workspace entry 自带 Provider controller，再由 registry
公开 scope/pin/snapshot 供独立 reaper 回收”的设计。长期有效规则已同步到工程规范 §4。

## 决策

- Registry 仍是 Provider 实例和进程的唯一所有者，也是 factory 唯一调用者。
- GlobalRuntime 封装每个 Provider ID 唯一的 global 实例，承载所有会话前/全局操作。
- BindingManager 以 draft/thread key 唯一维护逻辑会话，并内聚空闲监控。
- Binding 持有可选 session runtime、事件 generation、权限状态和活动计数。
- ViewModel 只编排对话/UI，不持有 registry lease、scope、pin 或 runtime identity 缓存。

## 生命周期不变量

1. 新建草稿、打开已有 thread、读取历史均不启动 session Provider。
2. `beginTurn()` 是唯一创建入口；草稿取得 threadId 后原子晋升，冲突 fail-closed。
3. `runCurrent()` 不创建实例；迟到 cancel/steer/审批回写在回收后 fail-closed。
4. turn 与短 RPC 均计为活跃；完成时间重新开始计算 10 分钟 TTL。
5. sweep single-flight，候选携带 identity 防 ABA；旧进程 dispose 完成前 acquire 等待。
6. global 永不空闲回收；配置变化仍失效该 Provider 的全部 runtime。

## 权限边界

权限状态跟随 Binding，不再用“Provider 当前 runtime”代表所有会话。dormant 选择仅更新
本 Binding 和 provider default，标记下次发送生效；runtime 存在时才 apply。回收清除
runtime-only 状态，保留 default、session effective、pending turn 和持久化失败。Project
Threads 优先读取已有 Binding，否则使用 provider/catalog default。
