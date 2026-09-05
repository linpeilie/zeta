/// 品牌图标的着色策略；实际主题颜色由宿主决定。
enum AgentIconColorPolicy {
  /// 使用宿主当前的主题前景色。
  themed,

  /// 保留 SVG 中声明的品牌原色。
  original,
}

/// 插件拥有的 SVG 资源描述，不引入 Flutter 类型或资源加载行为。
///
/// 资源在所属包的 pubspec 中声明，宿主通过 package 与相对路径加载。
/// 此描述只用于静态展示，不进入 Provider 配置或其他持久化数据。
final class AgentProviderSvgIcon {
  /// 声明包内图标及其品牌着色策略。
  const AgentProviderSvgIcon({
    required this.packageName,
    required this.assetPath,
    this.colorPolicy = AgentIconColorPolicy.themed,
  });

  /// 所属包 pubspec 的 name，不是 Provider 实例或协议类型标识。
  final String packageName;

  /// 相对所属包根目录的 SVG 路径，不带 packages 前缀。
  final String assetPath;

  /// 原色或主题着色；尺寸与布局始终由宿主控制。
  final AgentIconColorPolicy colorPolicy;
}
