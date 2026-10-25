#include "window_controls.h"

#include <gtk/gtk.h>
#include <cstring>

namespace {
void request_close(GtkWidget*, FlMethodChannel* channel) {
  // Dart owns hiding/caching, avoiding a second hide racing a rapid reopen.
  fl_method_channel_invoke_method(channel, "closeRequested", nullptr, nullptr,
                                 nullptr, nullptr);
}

gboolean on_delete(GtkWidget* window, GdkEvent*, gpointer channel) {
  request_close(window, FL_METHOD_CHANNEL(channel));
  return TRUE;  // Cached engines are released only by an explicit destroy.
}

int integer_arg(FlValue* args, const char* key, int fallback) {
  if (!args || fl_value_get_type(args) != FL_VALUE_TYPE_MAP) return fallback;
  FlValue* value = fl_value_lookup_string(args, key);
  return value && fl_value_get_type(value) == FL_VALUE_TYPE_INT
             ? static_cast<int>(fl_value_get_int(value)) : fallback;
}

void handle(FlMethodChannel* channel, FlMethodCall* call, gpointer data) {
  g_autoptr(GObject) object = G_OBJECT(g_weak_ref_get(static_cast<GWeakRef*>(data)));
  GtkWidget* top = object ? gtk_widget_get_toplevel(GTK_WIDGET(object)) : nullptr;
  if (!top || !GTK_IS_WINDOW(top)) {
    fl_method_call_respond_error(call, "WINDOW_UNAVAILABLE",
                                "This engine has no attached window", nullptr, nullptr);
    return;
  }
  GtkWindow* window = GTK_WINDOW(top);
  if (!g_object_get_data(G_OBJECT(window), "gotoim-close-hook")) {
    g_signal_connect_object(window, "delete-event", G_CALLBACK(on_delete),
                            channel, static_cast<GConnectFlags>(0));
    g_object_set_data(G_OBJECT(window), "gotoim-close-hook", GINT_TO_POINTER(1));
  }
  const char* method = fl_method_call_get_name(call);
  FlValue* args = fl_method_call_get_args(call);
  bool response = true;
  if (strcmp(method, "configure") == 0) {
    response = gtk_window_is_maximized(window);
  } else if (strcmp(method, "minimize") == 0) {
    gtk_window_iconify(window);
  } else if (strcmp(method, "toggleMaximize") == 0) {
    response = !gtk_window_is_maximized(window);
    if (response) gtk_window_maximize(window);
    else gtk_window_unmaximize(window);
  } else if (strcmp(method, "restore") == 0) {
    gtk_window_deiconify(window);
    gtk_window_present(window);
    response = gtk_window_is_maximized(window);
  } else if (strcmp(method, "toggleVisibility") == 0) {
    if (gtk_widget_get_visible(top)) gtk_widget_hide(top);
    else gtk_window_present(window);
    response = gtk_widget_get_visible(top);
  } else if (strcmp(method, "close") == 0) {
    request_close(top, channel);
  } else if (strcmp(method, "hide") == 0) {
    gtk_widget_hide(top);
  } else if (strcmp(method, "destroy") == 0) {
    // Respond before disposing the view/messenger that owns this channel.
    g_autoptr(FlValue) value = fl_value_new_bool(true);
    fl_method_call_respond_success(call, value, nullptr);
    gtk_widget_destroy(top);
    return;
  } else if (strcmp(method, "center") == 0) {
    int width = 0, height = 0;
    gtk_window_get_size(window, &width, &height);
    width = integer_arg(args, "width", width);
    height = integer_arg(args, "height", height);
    if (width <= 0 || height <= 0) {
      fl_method_call_respond_error(call, "INVALID_BOUNDS", "Invalid window size", nullptr, nullptr);
      return;
    }
    gtk_window_resize(window, width, height);
    gtk_window_set_position(window, GTK_WIN_POS_CENTER);
  } else if (strcmp(method, "drag") == 0) {
    GdkEvent* event = gtk_get_current_event();
    gdouble x = 0, y = 0;
    if (!event || !gdk_event_get_root_coords(event, &x, &y)) {
      if (event) gdk_event_free(event);
      fl_method_call_respond_error(call, "NO_POINTER_EVENT", "No drag event", nullptr, nullptr);
      return;
    }
    gtk_window_begin_move_drag(window, 1, static_cast<int>(x), static_cast<int>(y),
                               gdk_event_get_time(event));
    gdk_event_free(event);
  } else if (strcmp(method, "setToolWindow") == 0) {
    const bool tool = !args || fl_value_get_type(args) != FL_VALUE_TYPE_BOOL ||
                      fl_value_get_bool(args);
    gtk_window_set_skip_taskbar_hint(window, tool);
    gtk_window_set_skip_pager_hint(window, tool);
  } else {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  g_autoptr(FlValue) value = fl_value_new_bool(response);
  fl_method_call_respond_success(call, value, nullptr);
}
}  // namespace

void register_window_controls(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "GotoIMWindowControls");
  FlView* view = fl_plugin_registrar_get_view(registrar);
  if (!view || g_object_get_data(G_OBJECT(view), "gotoim-window-channel")) return;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  FlMethodChannel* channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar), "gotoim/window", FL_METHOD_CODEC(codec));
  GWeakRef* ref = g_new0(GWeakRef, 1);
  g_weak_ref_init(ref, G_OBJECT(view));
  fl_method_channel_set_method_call_handler(channel, handle, ref, [](gpointer data) {
    auto* ref = static_cast<GWeakRef*>(data);
    g_weak_ref_clear(ref);
    g_free(ref);
  });
  g_object_set_data_full(G_OBJECT(view), "gotoim-window-channel", channel, g_object_unref);
}
