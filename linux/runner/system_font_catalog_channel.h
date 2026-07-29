#ifndef RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_
#define RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_

#include <flutter_linux/flutter_linux.h>

// 注册 `zeta/system_fonts`，通过 Fontconfig 返回系统字体家族。
FlMethodChannel* create_system_font_catalog_channel(
    FlBinaryMessenger* messenger);

#endif  // RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_
