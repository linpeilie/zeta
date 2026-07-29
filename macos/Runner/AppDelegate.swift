import Cocoa
import CoreText
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 与 Flutter 侧 `zeta/menu` MethodChannel 对应的原生通道。
  private var menuChannel: FlutterMethodChannel?
  /// 通过 CoreText 向 Flutter 暴露本地化系统字体家族。
  private var systemFontCatalogChannel: FlutterMethodChannel?

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    setupMenuChannel()
    setupSystemFontCatalogChannel()
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

  /// 建立 `zeta/system_fonts` 通道，返回 CoreText 可见字体家族。
  private func setupSystemFontCatalogChannel() {
    guard let window = mainFlutterWindow,
          let controller = window.contentViewController as? FlutterViewController else {
      return
    }
    let channel = FlutterMethodChannel(
      name: "zeta/system_fonts",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "listFontFamilies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(Self.listSystemFontFamilies())
    }
    systemFontCatalogChannel = channel
  }

  /// 使用 CoreText 的家族、显示名称和固定字宽特征构造平台中立响应。
  private static func listSystemFontFamilies() -> [[String: Any]] {
    let visibleFamilies =
      CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? []
    var seen = Set<String>()
    var result: [[String: Any]] = []

    for visibleFamily in visibleFamilies {
      let font = CTFontCreateWithName(visibleFamily as CFString, 12, nil)
      let canonicalName = CTFontCopyFamilyName(font) as String
      let normalizedCanonicalName = canonicalName
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard !normalizedCanonicalName.isEmpty else { continue }

      let identity = normalizedCanonicalName.lowercased()
      guard seen.insert(identity).inserted else { continue }

      let localizedName =
        CTFontCopyLocalizedName(font, kCTFontFamilyNameKey, nil) as String?
          ?? normalizedCanonicalName
      var aliases = Set([visibleFamily, normalizedCanonicalName, localizedName])
      let descriptor = CTFontDescriptorCreateWithAttributes([
        kCTFontFamilyNameAttribute: normalizedCanonicalName
      ] as CFDictionary)
      let matchingDescriptors =
        CTFontDescriptorCreateMatchingFontDescriptors(descriptor, nil)
          as? [CTFontDescriptor] ?? []
      for matchingDescriptor in matchingDescriptors {
        if let fontURL =
          CTFontDescriptorCopyAttribute(
            matchingDescriptor,
            kCTFontURLAttribute
          ) as? URL {
          aliases.insert(fontURL.deletingPathExtension().lastPathComponent)
        }
      }

      result.append([
        "id": "macos:\(identity)",
        "familyName": normalizedCanonicalName,
        "displayName": localizedName,
        "aliases": aliases.sorted(),
        "monospace": CTFontGetSymbolicTraits(font).contains(.traitMonoSpace),
      ])
    }

    return result
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
