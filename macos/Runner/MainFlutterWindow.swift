import Cocoa
import CoreText
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 字体目录通道必须与 Flutter 引擎一起注册，避免 Dart 启动后才补注册的竞态。
  private var systemFontCatalogChannel: FlutterMethodChannel?
  private var desktopAttentionChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    setupSystemFontCatalogChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    setupDesktopAttentionChannel(
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  /// 建立桌面提醒通道，使用 Dock 角标展示运行期未读数量。
  private func setupDesktopAttentionChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "zeta/desktop_attention",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "setUnreadCount":
        let arguments = call.arguments as? [String: Any]
        let count = max(arguments?["count"] as? Int ?? 0, 0)
        NSApp.dockTile.badgeLabel = count == 0
          ? nil
          : (count > 99 ? "99+" : String(count))
        result(nil)
      case "requestAttention":
        NSApp.requestUserAttention(.informationalRequest)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    desktopAttentionChannel = channel
  }

  /// 建立 `zeta/system_fonts` 通道，返回 CoreText 可见字体家族。
  private func setupSystemFontCatalogChannel(
    binaryMessenger: FlutterBinaryMessenger
  ) {
    let channel = FlutterMethodChannel(
      name: "zeta/system_fonts",
      binaryMessenger: binaryMessenger
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
}
