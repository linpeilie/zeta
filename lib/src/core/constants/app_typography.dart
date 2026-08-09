/// 应用内置代码字体族名（与 `pubspec.yaml` fonts 声明一致）。
///
/// 生效位置：
/// - 外观设置默认「代码字体」选择（`AppearanceFontChoice.bundledJetBrainsMono`）
/// - [IdeThemeData.codeFontFamily] / `buildIdeThemeData` 回退值
/// - [IdeTextStyles] 的 `codeMedium` / `codeSmall` / `identifier` /
///   `identifierSmall` / `numeric` / `metricValue` 默认字体
/// - shadcn 主题投影中的 mono / inlineCode 字体族
const String bundledCodeFontFamily = 'JetBrainsMono';

/// 应用内置界面字体族名（与 `pubspec.yaml` fonts 声明一致）。
///
/// 生效位置：
/// - `buildIdeThemeData` 中「跟随应用默认」（`systemDefault`）的解析目标
/// - [IdeTextStyles] 全部 UI 语义样式的默认字体
/// - shadcn / Material 主题投影的 sans 字体族
///
/// 注意：Geist 不含中日韩字形，中文由 `resolvePlatformUiFontFamilyFallback`
/// 提供的平台回退链（PingFang SC / Microsoft YaHei UI / Noto Sans CJK SC）承接。
/// 用户仍可在外观设置里显式改回系统字体。
const String bundledUiFontFamily = 'Geist';

/// 界面排版 token 的默认基准字号（逻辑 px）。
///
/// 生效位置：
/// - `AppearanceSettings.uiFontSize` 默认值与设置页滑块基准
/// - [IdeTextStyles.resolve] 中 UI 样式的缩放分母：
///   `uiScale = uiFontSize / defaultUiFontSize`
/// - Material / shadcn 主题投影的 UI 字号缩放分母
///
/// 改此常量会改变「字号=12」时的绝对视觉大小，以及设置页默认档位含义。
const double defaultUiFontSize = 12;

/// 代码排版 token 的默认基准字号（逻辑 px）。
///
/// 生效位置：
/// - `AppearanceSettings.codeFontSize` 默认值
/// - [IdeTextStyles.resolve] 中代码样式的缩放分母：
///   `codeScale = codeFontSize / defaultCodeFontSize`
/// - shadcn mono / inlineCode 字号缩放分母
const double defaultCodeFontSize = 12;
