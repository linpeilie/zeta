# Provider 包内图标迁移与验收

日期：2026-09-05

## 范围与设计

本任务承接 Provider 插件包拆分后的图标归属分析。三个插件拥有各自 `assets/icon.svg` 与包内 `flutter.assets` 声明，纯 Dart API 新增可选 `AgentProviderDefinition.icon`（包名、相对 SVG 路径、着色枚举）。宿主不再保存厂商图标表，原 AST 白名单已删除并增加反例。

`agentProviderIconResolverProvider` 是 application 的可覆盖静态查询接缝。生产入口和测试助手经 app 的 `agentProviderIconsOverride` 从静态 manifest 装配，不读取激活目录，不冻结语言、不创建 CLI。独立组件在 ProviderScope 内未装图标目录时安全显示中立图标；显式测试覆盖优先于测试助手默认值。

保持稳定 id 查询；不扩展自定义实例到协议类型的品牌映射，不按显示名或 id 前缀猜品牌。主题色、原色、尺寸、语义与错误渲染回退不变；图标不参与配置/用量持久化。没有增加 Flutter SDK、flutter_svg 或任何其他依赖，core、SDK、kernel 与协议实现未改。

## 资源逐字节核对

与变更前 Git 版本比较，三个 SVG 字节完全一致：

| 插件 | 字节数 | SHA-256 |
|---|---:|---|
| Codex | 6617 | a7d6ecd3d22d1979e0d46f1da03fe280719f2fe8eb612232a335d1d00bba198c |
| Grok | 1250 | 22bf4d0f9cffc9801cd6fa1c687f7e1bb457c593d7f479239910f383c6b7196a |
| Claude Code | 2755 | 298b1ec372beb0bb63627435d2918350ce0e62edf16122db692b41e01e5daf54 |

原测试仅修改包资源定位断言及 ProviderScope 装配；原尺寸、滤镜、布局、语义和未知 id 回退断言保留。新增动态资源清单与实际 SVG 解码、第四个定义、可选图标、错误渲染、静态查询不激活、元数据不持久化与旧图标表反例测试。第四个测试定义复用已打包资源，证明新增身份不需宿主映射；不将此测试宣称为新增物理插件包构建。

## 验证记录

- 定向图标、manifest 与隔离守卫：40 条通过。
- 严格依赖锁校验：使用仓库源 `PUB_HOSTED_URL=https://pub.flutter-io.cn flutter pub get --enforce-lockfile` 通过。
- 本机默认源与锁文件源不一致的首次检查失败；随后默认 analyze 的隐式 pub 导致源与 Riverpod 解析漂移，已恢复本任务开始时的锁文件并按原源严格重建依赖。本任务不提交这些环境变化。
- `dart format .`：1086 个 Dart 文件，最终 0 个改动；`flutter analyze`：0 issue。
- `bash tool/test_affected.sh`：因根 pubspec 改动选择全量。首次根运行暴露页面测试宿主未提供 ProviderScope 的 6 个失败；为避免继续运行已知失败批次，中止该次根测试，脚本后续仍完成内部包分析及 982 条测试。公共组件测试宿主随后补齐位于 ShadcnApp 之上的静态 ProviderScope，覆盖页面与 Overlay；图标、项目首页、全局首页 15 条定向复验通过，原页面断言未改。
- 首次独立完整门禁：根测试仅管理页独立测试宿主的 2 条品牌图标断言失败，其余根测试与内部包通过。已在该宿主注入相同静态目录，管理页 9 条定向复验通过；所有直接断言品牌 SVG 的测试入口均已检查。
- `PUB_HOSTED_URL=https://pub.flutter-io.cn bash tool/test_full.sh`：最终退出码 0；根 1919 条 + 内部包 982 条，共 2901 条通过。根 JSON reporter 的 done.success 为 true。内部包分析全部通过，api 与三个 Provider 包继续使用 dart runner。
- 内部包测试数：core 7、api 3、Claude Code 251、Codex 175、Grok 193、SDK 74、foundation 32、markdown 208、kernel 23、UI 16。
- 最终 `git diff --check` 通过；锁文件、core、SDK、kernel、配置 codec/store 与协议实现无变更。Git 将三个 SVG 均识别为 100% 相同内容的迁移。

## 验证边界

资源清单和三个真实 SVG 经 Flutter 测试资源包加载并解码；这不代表 Windows/Linux 原生应用打包或设备验收。错误回退测试直接调用 SvgPicture 的 errorBuilder，验证宿主渲染契约。开发中注入真实缺失资源时，现有 flutter_svg/vector_graphics 缓存 Future 链产生未处理异步错误；本次不修改第三方依赖或原有加载机制，也不把回退渲染用例宣称为缺失资源端到端无异常验证。

已同步 AGENTS、工程规范、设计文档、中英文总览、开发指南、中英文术语表与贡献指南。纯内部重构，不修改 CHANGELOG；历史 WP 文档保留当时的记录。
