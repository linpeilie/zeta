/// 读取当前时间的最小端口。
///
/// domain / application 不允许直接调用 [DateTime.now]：时间是外部输入，必须
/// 可注入才能写确定性测试。生产组合点传 [systemClock]，测试传固定值即可。
typedef Clock = DateTime Function();

/// 生产环境使用的系统时钟。
DateTime systemClock() => DateTime.now();

/// 始终返回同一时刻的时钟，用于确定性测试与回放。
Clock fixedClock(DateTime instant) =>
    () => instant;
