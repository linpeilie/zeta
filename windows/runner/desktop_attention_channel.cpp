#include "desktop_attention_channel.h"

#include <ShObjIdl.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <wrl/client.h>

#include <algorithm>
#include <cstdint>
#include <string>

namespace {

using Microsoft::WRL::ComPtr;

constexpr char kChannelName[] = "zeta/desktop_attention";
constexpr char kSetUnreadCountMethod[] = "setUnreadCount";
constexpr char kRequestAttentionMethod[] = "requestAttention";

int ReadCount(const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return 0;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return 0;
  }
  const auto iterator = map->find(flutter::EncodableValue("count"));
  if (iterator == map->end()) {
    return 0;
  }
  if (const auto* value = std::get_if<int32_t>(&iterator->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&iterator->second)) {
    return static_cast<int>(*value);
  }
  return 0;
}

HICON CreateUnreadOverlayIcon() {
  BITMAPV5HEADER header = {};
  header.bV5Size = sizeof(BITMAPV5HEADER);
  header.bV5Width = 16;
  header.bV5Height = -16;
  header.bV5Planes = 1;
  header.bV5BitCount = 32;
  header.bV5Compression = BI_BITFIELDS;
  header.bV5RedMask = 0x00FF0000;
  header.bV5GreenMask = 0x0000FF00;
  header.bV5BlueMask = 0x000000FF;
  header.bV5AlphaMask = 0xFF000000;

  void* raw_pixels = nullptr;
  HDC screen = GetDC(nullptr);
  HBITMAP color = CreateDIBSection(
      screen, reinterpret_cast<BITMAPINFO*>(&header), DIB_RGB_COLORS,
      &raw_pixels, nullptr, 0);
  ReleaseDC(nullptr, screen);
  if (color == nullptr || raw_pixels == nullptr) {
    if (color != nullptr) {
      DeleteObject(color);
    }
    return nullptr;
  }

  auto* pixels = static_cast<uint32_t*>(raw_pixels);
  for (int y = 0; y < 16; ++y) {
    for (int x = 0; x < 16; ++x) {
      const int dx = x - 8;
      const int dy = y - 8;
      pixels[y * 16 + x] = dx * dx + dy * dy <= 36
                                   ? 0xFFF04444
                                   : 0x00000000;
    }
  }

  HBITMAP mask = CreateBitmap(16, 16, 1, 1, nullptr);
  ICONINFO info = {};
  info.fIcon = TRUE;
  info.hbmColor = color;
  info.hbmMask = mask;
  HICON icon = CreateIconIndirect(&info);
  DeleteObject(color);
  DeleteObject(mask);
  return icon;
}

}  // namespace

class DesktopAttentionChannel::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window),
        taskbar_created_message_(RegisterWindowMessage(L"TaskbarButtonCreated")),
        channel_(std::make_unique<
                 flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, kChannelName,
            &flutter::StandardMethodCodec::GetInstance())) {
    if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(taskbar_.GetAddressOf())))) {
      taskbar_->HrInit();
    }
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<
                   flutter::MethodResult<flutter::EncodableValue>> result) {
          if (call.method_name() == kSetUnreadCountMethod) {
            unread_count_ = std::max(0, ReadCount(call.arguments()));
            ApplyOverlay();
            result->Success();
            return;
          }
          if (call.method_name() == kRequestAttentionMethod) {
            FLASHWINFO info = {sizeof(FLASHWINFO), window_,
                               FLASHW_TRAY | FLASHW_TIMERNOFG, 3, 0};
            FlashWindowEx(&info);
            result->Success();
            return;
          }
          result->NotImplemented();
        });
  }

  void HandleWindowMessage(UINT message) {
    if (message == taskbar_created_message_ && unread_count_ > 0) {
      ApplyOverlay();
    }
  }

 private:
  void ApplyOverlay() {
    if (!taskbar_) {
      return;
    }
    if (unread_count_ <= 0) {
      taskbar_->SetOverlayIcon(window_, nullptr, L"");
      return;
    }
    HICON icon = CreateUnreadOverlayIcon();
    if (icon == nullptr) {
      return;
    }
    taskbar_->SetOverlayIcon(window_, icon,
                             L"Zeta has unread notifications");
    DestroyIcon(icon);
  }

  HWND window_;
  UINT taskbar_created_message_;
  int unread_count_ = 0;
  ComPtr<ITaskbarList3> taskbar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

DesktopAttentionChannel::DesktopAttentionChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

DesktopAttentionChannel::~DesktopAttentionChannel() = default;

void DesktopAttentionChannel::HandleWindowMessage(UINT message) {
  impl_->HandleWindowMessage(message);
}
