#ifndef RUNNER_DESKTOP_ATTENTION_CHANNEL_H_
#define RUNNER_DESKTOP_ATTENTION_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

// 注册 `zeta/desktop_attention`，通过 GTK urgency 请求桌面环境提醒用户。
FlMethodChannel* create_desktop_attention_channel(
    FlBinaryMessenger* messenger,
    GtkWindow* window);

#endif  // RUNNER_DESKTOP_ATTENTION_CHANNEL_H_
