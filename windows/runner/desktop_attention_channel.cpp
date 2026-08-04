#include "desktop_attention_channel.h"

#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <string>

namespace {

constexpr char kChannelName[] = "zeta/desktop_attention";
constexpr char kSetUnreadCountMethod[] = "setUnreadCount";
constexpr char kRequestAttentionMethod[] = "requestAttention";

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

 private:
  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};

DesktopAttentionChannel::DesktopAttentionChannel(
    flutter::BinaryMessenger* messenger, HWND window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

DesktopAttentionChannel::~DesktopAttentionChannel() = default;
