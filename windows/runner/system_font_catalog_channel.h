#ifndef RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_
#define RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>

#include <memory>

// Registers `zeta/system_fonts` and exposes DirectWrite font families.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
CreateSystemFontCatalogChannel(flutter::BinaryMessenger* messenger);

#endif  // RUNNER_SYSTEM_FONT_CATALOG_CHANNEL_H_
