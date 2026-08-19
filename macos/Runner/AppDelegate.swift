import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 与 Flutter 侧 `zeta/menu` MethodChannel 对应的原生通道。
  private var menuChannel: FlutterMethodChannel?

  /// 已安装的 Zeta File 菜单项；configure 前保持为 nil。
  private var fileMenuItem: NSMenuItem?

  /// File 菜单里的 Open Project 项，重复 configure 时只更新标题。
  private var openProjectMenuItem: NSMenuItem?

  /// configure 之前也可更新的 Open Project enabled 状态。
  private var openProjectEnabled = true

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupMenuChannel()
  }

  /// 建立 `zeta/menu` 通道：接收版本化 configure，并把菜单点击转给 Flutter。
  private func setupMenuChannel() {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "zeta/menu",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handleMenuMethod(call, result: result)
    }
    menuChannel = channel
  }

  private func handleMenuMethod(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      handleConfigure(call, result: result)
    case "setEnabled":
      handleSetEnabled(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// 只接受稳定 commandId，未知命令或错误参数均 fail closed。
  private func handleSetEnabled(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let commandId = args["commandId"] as? String,
          commandId == "openProject",
          let enabled = args["enabled"] as? Bool else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "setEnabled requires a known command and boolean enabled",
          details: nil
        )
      )
      return
    }
    openProjectEnabled = enabled
    openProjectMenuItem?.isEnabled = enabled
    result(true)
  }

  /// 仅在 schema 与标签完整时安装或更新 Zeta 自有 File 菜单。
  private func handleConfigure(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "configure requires a map",
          details: nil
        )
      )
      return
    }
    guard let version = args["version"] as? Int, version == 1 else {
      result(
        FlutterError(
          code: "unsupported_version",
          message: "unknown menu schema version",
          details: nil
        )
      )
      return
    }
    guard let fileLabel = sanitizedLabel(args["fileMenuLabel"]),
          let openLabel = sanitizedLabel(args["openProjectLabel"]) else {
      result(
        FlutterError(
          code: "invalid_arguments",
          message: "missing menu labels",
          details: nil
        )
      )
      return
    }
    applyFileMenu(fileLabel: fileLabel, openProjectLabel: openLabel)
    result(true)
  }

  /// 首次安装 File 菜单；重复配置只更新标题，动作仍指向同一 selector。
  private func applyFileMenu(fileLabel: String, openProjectLabel: String) {
    if let fileItem = fileMenuItem, let openItem = openProjectMenuItem {
      fileItem.title = fileLabel
      fileItem.submenu?.title = fileLabel
      openItem.title = openProjectLabel
      openItem.isEnabled = openProjectEnabled
      return
    }

    guard let mainMenu = NSApplication.shared.mainMenu else { return }

    let fileMenu = NSMenu(title: fileLabel)
    let openProjectItem = NSMenuItem(
      title: openProjectLabel,
      action: #selector(openProject(_:)),
      keyEquivalent: "o"
    )
    openProjectItem.target = self
    openProjectItem.isEnabled = openProjectEnabled
    fileMenu.addItem(openProjectItem)

    let fileItem = NSMenuItem()
    fileItem.title = fileLabel
    fileItem.submenu = fileMenu
    // 索引 0 是应用菜单，插入到索引 1 让 File 排在 Edit 之前。
    mainMenu.insertItem(fileItem, at: 1)

    fileMenuItem = fileItem
    openProjectMenuItem = openProjectItem
  }

  private func sanitizedLabel(_ value: Any?) -> String? {
    guard let text = value as? String else {
      return nil
    }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// 用户选择 File / Open Project 时触发，转发给 Flutter 侧执行打开流程。
  @objc private func openProject(_ sender: NSMenuItem) {
    menuChannel?.invokeMethod("openProject", arguments: nil)
  }
}
