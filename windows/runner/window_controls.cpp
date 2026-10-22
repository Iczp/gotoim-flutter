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
#include <unordered_map>
#include <iostream>
#include <cstdarg>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

static HWND g_main_window = nullptr;
static HWND g_main_child_content = nullptr;

static void DockLog(const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  OutputDebugStringA(buffer);
  std::cout << buffer << std::endl;
}

struct WindowStateSnapshot {
  LONG_PTR style = 0;
  LONG_PTR ex_style = 0;
  HWND original_parent = nullptr;
  WINDOWPLACEMENT placement{ sizeof(WINDOWPLACEMENT) };
  bool is_docked = false;
};

static std::unordered_map<HWND, WindowStateSnapshot> g_dock_snapshots;

void SetMainWindowHandle(HWND hwnd) {
  g_main_window = hwnd;
  DockLog("[BrowserDock C++] SetMainWindowHandle: 0x%p", hwnd);
}

HWND GetMainWindowHandle() {
  return g_main_window;
}

void SetMainChildContentHandle(HWND hwnd) {
  g_main_child_content = hwnd;
  if (hwnd && IsWindow(hwnd)) {
    LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
    if (!(style & WS_CLIPSIBLINGS)) {
      SetWindowLongPtr(hwnd, GWL_STYLE, style | WS_CLIPSIBLINGS);
    }
    DockLog("[BrowserDock C++] SetMainChildContentHandle: 0x%p (WS_CLIPSIBLINGS applied)", hwnd);
  }
}

HWND GetMainChildContentHandle() {
  if (g_main_child_content && IsWindow(g_main_child_content)) {
    return g_main_child_content;
  }
  if (g_main_window && IsWindow(g_main_window)) {
    return GetWindow(g_main_window, GW_CHILD);
  }
  return nullptr;
}

static void UpdateMainViewClipHole(int x, int y, int w, int h) {
  HWND child_view = GetMainChildContentHandle();
  if (!child_view || !IsWindow(child_view)) {
    DockLog("[BrowserDock C++] UpdateMainViewClipHole: child_view is invalid");
    return;
  }

  RECT rc_view;
  GetClientRect(child_view, &rc_view);
  int view_w = rc_view.right - rc_view.left;
  int view_h = rc_view.bottom - rc_view.top;

  if (view_w <= 0 || view_h <= 0 || w <= 0 || h <= 0) {
    DockLog("[BrowserDock C++] UpdateMainViewClipHole skipped (invalid dim: view=%dx%d, hole=%dx%d)",
            view_w, view_h, w, h);
    return;
  }

  HRGN full_rgn = CreateRectRgn(0, 0, view_w, view_h);
  HRGN hole_rgn = CreateRectRgn(x, y, x + w, y + h);
  HRGN final_rgn = CreateRectRgn(0, 0, 0, 0);

  CombineRgn(final_rgn, full_rgn, hole_rgn, RGN_DIFF);
  DeleteObject(full_rgn);
  DeleteObject(hole_rgn);

  if (SetWindowRgn(child_view, final_rgn, TRUE)) {
    DockLog("[BrowserDock C++] UpdateMainViewClipHole applied: view=%dx%d, hole=(%d, %d, %d, %d)",
            view_w, view_h, x, y, w, h);
  } else {
    DockLog("[BrowserDock C++] SetWindowRgn failed on child_view=0x%p, error=%lu",
            child_view, GetLastError());
    DeleteObject(final_rgn);
  }
}

static void ResetMainViewClipHole() {
  HWND child_view = GetMainChildContentHandle();
  if (child_view && IsWindow(child_view)) {
    SetWindowRgn(child_view, nullptr, TRUE);
    DockLog("[BrowserDock C++] ResetMainViewClipHole restored full rendering region");
  }
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
      HWND root = GetAncestor(hwnd, GA_ROOT);
      if (root && root != hwnd && IsWindow(root) && !IsZoomed(root)) {
        // 吸附模式下：如果鼠标在顶层主窗口的外围 8px 边框区域，穿透给顶层主窗口处理尺寸调整
        const LONG_PTR root_style = GetWindowLongPtr(root, GWL_STYLE);
        if (root_style & WS_THICKFRAME) {
          RECT rc;
          if (GetWindowRect(root, &rc)) {
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

std::string Narrow(const std::wstring& value) {
  if (value.empty()) return {};
  const int count = WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(count, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(),
      static_cast<int>(value.size()), result.data(), count, nullptr, nullptr);
  return result;
}
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
          if (hwnd == Window() && message == WM_HOTKEY) {
            if (wparam == 9001) {
              channel_->InvokeMethod("hotkey", std::make_unique<flutter::EncodableValue>("screenshot"));
              return 0;
            }
            if (wparam == 9002) {
              channel_->InvokeMethod("hotkey", std::make_unique<flutter::EncodableValue>("toggle_app"));
              return 0;
            }
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
      } else if (method == "toggleVisibility") {
        if (IsIconic(hwnd) || !IsWindowVisible(hwnd) || GetForegroundWindow() != hwnd) {
          ShowWindow(hwnd, SW_RESTORE);
          SetForegroundWindow(hwnd);
          result->Success(flutter::EncodableValue(true));
        } else {
          ShowWindow(hwnd, SW_MINIMIZE);
          result->Success(flutter::EncodableValue(false));
        }
        return;
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
      } else if (method == "captureScreen") {
        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (vw <= 0) vw = GetSystemMetrics(SM_CXSCREEN);
        if (vh <= 0) vh = GetSystemMetrics(SM_CYSCREEN);

        HDC hScreenDC = GetDC(nullptr);
        HDC hMemDC = CreateCompatibleDC(hScreenDC);
        HBITMAP hBitmap = CreateCompatibleBitmap(hScreenDC, vw, vh);
        HGDIOBJ hOld = SelectObject(hMemDC, hBitmap);
        BitBlt(hMemDC, 0, 0, vw, vh, hScreenDC, vx, vy, SRCCOPY | CAPTUREBLT);
        SelectObject(hMemDC, hOld);

        BITMAPINFO bih = {};
        bih.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
        bih.bmiHeader.biWidth = vw;
        bih.bmiHeader.biHeight = vh;
        bih.bmiHeader.biPlanes = 1;
        bih.bmiHeader.biBitCount = 32;
        bih.bmiHeader.biCompression = BI_RGB;
        DWORD row_size = ((vw * 32 + 31) / 32) * 4;
        DWORD image_size = row_size * vh;
        bih.bmiHeader.biSizeImage = image_size;

        DWORD total_file_size = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER) + image_size;
        std::vector<uint8_t> buffer(total_file_size);
        BITMAPFILEHEADER* bfh = reinterpret_cast<BITMAPFILEHEADER*>(buffer.data());
        bfh->bfType = 0x4D42; // "BM"
        bfh->bfOffBits = sizeof(BITMAPFILEHEADER) + sizeof(BITMAPINFOHEADER);
        bfh->bfSize = total_file_size;
        bfh->bfReserved1 = 0;
        bfh->bfReserved2 = 0;
        memcpy(buffer.data() + sizeof(BITMAPFILEHEADER), &bih.bmiHeader, sizeof(BITMAPINFOHEADER));

        GetDIBits(hMemDC, hBitmap, 0, vh, buffer.data() + bfh->bfOffBits, &bih, DIB_RGB_COLORS);

        DeleteObject(hBitmap);
        DeleteDC(hMemDC);
        ReleaseDC(nullptr, hScreenDC);

        wchar_t temp_dir[MAX_PATH];
        GetTempPathW(MAX_PATH, temp_dir);
        std::wstring file_path = std::wstring(temp_dir) + L"gotoim_screen_raw.bmp";
        HANDLE hFile = CreateFileW(file_path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (hFile != INVALID_HANDLE_VALUE) {
          DWORD written = 0;
          WriteFile(hFile, buffer.data(), static_cast<DWORD>(buffer.size()), &written, nullptr);
          CloseHandle(hFile);
        }

        flutter::EncodableMap res;
        res[flutter::EncodableValue("path")] = flutter::EncodableValue(Narrow(file_path));
        res[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int32_t>(vx));
        res[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int32_t>(vy));
        res[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(vw));
        res[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(vh));
        const UINT dpi = GetDpiForWindow(hwnd);
        res[flutter::EncodableValue("dpi")] = flutter::EncodableValue(static_cast<int32_t>(dpi));
        result->Success(flutter::EncodableValue(res));
        return;
      } else if (method == "showScreenCapture") {
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        int x = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int y = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (w <= 0) w = GetSystemMetrics(SM_CXSCREEN);
        if (h <= 0) h = GetSystemMetrics(SM_CYSCREEN);
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
          x = read_num("x", x);
          y = read_num("y", y);
          w = read_num("width", w);
          h = read_num("height", h);
        }

        LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
        style &= ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        style |= WS_POPUP;
        SetWindowLongPtr(hwnd, GWL_STYLE, style);

        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        ex_style = (ex_style & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW;
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

        SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h,
                     SWP_FRAMECHANGED | SWP_SHOWWINDOW);
        SetForegroundWindow(hwnd);
        result->Success(flutter::EncodableValue(true));
        return;
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
      } else if (method == "dockToParent") {
        if (!g_main_window || !IsWindow(g_main_window) || hwnd == g_main_window) {
          result->Error("MAIN_WINDOW_UNAVAILABLE", "Cannot dock: main window not available");
          return;
        }
        const auto* args = call.arguments()
            ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (!args) {
          result->Error("INVALID_ARGS", "dockToParent requires bounds arguments");
          return;
        }
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
        const int w = read_num("width", 400);
        const int h = read_num("height", 600);

        DockLog("[BrowserDock C++] dockToParent called: hwnd=0x%p, main=0x%p, (x=%d, y=%d, w=%d, h=%d)",
                hwnd, g_main_window, x, y, w, h);

        if (!g_main_window || !IsWindow(g_main_window)) {
          DockLog("[BrowserDock C++] dockToParent failed: g_main_window is null or invalid");
          result->Error("NO_MAIN_WINDOW", "Main window handle unavailable");
          return;
        }

        // 1. 保存快照（仅在未挂载时保存原始状态）
        if (g_dock_snapshots.find(hwnd) == g_dock_snapshots.end()) {
          WindowStateSnapshot snapshot;
          snapshot.style = GetWindowLongPtr(hwnd, GWL_STYLE);
          snapshot.ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
          snapshot.original_parent = GetParent(hwnd);
          GetWindowPlacement(hwnd, &snapshot.placement);
          snapshot.is_docked = true;
          g_dock_snapshots[hwnd] = snapshot;
          DockLog("[BrowserDock C++] Snapshot saved: style=0x%llx, ex_style=0x%llx, parent=0x%p",
                  snapshot.style, snapshot.ex_style, snapshot.original_parent);
        }

        // 2. 确保主窗口具有 WS_CLIPCHILDREN
        LONG_PTR main_style = GetWindowLongPtr(g_main_window, GWL_STYLE);
        if (!(main_style & WS_CLIPCHILDREN)) {
          SetWindowLongPtr(g_main_window, GWL_STYLE, main_style | WS_CLIPCHILDREN);
        }

        // 3. 剥离独立窗口样式，变更为 WS_CHILD 并补充 WS_CLIPCHILDREN | WS_CLIPSIBLINGS
        LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
        style &= ~(WS_POPUP | WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU);
        style |= (WS_CHILD | WS_CLIPCHILDREN | WS_CLIPSIBLINGS);
        SetWindowLongPtr(hwnd, GWL_STYLE, style);

        LONG_PTR ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
        ex_style &= ~WS_EX_APPWINDOW;
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, ex_style);

        // 4. 执行 SetParent，校验错误
        SetLastError(ERROR_SUCCESS);
        HWND prev_parent = SetParent(hwnd, g_main_window);
        DWORD err = GetLastError();
        if (prev_parent == nullptr && err != ERROR_SUCCESS) {
          DockLog("[BrowserDock C++] SetParent failed! error=%lu", err);
          const auto& s = g_dock_snapshots[hwnd];
          SetWindowLongPtr(hwnd, GWL_STYLE, s.style);
          SetWindowLongPtr(hwnd, GWL_EXSTYLE, s.ex_style);
          g_dock_snapshots.erase(hwnd);
          result->Error("SET_PARENT_FAILED", "Win32 SetParent failed");
          return;
        }
        DockLog("[BrowserDock C++] SetParent succeeded: prev_parent=0x%p", prev_parent);

        // 5. 坐标映射（从主 Flutter View 客户区转换到 g_main_window 客户区）
        POINT pt = {x, y};
        HWND child_view = GetMainChildContentHandle();
        if (child_view && IsWindow(child_view)) {
          MapWindowPoints(child_view, g_main_window, &pt, 1);
        }
        const int client_x = pt.x;
        const int client_y = pt.y;

        // 6. 计算有效尺寸：如果主窗口未最大化，确保不覆盖主窗口右侧与底部的 8px 调整边框
        int effective_w = w;
        int effective_h = h;
        if (g_main_window && IsWindow(g_main_window) && !IsZoomed(g_main_window)) {
          RECT rc_client;
          GetClientRect(g_main_window, &rc_client);
          const int max_w = rc_client.right - rc_client.left;
          const int max_h = rc_client.bottom - rc_client.top;
          const int border = 8;

          if (client_x + effective_w > max_w - border) {
            effective_w = max_w - border - client_x;
          }
          if (client_y + effective_h > max_h - border) {
            effective_h = max_h - border - client_y;
          }
          if (effective_w < 100) effective_w = 100;
          if (effective_h < 100) effective_h = 100;
        }

        // 7. 对主 Flutter View 设置镂空区域，防止 DirectX/Flutter 覆盖子窗口产生闪烁白屏
        UpdateMainViewClipHole(x, y, effective_w, effective_h);

        // 8. 定位子窗口并置顶在 siblings 之上
        SetWindowPos(hwnd, HWND_TOP, client_x, client_y, effective_w, effective_h,
                     SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);

        // 9. 确保子窗口内部的 Flutter View 贴合并重绘
        HWND sub_child = GetWindow(hwnd, GW_CHILD);
        if (sub_child && IsWindow(sub_child)) {
          MoveWindow(sub_child, 0, 0, effective_w, effective_h, TRUE);
          InvalidateRect(sub_child, NULL, TRUE);
          UpdateWindow(sub_child);
        }
        InvalidateRect(hwnd, NULL, TRUE);
        UpdateWindow(hwnd);

        // 10. 独立浏览器切换吸附到主窗口时，确保主窗口恢复显示并激活置顶
        if (g_main_window && IsWindow(g_main_window)) {
          if (IsIconic(g_main_window)) {
            ShowWindow(g_main_window, SW_RESTORE);
          } else if (!IsWindowVisible(g_main_window)) {
            ShowWindow(g_main_window, SW_SHOW);
          }
          SetForegroundWindow(g_main_window);
        }

        DockLog("[BrowserDock C++] dockToParent complete: client=(%d, %d), size=(%d, %d)",
                client_x, client_y, effective_w, effective_h);
        result->Success(flutter::EncodableValue(true));
        return;
      } else if (method == "updateDockedBounds") {
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
          const int w = read_num("width", 400);
          const int h = read_num("height", 600);

          POINT pt = {x, y};
          HWND child_view = GetMainChildContentHandle();
          if (child_view && IsWindow(child_view) && g_main_window && IsWindow(g_main_window)) {
            MapWindowPoints(child_view, g_main_window, &pt, 1);
          }
          const int client_x = pt.x;
          const int client_y = pt.y;

          int effective_w = w;
          int effective_h = h;
          if (g_main_window && IsWindow(g_main_window) && !IsZoomed(g_main_window)) {
            RECT rc_client;
            GetClientRect(g_main_window, &rc_client);
            const int max_w = rc_client.right - rc_client.left;
            const int max_h = rc_client.bottom - rc_client.top;
            const int border = 8;

            if (client_x + effective_w > max_w - border) {
              effective_w = max_w - border - client_x;
            }
            if (client_y + effective_h > max_h - border) {
              effective_h = max_h - border - client_y;
            }
            if (effective_w < 100) effective_w = 100;
            if (effective_h < 100) effective_h = 100;
          }

          UpdateMainViewClipHole(x, y, effective_w, effective_h);

          SetWindowPos(hwnd, HWND_TOP, client_x, client_y, effective_w, effective_h,
                       SWP_NOACTIVATE);

          HWND sub_child = GetWindow(hwnd, GW_CHILD);
          if (sub_child && IsWindow(sub_child)) {
            MoveWindow(sub_child, 0, 0, effective_w, effective_h, TRUE);
            InvalidateRect(sub_child, NULL, TRUE);
          }
          InvalidateRect(hwnd, NULL, TRUE);
          DockLog("[BrowserDock C++] updateDockedBounds: (x=%d, y=%d, w=%d, h=%d) -> client=(%d, %d), effective=(%d, %d)",
                  x, y, w, h, client_x, client_y, effective_w, effective_h);
        }
        result->Success(flutter::EncodableValue(true));
        return;
      } else if (method == "undockFromParent") {
        DockLog("[BrowserDock C++] undockFromParent called: hwnd=0x%p", hwnd);
        auto it = g_dock_snapshots.find(hwnd);
        if (it != g_dock_snapshots.end() && it->second.is_docked) {
          const auto& s = it->second;

          // 1. 恢复主窗口的完整渲染区域
          ResetMainViewClipHole();

          // 2. 恢复父窗口
          SetParent(hwnd, s.original_parent);

          // 3. 严格恢复保存的原始 style 和 ex_style
          SetWindowLongPtr(hwnd, GWL_STYLE, s.style);
          SetWindowLongPtr(hwnd, GWL_EXSTYLE, s.ex_style);

          // 4. 恢复原始位置与状态并置顶激活
          SetWindowPlacement(hwnd, &s.placement);
          SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
          SetForegroundWindow(hwnd);

          HWND sub_child = GetWindow(hwnd, GW_CHILD);
          if (sub_child && IsWindow(sub_child)) {
            RECT rc;
            GetClientRect(hwnd, &rc);
            MoveWindow(sub_child, 0, 0, rc.right - rc.left, rc.bottom - rc.top, TRUE);
            InvalidateRect(sub_child, NULL, TRUE);
          }
          InvalidateRect(hwnd, NULL, TRUE);

          g_dock_snapshots.erase(it);
          DockLog("[BrowserDock C++] undockFromParent complete");
          result->Success(flutter::EncodableValue(true));
          return;
        }
        DockLog("[BrowserDock C++] undockFromParent: hwnd not in docked snapshots");
        result->Success(flutter::EncodableValue(false));
        return;
      } else if (method == "isDocked") {
        auto it = g_dock_snapshots.find(hwnd);
        bool docked = (it != g_dock_snapshots.end() && it->second.is_docked);
        DockLog("[BrowserDock C++] isDocked query: hwnd=0x%p, docked=%s", hwnd, docked ? "true" : "false");
        result->Success(flutter::EncodableValue(docked));
        return;
      } else {
        result->NotImplemented();
        return;
      }
      result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
    });
  }
  ~WindowControls() override {
    if (Window() == g_main_window && g_main_window) {
      UnregisterHotKey(g_main_window, 9001);
      UnregisterHotKey(g_main_window, 9002);
    }
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
      RegisterHotKey(hwnd, 9001, MOD_ALT | 0x4000, 'A');
      RegisterHotKey(hwnd, 9002, MOD_ALT | 0x4000, 'W');
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
