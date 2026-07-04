import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 与 Flutter 侧 `zeta/menu` MethodChannel 对应的原生通道。
  private var menuChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupMenuChannel()
    installFileMenu()
  }

  /// 建立 `zeta/menu` 通道，用于把原生菜单选中事件转发到 Flutter。
  private func setupMenuChannel() {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }
    menuChannel = FlutterMethodChannel(
      name: "zeta/menu",
      binaryMessenger: controller.engine.binaryMessenger
    )
  }

  /// 在应用菜单之后、Edit 菜单之前插入「File - Open Project…」菜单。
  private func installFileMenu() {
    guard let mainMenu = NSApplication.shared.mainMenu else { return }

    let fileMenu = NSMenu(title: "File")
    let openProjectItem = NSMenuItem(
      title: "Open Project…",
      action: #selector(openProject(_:)),
      keyEquivalent: "o"
    )
    openProjectItem.target = self
    fileMenu.addItem(openProjectItem)

    let fileMenuItem = NSMenuItem()
    fileMenuItem.submenu = fileMenu
    // 索引 0 是应用菜单，插入到索引 1 让 File 排在 Edit 之前。
    mainMenu.insertItem(fileMenuItem, at: 1)
  }

  /// 用户选择「File - Open Project…」时触发，转发给 Flutter 侧执行打开流程。
  @objc private func openProject(_ sender: NSMenuItem) {
    menuChannel?.invokeMethod("openProject", arguments: nil)
  }
}
