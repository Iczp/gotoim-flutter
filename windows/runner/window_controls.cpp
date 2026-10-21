#include "window_controls.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <commctrl.h>
#include "resource.h"
#include <string>
#include <memory>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

static HWND g_main_window = nullptr;

void SetMainWindowHandle(HWND hwnd) {
  g_main_window = hwnd;
}

HWND GetMainWindowHandle() {
  return g_main_window;
}

void CenterWindowOnMonitor(HWND hwnd, HWND ref_hwnd = nullptr, int desired_w = 0, int desired_h = 0) {
  if (!hwnd || !IsWindow(hwnd)) return;

  HMONITOR monitor = nullptr;
  if (ref_hwnd && IsWindow(ref_hwnd) && IsWindowVisible(ref_hwnd) && !IsIconic(ref_hwnd)) {
    monitor = MonitorFromWindow(ref_hwnd, MONITOR_DEFAULTTONEAREST);
  } else {
    POINT cursor;
    if (GetCursorPos(&cursor)) {
      monitor = MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY);
    } else {
      monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    }
  }

  MONITORINFO info{sizeof(MONITORINFO)};
  if (!GetMonitorInfo(monitor, &info)) {
    return;
  }

  const UINT dpi = GetDpiForWindow(hwnd);
  RECT cur_rc;
  GetWindowRect(hwnd, &cur_rc);

  int width = (desired_w > 0) ? MulDiv(desired_w, dpi, 96) : (cur_rc.right - cur_rc.left);
  int height = (desired_h > 0) ? MulDiv(desired_h, dpi, 96) : (cur_rc.bottom - cur_rc.top);

  int work_w = info.rcWork.right - info.rcWork.left;
  int work_h = info.rcWork.bottom - info.rcWork.top;

  if (width > work_w) width = work_w;
  if (height > work_h) height = work_h;

  int x = info.rcWork.left + (work_w - width) / 2;
  int y = info.rcWork.top + (work_h - height) / 2;

  SetWindowPos(hwnd, nullptr, x, y, width, height,
               SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
}

static LRESULT CALLBACK ChildViewSubclassProc(
    HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam,
    UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
  if (uMsg == WM_NCHITTEST) {
    HWND top_hwnd = GetAncestor(hwnd, GA_ROOT);
    if (top_hwnd && IsWindow(top_hwnd) && !IsZoomed(top_hwnd)) {
      const LONG_PTR style = GetWindowLongPtr(top_hwnd, GWL_STYLE);
      if (style & WS_THICKFRAME) {
        RECT rc;
        if (GetWindowRect(top_hwnd, &rc)) {
          const int border = 8;
          const int sx = static_cast<short>(LOWORD(lParam));
          const int sy = static_cast<short>(HIWORD(lParam));
          if (sx < rc.left + border || sx >= rc.right - border ||
              sy < rc.top + border || sy >= rc.bottom - border) {
            return HTTRANSPARENT;
          }
        }
      }
    }
  }
  return DefSubclassProc(hwnd, uMsg, wParam, lParam);
}

void AttachChildViewResizeSubclass(HWND child_hwnd) {
  if (child_hwnd && IsWindow(child_hwnd)) {
    SetWindowSubclass(child_hwnd, ChildViewSubclassProc, 2001, 0);
  }
}

LRESULT CALLBACK SubWindowSubclassProc(
    HWND hwnd, UINT uMsg, WPARAM wParam, LPARAM lParam,
    UINT_PTR uIdSubclass, DWORD_PTR dwRefData) {
  switch (uMsg) {
    case WM_NCCALCSIZE: {
      if (wParam == TRUE) {
        auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lParam);
        if (IsZoomed(hwnd)) {
          HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
          MONITORINFO monitor_info{sizeof(MONITORINFO)};
          if (GetMonitorInfo(monitor, &monitor_info)) {
            params->rgrc[0] = monitor_info.rcWork;
          }
        }
        return 0;
      }
      return 0;
    }
    case WM_NCACTIVATE: {
      return DefSubclassProc(hwnd, WM_NCACTIVATE, wParam, -1);
    }
    case WM_NCPAINT: {
      return 0;
    }
    case WM_NCHITTEST: {
      if (IsZoomed(hwnd)) return DefSubclassProc(hwnd, uMsg, wParam, lParam);
      const LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
      if (!(style & WS_THICKFRAME)) return DefSubclassProc(hwnd, uMsg, wParam, lParam);

      const int border = 8;
      const int x = static_cast<short>(LOWORD(lParam));
      const int y = static_cast<short>(HIWORD(lParam));
      RECT rc;
      GetWindowRect(hwnd, &rc);

      const bool left = x < rc.left + border;
      const bool right = x >= rc.right - border;
      const bool top = y < rc.top + border;
      const bool bottom = y >= rc.bottom - border;

      if (top && left) return HTTOPLEFT;
      if (top && right) return HTTOPRIGHT;
      if (bottom && left) return HTBOTTOMLEFT;
      if (bottom && right) return HTBOTTOMRIGHT;
      if (left) return HTLEFT;
      if (right) return HTRIGHT;
      if (top) return HTTOP;
      if (bottom) return HTBOTTOM;
      return DefSubclassProc(hwnd, uMsg, wParam, lParam);
    }
    case WM_WINDOWPOSCHANGED: {
      auto* pos = reinterpret_cast<WINDOWPOS*>(lParam);
      if (!(pos->flags & SWP_NOSIZE)) {
        HWND child = GetWindow(hwnd, GW_CHILD);
        if (child) {
          RECT rc;
          GetClientRect(hwnd, &rc);
          MoveWindow(child, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
        }
      }
      break;
    }
    case WM_SHOWWINDOW: {
      if (wParam == FALSE) {
        HWND main = GetMainWindowHandle();
        if (main && IsWindow(main) && !IsWindowEnabled(main)) {
          EnableWindow(main, TRUE);
          SetForegroundWindow(main);
        }
      }
      break;
    }
    case WM_DESTROY: {
      HWND main = GetMainWindowHandle();
      if (main && IsWindow(main)) {
        EnableWindow(main, TRUE);
        SetForegroundWindow(main);
      }
      RemoveWindowSubclass(hwnd, SubWindowSubclassProc, uIdSubclass);
      break;
    }
  }
  return DefSubclassProc(hwnd, uMsg, wParam, lParam);
}

void ConfigureSubWindowNative(HWND sub_hwnd, HWND child_hwnd) {
  if (!sub_hwnd || !IsWindow(sub_hwnd)) return;
  const LONG_PTR style = GetWindowLongPtr(sub_hwnd, GWL_STYLE);
  const LONG_PTR custom = (style & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)) | WS_THICKFRAME | WS_CLIPCHILDREN;
  if (style != custom) {
    SetWindowLongPtr(sub_hwnd, GWL_STYLE, custom);
  }
  SetWindowSubclass(sub_hwnd, SubWindowSubclassProc, 1001, 0);
  if (child_hwnd && IsWindow(child_hwnd)) {
    AttachChildViewResizeSubclass(child_hwnd);
  }
  const MARGINS margins = {0, 0, 0, 1};
  DwmExtendFrameIntoClientArea(sub_hwnd, &margins);
  const int corner_pref = DWMWCP_ROUND;
  DwmSetWindowAttribute(sub_hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner_pref, sizeof(corner_pref));
  CenterWindowOnMonitor(sub_hwnd, g_main_window);
  if (child_hwnd && IsWindow(child_hwnd)) {
    RECT rc;
    GetClientRect(sub_hwnd, &rc);
    MoveWindow(child_hwnd, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
  }
}

namespace {
constexpr UINT kTrayCallback = WM_APP + 0x48;
constexpr UINT kShowTrayMenu = WM_APP + 0x49;
std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int count = MultiByteToWideChar(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(count, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), result.data(), count);
  return result;
}
class WindowControls : public flutter::Plugin {
 public:
  explicit WindowControls(flutter::PluginRegistrarWindows* registrar, HWND explicit_hwnd = nullptr)
      : registrar_(registrar),
        explicit_hwnd_(explicit_hwnd),
        channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "gotoim/window",
            &flutter::StandardMethodCodec::GetInstance())) {
    Configure();
    delegate_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
            -> std::optional<LRESULT> {
          if (hwnd == Window() && message == WM_NCCALCSIZE) {
            if (wparam == TRUE) {
              auto* params = reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam);
              if (IsZoomed(hwnd)) {
                HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
                MONITORINFO monitor_info{sizeof(MONITORINFO)};
                if (GetMonitorInfo(monitor, &monitor_info)) {
                  params->rgrc[0] = monitor_info.rcWork;
                }
              }
              return 0;
            }
            return 0;
          }
          if (hwnd == Window() && message == WM_NCACTIVATE) {
            return DefWindowProc(hwnd, WM_NCACTIVATE, wparam, -1);
          }
          if (hwnd == Window() && message == WM_NCPAINT) {
            return 0;
          }
          if (hwnd == Window() && message == WM_NCHITTEST) {
            if (IsZoomed(hwnd)) return HTCLIENT;
            const LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
            if (!(style & WS_THICKFRAME)) return HTCLIENT;

            const int border = 8;
            const int x = static_cast<short>(LOWORD(lparam));
            const int y = static_cast<short>(HIWORD(lparam));
            RECT rc;
            GetWindowRect(hwnd, &rc);

            const bool left = x < rc.left + border;
            const bool right = x >= rc.right - border;
            const bool top = y < rc.top + border;
            const bool bottom = y >= rc.bottom - border;

            if (top && left) return HTTOPLEFT;
            if (top && right) return HTTOPRIGHT;
            if (bottom && left) return HTBOTTOMLEFT;
            if (bottom && right) return HTBOTTOMRIGHT;
            if (left) return HTLEFT;
            if (right) return HTRIGHT;
            if (top) return HTTOP;
            if (bottom) return HTBOTTOM;
            return HTCLIENT;
          }
          if (hwnd == Window() && message == kTrayCallback) {
            if (lparam == WM_LBUTTONUP) TrayEvent("left");
            if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) ShowTrayMenu();
            return 0;
          }
          if (hwnd == Window() && message == kShowTrayMenu) {
            ShowTrayMenu();
            return 0;
          }
          if (hwnd == Window() && auto_hide_ && message == WM_ACTIVATE &&
              LOWORD(wparam) == WA_INACTIVE && IsWindowVisible(hwnd)) {
            ShowWindow(hwnd, SW_HIDE);
            channel_->InvokeMethod("closeRequested", nullptr);
          }
          if (hwnd == Window() && message == WM_CLOSE && !allow_destroy_) {
            if (is_modal_ && g_main_window && IsWindow(g_main_window)) {
              EnableWindow(g_main_window, TRUE);
              SetForegroundWindow(g_main_window);
            }
            // Cached engines stay alive. Dart updates the window registry.
            ShowWindow(hwnd, SW_HIDE);
            channel_->InvokeMethod("closeRequested", nullptr);
            return 0;
          }
          return std::nullopt;
        });
    channel_->SetMethodCallHandler([this](const auto& call, auto result) {
      HWND hwnd = Window();
      if (!hwnd || !IsWindow(hwnd)) {
        result->Error("WINDOW_UNAVAILABLE", "Engine view has no window");
        return;
      }
      const auto& method = call.method_name();
      if (method == "trayInitialize") {
        if (!tray_active_) {
          tray_ = {};
          tray_.cbSize = sizeof(tray_);
          tray_.hWnd = hwnd;
          tray_.uID = 1;
          tray_.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
          tray_.uCallbackMessage = kTrayCallback;
          tray_.hIcon = LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON));
          wcsncpy_s(tray_.szTip, L"Goto IM", _TRUNCATE);
          if (!Shell_NotifyIcon(NIM_ADD, &tray_)) {
            result->Error("TRAY_ADD_FAILED", "Windows notification area rejected icon");
            return;
          }
          tray_active_ = true;
        }
      } else if (method == "trayUpdate") {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (!tray_active_ || !args) {
          result->Error("TRAY_UNAVAILABLE", "Initialize the main tray first");
          return;
        }
        const auto read = [args](const char* key) -> const flutter::EncodableValue* {
          auto it = args->find(flutter::EncodableValue(key));
          return it == args->end() ? nullptr : &it->second;
        };
        if (const auto* value = read("unread")) {
          if (const auto* count = std::get_if<int32_t>(value)) tray_unread_ = *count;
        }
        if (const auto* value = read("owner")) {
          if (const auto* owner = std::get_if<std::string>(value)) tray_owner_ = Wide(*owner);
        }
        if (const auto* value = read("tooltip")) {
          if (const auto* tip = std::get_if<std::string>(value)) {
            wcsncpy_s(tray_.szTip, Wide(*tip).c_str(), _TRUNCATE);
          }
        }
        HICON next_icon = nullptr;
        bool next_owned = false;
        if (const auto* value = read("iconPath")) {
          if (const auto* path = std::get_if<std::string>(value)) {
            next_icon = path->empty()
                ? LoadIcon(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON))
                : static_cast<HICON>(LoadImage(nullptr, Wide(*path).c_str(),
                    IMAGE_ICON, 32, 32, LR_LOADFROMFILE));
            next_owned = !path->empty();
            if (!next_icon) {
              result->Error("TRAY_ICON_FAILED", "Cannot load ICO image");
              return;
            }
          }
        }
        const HICON old = tray_.hIcon;
        const bool old_owned = tray_icon_owned_;
        if (next_icon) {
          tray_.hIcon = next_icon;
          tray_icon_owned_ = next_owned;
        }
        if (!Shell_NotifyIcon(NIM_MODIFY, &tray_)) {
          if (next_icon && next_owned) DestroyIcon(next_icon);
          tray_.hIcon = old;
          tray_icon_owned_ = old_owned;
          result->Error("TRAY_UPDATE_FAILED", "Windows rejected tray update");
          return;
        }
        if (next_icon && old_owned) DestroyIcon(old);
      } else if (method == "trayMenu") {
        PostMessage(hwnd, kShowTrayMenu, 0, 0);
      } else if (method == "trayDestroy") {
        DestroyTray();
      } else if (method == "configure") {
        Configure();
      } else if (method == "drag") {
        POINT cursor;
        GetCursorPos(&cursor);
        ReleaseCapture();
        // Reply before entering the native move loop; never block Dart's UI.
        PostMessage(hwnd, WM_NCLBUTTONDOWN, HTCAPTION,
                    MAKELPARAM(cursor.x, cursor.y));
      } else if (method == "minimize") {
        ShowWindow(hwnd, SW_MINIMIZE);
      } else if (method == "toggleMaximize") {
        ShowWindow(hwnd, IsZoomed(hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      } else if (method == "restore") {
        ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
        SetForegroundWindow(hwnd);
      } else if (method == "hide") {
        if (is_modal_ && g_main_window && IsWindow(g_main_window)) {
          EnableWindow(g_main_window, TRUE);
          SetForegroundWindow(g_main_window);
        }
        ShowWindow(hwnd, SW_HIDE);
      } else if (method == "close") {
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      } else if (method == "destroy") {
        allow_destroy_ = true;
        PostMessage(hwnd, WM_CLOSE, 0, 0);
      } else if (method == "center") {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        int w = 0, h = 0;
        if (args) {
          const auto read_dim = [args](const char* key, int def) -> int {
            auto it = args->find(flutter::EncodableValue(key));
            if (it != args->end()) {
              if (const auto* val_i = std::get_if<int32_t>(&it->second)) return *val_i;
              if (const auto* val_l = std::get_if<int64_t>(&it->second)) return static_cast<int>(*val_l);
              if (const auto* val_d = std::get_if<double>(&it->second)) return static_cast<int>(*val_d);
            }
            return def;
          };
          w = read_dim("width", 0);
          h = read_dim("height", 0);
        }
        CenterWindowOnMonitor(hwnd, (hwnd != g_main_window) ? g_main_window : nullptr, w, h);
      } else if (method == "pin") {
        const bool* pinned = call.arguments()
            ? std::get_if<bool>(call.arguments()) : nullptr;
        SetWindowPos(hwnd, pinned && *pinned ? HWND_TOPMOST : HWND_NOTOPMOST,
                     0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
      } else if (method == "setModal") {
        const bool* modal = call.arguments()
            ? std::get_if<bool>(call.arguments()) : nullptr;
        is_modal_ = modal && *modal;
        if (is_modal_) {
          LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
          style &= ~(WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_CAPTION | WS_SYSMENU);
          style |= WS_THICKFRAME;
          SetWindowLongPtr(hwnd, GWL_STYLE, style);
          const int corner_pref = DWMWCP_ROUND;
          DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner_pref, sizeof(corner_pref));
          if (g_main_window && IsWindow(g_main_window) && g_main_window != hwnd) {
            SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window));
            EnableWindow(g_main_window, FALSE);
          }
          const UINT dpi = GetDpiForWindow(hwnd);
          const int physical_w = MulDiv(720, dpi, 96);
          const int physical_h = MulDiv(560, dpi, 96);
          int x = 0;
          int y = 0;
          if (g_main_window && IsWindow(g_main_window)) {
            RECT main_rc;
            GetWindowRect(g_main_window, &main_rc);
            x = main_rc.left + ((main_rc.right - main_rc.left) - physical_w) / 2;
            y = main_rc.top + ((main_rc.bottom - main_rc.top) - physical_h) / 2;
          } else {
            HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
            MONITORINFO info{sizeof(MONITORINFO)};
            GetMonitorInfo(monitor, &info);
            x = info.rcWork.left + ((info.rcWork.right - info.rcWork.left) - physical_w) / 2;
            y = info.rcWork.top + ((info.rcWork.bottom - info.rcWork.top) - physical_h) / 2;
          }
          SetWindowPos(hwnd, HWND_TOP, x, y, physical_w, physical_h,
                       SWP_FRAMECHANGED | SWP_SHOWWINDOW);
          SetForegroundWindow(hwnd);
        } else {
          if (g_main_window && IsWindow(g_main_window)) {
            EnableWindow(g_main_window, TRUE);
            SetForegroundWindow(g_main_window);
          }
        }
      } else if (method == "setToolWindow") {
        const bool* enable = call.arguments()
            ? std::get_if<bool>(call.arguments()) : nullptr;
        bool is_tool = enable ? *enable : true;
        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        if (is_tool) {
          ex_style = (ex_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
        } else {
          ex_style = (ex_style & ~WS_EX_TOOLWINDOW) | WS_EX_APPWINDOW;
        }
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
        if (g_main_window && IsWindow(g_main_window) && hwnd != g_main_window) {
          SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window));
        }
        SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED | SWP_NOACTIVATE);
      } else if (method == "trayFlyout") {
        auto_hide_ = true;
        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        if ((ex_style & WS_EX_TOOLWINDOW) == 0 || (ex_style & WS_EX_APPWINDOW) != 0) {
          ex_style = (ex_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
          SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
        }
        if (g_main_window && IsWindow(g_main_window) && hwnd != g_main_window) {
          SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window));
        }
        POINT cursor;
        GetCursorPos(&cursor);
        MONITORINFO monitor{sizeof(MONITORINFO)};
        GetMonitorInfo(MonitorFromPoint(cursor, MONITOR_DEFAULTTONEAREST),
                       &monitor);
        const UINT dpi = GetDpiForWindow(hwnd);
        const int width = MulDiv(400, dpi, 96);
        const int height = MulDiv(600, dpi, 96);
        const RECT& work = monitor.rcWork;
        SetWindowPos(hwnd, HWND_TOPMOST, work.right - width - 8,
                     work.bottom - height - 8, width, height, SWP_SHOWWINDOW);
        SetForegroundWindow(hwnd);
      } else if (method == "positionFlyout") {
        auto_hide_ = true;
        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        if ((ex_style & WS_EX_TOOLWINDOW) == 0 || (ex_style & WS_EX_APPWINDOW) != 0) {
          ex_style = (ex_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
          SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);
        }
        if (g_main_window && IsWindow(g_main_window) && hwnd != g_main_window) {
          SetWindowLongPtr(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window));
        }
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (args) {
          const auto read_num = [args](const char* key, int def) -> int {
            auto it = args->find(flutter::EncodableValue(key));
            if (it != args->end()) {
              if (const auto* val_i = std::get_if<int32_t>(&it->second)) return *val_i;
              if (const auto* val_l = std::get_if<int64_t>(&it->second)) return static_cast<int>(*val_l);
              if (const auto* val_d = std::get_if<double>(&it->second)) return static_cast<int>(*val_d);
            }
            return def;
          };
          const int x = read_num("x", 0);
          const int y = read_num("y", 0);
          const int w = read_num("width", 380);
          const int h = read_num("height", 420);
          bool no_activate = true;
          auto no_act_it = args->find(flutter::EncodableValue("noActivate"));
          if (no_act_it != args->end()) {
            if (const auto* b = std::get_if<bool>(&no_act_it->second)) no_activate = *b;
          }
          SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h,
                       SWP_SHOWWINDOW | (no_activate ? SWP_NOACTIVATE : 0));
          if (!no_activate) {
            SetForegroundWindow(hwnd);
          }
        }
      } else if (method == "getWindowRect") {
        RECT rc;
        GetWindowRect(hwnd, &rc);
        POINT pt{0, 0};
        ClientToScreen(hwnd, &pt);
        RECT client_rc;
        GetClientRect(hwnd, &client_rc);
        flutter::EncodableMap result_map;
        result_map[flutter::EncodableValue("left")] = flutter::EncodableValue(static_cast<int32_t>(rc.left));
        result_map[flutter::EncodableValue("top")] = flutter::EncodableValue(static_cast<int32_t>(rc.top));
        result_map[flutter::EncodableValue("right")] = flutter::EncodableValue(static_cast<int32_t>(rc.right));
        result_map[flutter::EncodableValue("bottom")] = flutter::EncodableValue(static_cast<int32_t>(rc.bottom));
        result_map[flutter::EncodableValue("clientLeft")] = flutter::EncodableValue(static_cast<int32_t>(pt.x));
        result_map[flutter::EncodableValue("clientTop")] = flutter::EncodableValue(static_cast<int32_t>(pt.y));
        result_map[flutter::EncodableValue("clientWidth")] = flutter::EncodableValue(static_cast<int32_t>(client_rc.right - client_rc.left));
        result_map[flutter::EncodableValue("clientHeight")] = flutter::EncodableValue(static_cast<int32_t>(client_rc.bottom - client_rc.top));
        const UINT dpi = GetDpiForWindow(hwnd);
        result_map[flutter::EncodableValue("dpi")] = flutter::EncodableValue(static_cast<int32_t>(dpi));
        result->Success(flutter::EncodableValue(result_map));
        return;
      } else {
        result->NotImplemented();
        return;
      }
      result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
    });
  }
  ~WindowControls() override {
    if (is_modal_ && g_main_window && IsWindow(g_main_window)) {
      EnableWindow(g_main_window, TRUE);
      SetForegroundWindow(g_main_window);
    }
    DestroyTray();
    registrar_->UnregisterTopLevelWindowProcDelegate(delegate_);
  }
 private:
  void TrayEvent(const std::string& event) {
    channel_->InvokeMethod("trayEvent", std::make_unique<flutter::EncodableValue>(event));
  }
  void DestroyTray() {
    if (tray_active_) Shell_NotifyIcon(NIM_DELETE, &tray_);
    tray_active_ = false;
    if (tray_icon_owned_ && tray_.hIcon) DestroyIcon(tray_.hIcon);
    tray_icon_owned_ = false;
    tray_.hIcon = nullptr;
  }
  void ShowTrayMenu() {
    if (!tray_active_) return;
    HMENU menu = CreatePopupMenu();
    AppendMenu(menu, MF_STRING, 1, L"打开 Goto IM");
    if (tray_unread_ > 0) {
      const std::wstring label = L"查看未读消息 (" + std::to_wstring(tray_unread_) + L")";
      AppendMenu(menu, MF_STRING, 2, label.c_str());
    }
    AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
    const std::wstring owner = tray_owner_.empty() ? L"Goto IM" : L"当前身份: " + tray_owner_;
    AppendMenu(menu, MF_STRING | MF_GRAYED, 0, owner.c_str());
    AppendMenu(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenu(menu, MF_STRING, 3, L"退出应用");
    POINT cursor;
    GetCursorPos(&cursor);
    SetForegroundWindow(Window());
    const UINT selected = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
        cursor.x, cursor.y, 0, Window(), nullptr);
    DestroyMenu(menu);
    PostMessage(Window(), WM_NULL, 0, 0);
    if (selected == 1) TrayEvent("show");
    if (selected == 2) TrayEvent("unread");
    if (selected == 3) TrayEvent("exit");
  }
  HWND Window() const {
    if (explicit_hwnd_ && IsWindow(explicit_hwnd_)) {
      return explicit_hwnd_;
    }
    auto* view = registrar_->GetView();
    return view ? GetAncestor(view->GetNativeWindow(), GA_ROOT) : nullptr;
  }
  void Configure() {
    HWND hwnd = Window();
    if (!hwnd || configured_window_ == hwnd) return;
    configured_window_ = hwnd;
    const LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
    const LONG_PTR custom = (style & ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)) | WS_THICKFRAME | WS_CLIPCHILDREN;
    if (style != custom) {
      SetWindowLongPtr(hwnd, GWL_STYLE, custom);
      SetWindowPos(hwnd, nullptr, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED |
                   SWP_NOACTIVATE);
    }
    const MARGINS margins = {0, 0, 0, 1};
    DwmExtendFrameIntoClientArea(hwnd, &margins);
    const int corner_pref = DWMWCP_ROUND;
    DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corner_pref, sizeof(corner_pref));
    if (hwnd == g_main_window) {
      RECT rc;
      GetWindowRect(hwnd, &rc);
      if (rc.left <= 20 && rc.top <= 20) {
        CenterWindowOnMonitor(hwnd, nullptr);
      }
    }
  }
  flutter::PluginRegistrarWindows* registrar_;
  HWND explicit_hwnd_ = nullptr;
  bool is_modal_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  int delegate_ = -1;
  HWND configured_window_ = nullptr;
  bool allow_destroy_ = false;
  bool auto_hide_ = false;
  NOTIFYICONDATA tray_{};
  bool tray_active_ = false;
  bool tray_icon_owned_ = false;
  int tray_unread_ = 0;
  std::wstring tray_owner_;
};
}
void RegisterWindowControls(flutter::FlutterEngine* engine, HWND explicit_hwnd) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          engine->GetRegistrarForPlugin("GotoIMWindowControls"));
  registrar->AddPlugin(std::make_unique<WindowControls>(registrar, explicit_hwnd));
}
