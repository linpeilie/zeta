const String appTitle = 'Zeta';
const Duration sessionSaveDelay = Duration(milliseconds: 300);

/// Windows 标题栏品牌 Logo 资产路径。
///
/// 品牌资产由根 app 拥有并在 `pubspec.yaml` 声明；`zeta_ui` 只接受注入的 Widget，
/// 不感知资产路径，这样设计系统换宿主时不会缺资源。
const String brandingLogoAsset = 'assets/branding/zeta_logo.svg';
