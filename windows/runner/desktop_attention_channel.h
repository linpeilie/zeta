#ifndef RUNNER_DESKTOP_ATTENTION_CHANNEL_H_
#define RUNNER_DESKTOP_ATTENTION_CHANNEL_H_

#include <windows.h>

#include <flutter/binary_messenger.h>

#include <memory>

// Manages the taskbar unread overlay and window attention requests.
class DesktopAttentionChannel {
 public:
  DesktopAttentionChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~DesktopAttentionChannel();

  DesktopAttentionChannel(const DesktopAttentionChannel&) = delete;
  DesktopAttentionChannel& operator=(const DesktopAttentionChannel&) = delete;

  void HandleWindowMessage(UINT message);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_DESKTOP_ATTENTION_CHANNEL_H_
