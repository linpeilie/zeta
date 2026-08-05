#include "desktop_attention_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstdint>
#include <string>

namespace {

constexpr char kChannelName[] = "zeta/desktop_attention";
constexpr char kSetUnreadCountMethod[] = "setUnreadCount";
constexpr char kRequestAttentionMethod[] = "requestAttention";

bool HasZeroUnreadCount(const flutter::EncodableValue* arguments) {
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return false;
  }
  const auto count = map->find(flutter::EncodableValue("count"));
  if (count == map->end()) {
    return false;
  }
  if (const auto* value = std::get_if<int32_t>(&count->second)) {
    return *value <= 0;
  }
  if (const auto* value = std::get_if<int64_t>(&count->second)) {
    return *value <= 0;
  }
  return false;
}

}  // namespace

class DesktopAttentionChannel::Impl {
 public:
  Impl(flutter::BinaryMessenger* messenger, HWND window)
      : window_(window),
        channel_(std::make_unique<
                 flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, kChannelName,
            &flutter::StandardMethodCodec::GetInstance())) {
    channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<
                   flutter::MethodResult<flutter::EncodableValue>> result) {
          if (call.method_name() == kSetUnreadCountMethod) {
            // Windows intentionally does not draw an unread overlay badge.
            if (HasZeroUnreadCount(call.arguments())) {
              ClearAttention();
            }
            result->Success();
            return;
          }
          if (call.method_name() == kRequestAttentionMethod) {
            // Keep the taskbar flash finite so taskbar activation remains normal.
            FLASHWINFO info = {sizeof(FLASHWINFO), window_,
                               FLASHW_TRAY, 3, 0};
            FlashWindowEx(&info);
            attention_requested_ = true;
            result->Success();
            return;
          }
          result->NotImplemented();
        });
  }

  void HandleWindowActivated() {
    if (!attention_requested_) {
      return;
    }

    // Clear attention before restoring so this activation opens the window.
    ClearAttention();
    if (IsIconic(window_)) {
      ShowWindow(window_, SW_RESTORE);
    } else if (!IsWindowVisible(window_)) {
      ShowWindow(window_, SW_SHOW);
    }
    SetForegroundWindow(window_);
  }

 private:
  void ClearAttention() {
    if (!attention_requested_) {
      return;
    }
    FLASHWINFO info = {sizeof(FLASHWINFO), window_, FLASHW_STOP, 0, 0};
    FlashWindowEx(&info);
    attention_requested_ = false;
  }

  HWND window_;
  bool attention_requested_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

DesktopAttentionChannel::DesktopAttentionChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

DesktopAttentionChannel::~DesktopAttentionChannel() = default;

void DesktopAttentionChannel::HandleWindowActivated() {
  impl_->HandleWindowActivated();
}
