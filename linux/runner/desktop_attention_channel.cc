#include "desktop_attention_channel.h"

#include <cstring>

namespace {

constexpr char kChannelName[] = "zeta/desktop_attention";
constexpr char kSetUnreadCountMethod[] = "setUnreadCount";
constexpr char kRequestAttentionMethod[] = "requestAttention";

struct ChannelContext {
  GtkWindow* window;
};

int read_count(FlMethodCall* method_call) {
  FlValue* arguments = fl_method_call_get_args(method_call);
  if (arguments == nullptr ||
      fl_value_get_type(arguments) != FL_VALUE_TYPE_MAP) {
    return 0;
  }
  FlValue* value = fl_value_lookup_string(arguments, "count");
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? static_cast<int>(fl_value_get_int(value))
             : 0;
}

void method_call_cb(FlMethodChannel*,
                    FlMethodCall* method_call,
                    gpointer user_data) {
  auto* context = static_cast<ChannelContext*>(user_data);
  const char* method = fl_method_call_get_name(method_call);
  if (std::strcmp(method, kSetUnreadCountMethod) == 0) {
    gtk_window_set_urgency_hint(context->window, read_count(method_call) > 0);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  if (std::strcmp(method, kRequestAttentionMethod) == 0) {
    gtk_window_set_urgency_hint(context->window, TRUE);
    fl_method_call_respond_success(method_call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(method_call, nullptr);
}

void destroy_context(gpointer data) {
  delete static_cast<ChannelContext*>(data);
}

}  // namespace

FlMethodChannel* create_desktop_attention_channel(
    FlBinaryMessenger* messenger,
    GtkWindow* window) {
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      messenger, kChannelName, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      channel, method_call_cb, new ChannelContext{window}, destroy_context);
  return channel;
}
