#include "window_controls.h"
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>
#include <dwmapi.h>
#include <commctrl.h>
#include "resource.h"
#include "profile_flyout_policy.h"
#include "window_resize_policy.h"
#include <string>
#include <memory>
#include <algorithm>
#include <unordered_map>
#include <utility>
#include <vector>
#include <iostream>
#include <cstdarg>

#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "dwmapi.lib")

#ifndef DWMWA_WINDOW_CORNER_PREFERENCE
#define DWMWA_WINDOW_CORNER_PREFERENCE 33
#endif
#ifndef DWMWCP_DONOTROUND
#define DWMWCP_DONOTROUND 1
#endif
#ifndef DWMWCP_ROUND
#define DWMWCP_ROUND 2
#endif

static HWND g_main_window = nullptr;
static HWND g_main_child_content = nullptr;

// EnumWindows visits top-level windows in front-to-back Z order. Snapshot the
// geometry before showing the capture overlay, so it cannot select itself.
static flutter::EncodableList CaptureWindowRegions(const RECT& desktop) {
  struct Context {
    RECT desktop;
    flutter::EncodableList regions;
  } context{desktop, {}};
  EnumWindows([](HWND window, LPARAM parameter) -> BOOL {
    auto& context = *reinterpret_cast<Context*>(parameter);
    if (!IsWindowVisible(window) || IsIconic(window)) return TRUE;
    const auto ex_style = GetWindowLongPtr(window, GWL_EXSTYLE);
    if (ex_style & (WS_EX_TRANSPARENT | WS_EX_NOACTIVATE)) return TRUE;
    DWORD cloaked = 0;
    if (SUCCEEDED(DwmGetWindowAttribute(window, DWMWA_CLOAKED,
                                       &cloaked, sizeof(cloaked))) && cloaked) return TRUE;
    wchar_t class_name[128]{};
    GetClassNameW(window, class_name, 128);
    if (wcscmp(class_name, L"Progman") == 0 ||
        wcscmp(class_name, L"WorkerW") == 0 ||
        wcscmp(class_name, L"Shell_TrayWnd") == 0 ||
        wcscmp(class_name, L"Shell_SecondaryTrayWnd") == 0) return TRUE;
    RECT bounds{};
    if (FAILED(DwmGetWindowAttribute(window, DWMWA_EXTENDED_FRAME_BOUNDS,
                                     &bounds, sizeof(bounds))) &&
        !GetWindowRect(window, &bounds)) return TRUE;
    RECT clipped{};
    if (!IntersectRect(&clipped, &bounds, &context.desktop) ||
        clipped.right - clipped.left < 16 || clipped.bottom - clipped.top < 16) return TRUE;
    flutter::EncodableMap region;
    region[flutter::EncodableValue("x")] = flutter::EncodableValue(static_cast<int32_t>(clipped.left));
    region[flutter::EncodableValue("y")] = flutter::EncodableValue(static_cast<int32_t>(clipped.top));
    region[flutter::EncodableValue("width")] = flutter::EncodableValue(static_cast<int32_t>(clipped.right - clipped.left));
    region[flutter::EncodableValue("height")] = flutter::EncodableValue(static_cast<int32_t>(clipped.bottom - clipped.top));
    context.regions.emplace_back(region);
    return TRUE;
  }, reinterpret_cast<LPARAM>(&context));
  return context.regions;
}

static void DockLog(const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  OutputDebugStringA(buffer);
  std::cout << buffer << std::endl;
}

// Docked browsers remain owned TOP-LEVEL windows. Never nest two Flutter
// views or cut a hole in the main Flutter surface.
struct WindowStateSnapshot {
  LONG_PTR style = 0;
  LONG_PTR ex_style = 0;
  HWND owner = nullptr;
  WINDOWPLACEMENT placement{sizeof(WINDOWPLACEMENT)};
  RECT bounds{}; // physical main-client coordinates
  SIZE client_size{};
  UINT dpi = 96;
  std::string slot_id = "chat:right";
};
static std::unordered_map<HWND, WindowStateSnapshot> g_dock_snapshots;
static std::unordered_map<std::string, bool> g_dock_slot_visible;
static bool g_dock_route_visible = true;

static bool IsWindowDocked(HWND hwnd) {
  return g_dock_snapshots.find(hwnd) != g_dock_snapshots.end();
}
void SetMainWindowHandle(HWND hwnd) { g_main_window = hwnd; }
HWND GetMainWindowHandle() { return g_main_window; }
void SetMainChildContentHandle(HWND hwnd) { g_main_child_content = hwnd; }
HWND GetMainChildContentHandle() { return g_main_child_content; }

static bool WriteWindowLong(HWND hwnd, int index, LONG_PTR value) {
  SetLastError(ERROR_SUCCESS);
  return SetWindowLongPtr(hwnd, index, value) != 0 || GetLastError() == ERROR_SUCCESS;
}

static bool PositionDockedWindow(HWND hwnd, const WindowStateSnapshot& snapshot) {
  RECT client{};
  if (!g_main_window || !GetClientRect(g_main_window, &client)) return false;
  const auto slot_visibility = g_dock_slot_visible.find(snapshot.slot_id);
  const bool slot_visible = slot_visibility == g_dock_slot_visible.end() || slot_visibility->second;
  const bool visible = slot_visible && g_dock_route_visible &&
      IsWindowVisible(g_main_window) && !IsIconic(g_main_window) && IsWindowEnabled(g_main_window);
  if (!visible) { ShowWindow(hwnd, SW_HIDE); return true; }
  const UINT dpi = GetDpiForWindow(g_main_window);
  const auto scale = [&snapshot, dpi](int value) { return MulDiv(value, dpi, snapshot.dpi); };
  const int width = scale(snapshot.bounds.right - snapshot.bounds.left);
  const int right_gap = scale(snapshot.client_size.cx - snapshot.bounds.right);
  const int bottom_gap = scale(snapshot.client_size.cy - snapshot.bounds.bottom);
  const int y = scale(snapshot.bounds.top);
  const int x = client.right - right_gap - width;
  const int height = client.bottom - bottom_gap - y;
  if (x < 0 || y < 0 || width <= 0 || height <= 0) {
    ShowWindow(hwnd, SW_HIDE);
    return true; // Flutter will either supply new bounds or undock for narrow layouts.
  }
  // Owned windows receive mouse input before their owner. Reserve ALL four
  // resize edges/corners so the main HWND can receive native hit tests.
  const int border_x = IsZoomed(g_main_window) ? 0 : (std::max)(MulDiv(8, dpi, 96), GetSystemMetricsForDpi(SM_CXSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi));
  const int border_y = IsZoomed(g_main_window) ? 0 : (std::max)(MulDiv(8, dpi, 96), GetSystemMetricsForDpi(SM_CYSIZEFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi));
  const int safe_x = (std::max)(x, border_x);
  const int safe_y = (std::max)(y, border_y);
  const int effective_width = (std::min)(x + width, static_cast<int>(client.right) - border_x) - safe_x;
  const int effective_height = (std::min)(y + height, static_cast<int>(client.bottom) - border_y) - safe_y;
  POINT origin{safe_x, safe_y};
  if (!ClientToScreen(g_main_window, &origin)) return false;
  if (effective_width <= 0 || effective_height <= 0) {
    ShowWindow(hwnd, SW_HIDE);
    return true;
  }
  RECT existing{};
  if (IsWindowVisible(hwnd) && GetWindowRect(hwnd, &existing) &&
      existing.left == origin.x && existing.top == origin.y &&
      existing.right - existing.left == effective_width &&
      existing.bottom - existing.top == effective_height) return true;
  return SetWindowPos(hwnd, nullptr, origin.x, origin.y, effective_width, effective_height,
      SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW) != FALSE;
}

// SetWindowPos/ShowWindow below synchronously dispatch messages that can
// re-enter the main window delegate (WM_WINDOWPOSCHANGED/WM_ENABLE) and call
// back here. Guard against recursion (stack overflow) and iterate a copy so
// that any erase during dispatch cannot invalidate the iterator.
static bool g_syncing_docked_windows = false;
static void SyncDockedWindows() {
  if (g_syncing_docked_windows || g_dock_snapshots.empty()) return;
  g_syncing_docked_windows = true;
  const std::vector<std::pair<HWND, WindowStateSnapshot>> items(
      g_dock_snapshots.begin(), g_dock_snapshots.end());
  for (const auto& [hwnd, snapshot] : items) {
    if (IsWindow(hwnd) && IsWindowDocked(hwnd)) PositionDockedWindow(hwnd, snapshot);
  }
  g_syncing_docked_windows = false;
}

static bool SaveDockBounds(HWND hwnd, int x, int y, int width, int height) {
  auto it = g_dock_snapshots.find(hwnd);
  if (it == g_dock_snapshots.end() || width <= 0 || height <= 0) return false;
  POINT origin{x, y};
  if (!g_main_child_content || !IsWindow(g_main_child_content)) return false;
  MapWindowPoints(g_main_child_content, g_main_window, &origin, 1);
  RECT client{};
  if (!GetClientRect(g_main_window, &client)) return false;
  auto& snapshot = it->second;
  snapshot.bounds = {origin.x, origin.y, origin.x + width, origin.y + height};
  snapshot.client_size = {client.right, client.bottom};
  snapshot.dpi = GetDpiForWindow(g_main_window);
  return PositionDockedWindow(hwnd, snapshot);
}

static bool RestoreDockedWindow(HWND hwnd, bool show) {
  const auto it = g_dock_snapshots.find(hwnd);
  if (it == g_dock_snapshots.end()) return true; // idempotent close/rollback
  const auto snapshot = it->second;
  // Style/placement changes dispatch owner messages synchronously. Stop dock
  // synchronization BEFORE restoring, otherwise it re-shows/resizes this HWND
  // halfway through the transaction and the Flutter surface keeps dock bounds.
  g_dock_snapshots.erase(it);
  const LONG_PTR docked_style = GetWindowLongPtr(hwnd, GWL_STYLE);
  const LONG_PTR docked_ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  const auto rollback = [&]() {
    g_dock_snapshots[hwnd] = snapshot;
    WriteWindowLong(hwnd, GWL_STYLE, docked_style);
    WriteWindowLong(hwnd, GWL_EXSTYLE, docked_ex_style);
    WriteWindowLong(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window));
    SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
        SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED);
    PositionDockedWindow(hwnd, snapshot);
    return false;
  };
  ShowWindow(hwnd, SW_HIDE);
  if (!WriteWindowLong(hwnd, GWL_STYLE, snapshot.style & ~WS_VISIBLE) ||
      !WriteWindowLong(hwnd, GWL_EXSTYLE, snapshot.ex_style) ||
      !WriteWindowLong(hwnd, GWLP_HWNDPARENT,
          reinterpret_cast<LONG_PTR>(IsWindow(snapshot.owner) ? snapshot.owner : nullptr))) return rollback();
  WINDOWPLACEMENT placement = snapshot.placement;
  placement.showCmd = SW_HIDE;
  if (!SetWindowPlacement(hwnd, &placement)) return rollback();
  const MARGINS margins{0, 0, 0, 1};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
  const int corners = DWMWCP_ROUND;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corners, sizeof(corners));
  if (!SetWindowPos(hwnd, (snapshot.ex_style & WS_EX_TOPMOST) ? HWND_TOPMOST : HWND_NOTOPMOST,
      0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED)) return rollback();
  if (show) {
    ShowWindow(hwnd, snapshot.placement.showCmd == SW_SHOWMAXIMIZED ? SW_MAXIMIZE : SW_SHOWNORMAL);
    SetForegroundWindow(hwnd);
  }
  return true;
}

static bool AttachDockedWindow(HWND hwnd, const std::string& slot_id, int x, int y, int width, int height) {
  if (!IsWindow(hwnd) || !IsWindow(g_main_window) || hwnd == g_main_window || width <= 0 || height <= 0) return false;
  // UIThreadPolicy concerns the Dart isolate, not HWND ownership. Check actual
  // platform threads before manipulating native window presentation.
  const DWORD browser_thread = GetWindowThreadProcessId(hwnd, nullptr);
  const DWORD main_thread = GetWindowThreadProcessId(g_main_window, nullptr);
  if (browser_thread != main_thread || GetCurrentThreadId() != browser_thread) return false;
  if (IsWindowDocked(hwnd)) {
    if (g_dock_snapshots.at(hwnd).slot_id != slot_id) return false;
    return SaveDockBounds(hwnd, x, y, width, height);
  }
  WindowStateSnapshot snapshot;
  snapshot.slot_id = slot_id;
  snapshot.style = GetWindowLongPtr(hwnd, GWL_STYLE);
  snapshot.ex_style = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
  snapshot.owner = GetWindow(hwnd, GW_OWNER);
  if ((snapshot.style & WS_CHILD) || !GetWindowPlacement(hwnd, &snapshot.placement)) return false;
  g_dock_snapshots.emplace(hwnd, snapshot);
  ShowWindow(hwnd, SW_HIDE);
  const LONG_PTR style = (snapshot.style & ~(WS_CHILD | WS_VISIBLE | WS_CAPTION |
      WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_MAXIMIZE | WS_MINIMIZE)) | WS_POPUP;
  const LONG_PTR ex_style = (snapshot.ex_style & ~(WS_EX_APPWINDOW | WS_EX_TOPMOST)) | WS_EX_TOOLWINDOW;
  if (!WriteWindowLong(hwnd, GWL_STYLE, style) || !WriteWindowLong(hwnd, GWL_EXSTYLE, ex_style) ||
      !WriteWindowLong(hwnd, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(g_main_window)) ||
      !SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
          SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_FRAMECHANGED) ||
      !SaveDockBounds(hwnd, x, y, width, height)) {
    RestoreDockedWindow(hwnd, (snapshot.style & WS_VISIBLE) != 0);
    return false;
  }
  const MARGINS margins{};
  DwmExtendFrameIntoClientArea(hwnd, &margins);
  const int corners = DWMWCP_DONOTROUND;
  DwmSetWindowAttribute(hwnd, DWMWA_WINDOW_CORNER_PREFERENCE, &corners, sizeof(corners));
  // An owned window stays above its owner without becoming globally topmost.
  if (!SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_NOOWNERZORDER)) {
    RestoreDockedWindow(hwnd, (snapshot.style & WS_VISIBLE) != 0);
    return false;
  }
  return true;
}

void CenterWindowOnMonitor(HWND hwnd, HWND ref_hwnd = nullptr, int desired_w = 0, int desired_h = 0) {
  if (!hwnd || !IsWindow(hwnd) || IsWindowDocked(hwnd)) return;

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
  } else if (uMsg == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, ChildViewSubclassProc, uIdSubclass);
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

      if (IsWindowDocked(hwnd) || (root && root != hwnd)) {
        return HTCLIENT;
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
    case WM_SHOWWINDOW: {
      // Docked browsers are hidden/shown by SyncDockedWindows (e.g. while a
      // modal disables the main window). Never re-enable/activate main here,
      // otherwise WM_ENABLE -> SyncDockedWindows recursion breaks modals.
      if (wParam == FALSE && !IsWindowDocked(hwnd)) {
        HWND main = GetMainWindowHandle();
        if (main && IsWindow(main) && !IsWindowEnabled(main)) {
          EnableWindow(main, TRUE);
          SetForegroundWindow(main);
        }
      }
      break;
    }
    case WM_DESTROY: {
      // Drop stale snapshot so a recycled HWND is never repositioned.
      g_dock_snapshots.erase(hwnd);
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
  const LONG_PTR custom = (style & ~WS_CAPTION) | WS_THICKFRAME | WS_CLIPCHILDREN;
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
constexpr UINT kStartWindowDrag = WM_APP + 0x4A;
constexpr UINT kUpdateWindowDrag = WM_APP + 0x4B;
constexpr UINT kRebaseWindowDrag = WM_APP + 0x4C;
constexpr UINT kUpdateWindowResize = WM_APP + 0x4D;
constexpr UINT kResizeFlutterContent = WM_APP + 0x4E;
constexpr UINT kRebaseWindowResize = WM_APP + 0x4F;

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
  explicit WindowControls(flutter::PluginRegistrarWindows* registrar, HWND explicit_hwnd = nullptr,
                          flutter::FlutterViewController* controller = nullptr)
      : registrar_(registrar),
        explicit_hwnd_(explicit_hwnd),
        view_controller_(controller),
        channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            registrar->messenger(), "gotoim/window",
            &flutter::StandardMethodCodec::GetInstance())) {
    Configure();
    delegate_ = registrar_->RegisterTopLevelWindowProcDelegate(
        [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam)
            -> std::optional<LRESULT> {
          if (hwnd == Window() && message == kResizeFlutterContent) {
            content_resize_pending_ = false;
            ApplyLatestContentSize();
            return 0;
          }
          if (hwnd == Window() && message == WM_NCLBUTTONDOWN &&
              wparam >= HTLEFT && wparam <= HTBOTTOMRIGHT && !IsWindowDocked(hwnd) &&
              !IsZoomed(hwnd) && (GetWindowLongPtr(hwnd, GWL_STYLE) & WS_THICKFRAME)) {
            if (native_drag_active_ || native_resize_active_ ||
                !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) return 0;
            if (!GetCursorPos(&resize_cursor_) || !GetWindowRect(hwnd, &resize_bounds_)) return 0;
            resize_edge_ = static_cast<UINT>(wparam);
            const UINT dpi = GetDpiForWindow(hwnd);
            MINMAXINFO limits{};
            SendMessage(hwnd, WM_GETMINMAXINFO, 0, reinterpret_cast<LPARAM>(&limits));
            resize_minimum_ = {(std::max)(limits.ptMinTrackSize.x,
                static_cast<LONG>(GetSystemMetricsForDpi(SM_CXMINTRACK, dpi))),
                (std::max)(limits.ptMinTrackSize.y,
                static_cast<LONG>(GetSystemMetricsForDpi(SM_CYMINTRACK, dpi)))};
            ReleaseCapture();
            SetCapture(hwnd);
            native_resize_active_ = GetCapture() == hwnd;
            ++resize_gestures_;
            return 0;
          }
          if (hwnd == Window() && native_resize_active_) {
            if (message == WM_SETCURSOR) {
              LPCWSTR cursor = IDC_SIZEALL;
              if (resize_edge_ == HTLEFT || resize_edge_ == HTRIGHT) cursor = IDC_SIZEWE;
              else if (resize_edge_ == HTTOP || resize_edge_ == HTBOTTOM) cursor = IDC_SIZENS;
              else if (resize_edge_ == HTTOPLEFT || resize_edge_ == HTBOTTOMRIGHT) cursor = IDC_SIZENWSE;
              else cursor = IDC_SIZENESW;
              SetCursor(LoadCursor(nullptr, cursor));
              return TRUE;
            }
            if (message == WM_MOUSEMOVE) {
              if (!resize_update_pending_) {
                resize_update_pending_ = true;
                PostMessage(hwnd, kUpdateWindowResize, 0, 0);
              }
              return 0;
            }
            if (message == kUpdateWindowResize || message == WM_LBUTTONUP) {
              resize_update_pending_ = false;
              POINT cursor{};
              bool valid = false;
              if (message == WM_LBUTTONUP) {
                cursor = {static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
                valid = ClientToScreen(hwnd, &cursor) != FALSE;
              } else if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
                valid = GetCursorPos(&cursor) != FALSE;
              }
              if (valid) {
                const RECT next = WindowResizeBounds(resize_bounds_, resize_cursor_, cursor,
                                                     resize_edge_, resize_minimum_);
                RECT current{};
                if (GetWindowRect(hwnd, &current) && !EqualRect(&next, &current)) {
                  SetWindowPos(hwnd, nullptr, next.left, next.top,
                      next.right - next.left, next.bottom - next.top,
                      SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOOWNERZORDER);
                }
              }
              if (message == WM_LBUTTONUP || !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
                native_resize_active_ = false;
                if (GetCapture() == hwnd) ReleaseCapture();
                QueueContentResize(); // Always commit the final, latest size.
              }
              return 0;
            }
            if (message == WM_CAPTURECHANGED || message == WM_CANCELMODE ||
                (message == WM_KEYDOWN && wparam == VK_ESCAPE)) {
              native_resize_active_ = false;
              resize_update_pending_ = false;
              if (GetCapture() == hwnd) ReleaseCapture();
              QueueContentResize();
            }
            if (message == WM_DPICHANGED) PostMessage(hwnd, kRebaseWindowResize, 0, 0);
            if (message == kRebaseWindowResize) {
              GetCursorPos(&resize_cursor_);
              GetWindowRect(hwnd, &resize_bounds_);
              const UINT dpi = GetDpiForWindow(hwnd);
              resize_minimum_ = {GetSystemMetricsForDpi(SM_CXMINTRACK, dpi),
                                 GetSystemMetricsForDpi(SM_CYMINTRACK, dpi)};
              return 0;
            }
          }
          if (hwnd == Window() && (message == kUpdateWindowResize || message == kRebaseWindowResize)) {
            resize_update_pending_ = false;
            return 0;
          }
          if (hwnd == Window() && message == kStartWindowDrag) {
            if (native_drag_active_ || !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) return 0;
            if (!GetCursorPos(&drag_cursor_) || !GetWindowRect(hwnd, &drag_bounds_)) return 0;
            if (IsZoomed(hwnd)) {
              const int grab_y = drag_cursor_.y - drag_bounds_.top;
              const double ratio = static_cast<double>(drag_cursor_.x - drag_bounds_.left) /
                  (std::max)(1L, drag_bounds_.right - drag_bounds_.left);
              ShowWindow(hwnd, SW_RESTORE);
              GetWindowRect(hwnd, &drag_bounds_);
              const int width = drag_bounds_.right - drag_bounds_.left;
              SetWindowPos(hwnd, nullptr, drag_cursor_.x - static_cast<int>(width * ratio),
                  drag_cursor_.y - grab_y, 0, 0,
                  SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
              GetWindowRect(hwnd, &drag_bounds_);
            }
            ReleaseCapture();
            SetCapture(hwnd);
            native_drag_active_ = GetCapture() == hwnd;
            return 0;
          }
          if (hwnd == Window() && native_drag_active_) {
            if (message == WM_MOUSEMOVE) {
              // Coalesce high-frequency mouse input; consume the latest screen
              // point on the platform loop without a modal SC_MOVE loop or Dart.
              if (!drag_update_pending_) {
                drag_update_pending_ = true;
                PostMessage(hwnd, kUpdateWindowDrag, 0, 0);
              }
              return 0;
            }
            if (message == kUpdateWindowDrag || message == WM_LBUTTONUP) {
              drag_update_pending_ = false;
              POINT cursor{};
              bool has_point = false;
              if (message == WM_LBUTTONUP) {
                cursor = {static_cast<short>(LOWORD(lparam)), static_cast<short>(HIWORD(lparam))};
                has_point = ClientToScreen(hwnd, &cursor) != FALSE;
              } else if (GetAsyncKeyState(VK_LBUTTON) & 0x8000) {
                has_point = GetCursorPos(&cursor) != FALSE;
              }
              if (has_point) {
                const int x = drag_bounds_.left + cursor.x - drag_cursor_.x;
                const int y = drag_bounds_.top + cursor.y - drag_cursor_.y;
                RECT current{};
                if (GetWindowRect(hwnd, &current) && (current.left != x || current.top != y)) {
                  SetWindowPos(hwnd, nullptr, x, y, 0, 0,
                      SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
                }
              }
              if (message == WM_LBUTTONUP || !(GetAsyncKeyState(VK_LBUTTON) & 0x8000)) {
                native_drag_active_ = false;
                if (GetCapture() == hwnd) ReleaseCapture();
              }
              return 0;
            }
            if (message == WM_CAPTURECHANGED || message == WM_CANCELMODE ||
                (message == WM_KEYDOWN && wparam == VK_ESCAPE)) {
              native_drag_active_ = false;
              drag_update_pending_ = false;
              if (GetCapture() == hwnd) ReleaseCapture();
            }
            if (message == WM_DPICHANGED) {
              // Rebase after the suggested DPI rectangle has been applied.
              PostMessage(hwnd, kRebaseWindowDrag, 0, 0);
            }
            if (message == kRebaseWindowDrag) {
              GetCursorPos(&drag_cursor_);
              GetWindowRect(hwnd, &drag_bounds_);
              return 0;
            }
          }
          if (hwnd == Window() && (message == kUpdateWindowDrag || message == kRebaseWindowDrag)) {
            drag_update_pending_ = false;
            return 0;
          }
          if (hwnd == Window() && hwnd == g_main_window &&
              (message == WM_WINDOWPOSCHANGED ||
               message == WM_SHOWWINDOW || message == WM_ENABLE || message == WM_DPICHANGED)) {
            if (message == WM_SHOWWINDOW && !wparam) {
              for (const auto& entry : g_dock_snapshots) {
                ShowWindow(entry.first, SW_HIDE);
              }
            } else if (message == WM_WINDOWPOSCHANGED &&
                !(reinterpret_cast<WINDOWPOS*>(lparam)->flags & SWP_NOSIZE)) {
              QueueContentResize();
            } else {
              SyncDockedWindows();
            }
          }
          if (hwnd == Window() && message == WM_SIZE) {
            ++content_resize_requests_;
            if (wparam != SIZE_MINIMIZED) QueueContentResize();
            return 0;
          }
          if (hwnd == Window() && message == WM_WINDOWPOSCHANGED) {
            return DefWindowProc(hwnd, message, wparam, lparam);
          }
          if (hwnd == Window() && message == WM_NCDESTROY) {
            g_dock_snapshots.erase(hwnd);
          }
          if (hwnd == Window() && message == WM_SHOWWINDOW && !wparam) {
            KillTimer(hwnd, kProfileHoverTimer);
            profile_hover_ = false;
          }
          if (hwnd == Window() && message == WM_TIMER &&
              wparam == kProfileHoverTimer && profile_hover_) {
            POINT cursor{};
            RECT card{};
            if (!GetCursorPos(&cursor) || !GetWindowRect(hwnd, &card)) return 0;
            const bool inside = PtInRect(&card, cursor) ||
                                PtInRect(&profile_anchor_, cursor);
            const HWND foreground = GetForegroundWindow();
            const bool interacting = IsFlyoutInteraction(hwnd, foreground);
            if (profile_hover_state_.ShouldHide(GetTickCount64(), inside, interacting)) {
              ShowWindow(hwnd, SW_HIDE);
              channel_->InvokeMethod("closeRequested", nullptr);
            }
            return 0;
          }
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
            const HWND next = reinterpret_cast<HWND>(lparam);
            if (!profile_hover_ ||
                !IsFlyoutInteraction(hwnd, next)) {
              ShowWindow(hwnd, SW_HIDE);
              channel_->InvokeMethod("closeRequested", nullptr);
            }
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
        HWND target_hwnd = (IsWindowDocked(hwnd) && g_main_window && IsWindow(g_main_window))
                               ? g_main_window
                               : hwnd;
        // The receiving window validates the button and reads the cursor at
        // dispatch time. Releasing capture here would cancel Flutter's gesture
        // before the queued native move actually starts.
        PostMessage(target_hwnd, kStartWindowDrag, 0, 0);
      } else if (method == "minimize") {
        HWND target_hwnd = (IsWindowDocked(hwnd) && g_main_window && IsWindow(g_main_window))
                               ? g_main_window
                               : hwnd;
        ShowWindow(target_hwnd, SW_MINIMIZE);
      } else if (method == "toggleMaximize") {
        HWND target_hwnd = (IsWindowDocked(hwnd) && g_main_window && IsWindow(g_main_window))
                               ? g_main_window
                               : hwnd;
        ShowWindow(target_hwnd, IsZoomed(target_hwnd) ? SW_RESTORE : SW_MAXIMIZE);
      } else if (method == "restore") {
        ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
        BringWindowToTop(hwnd);
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
        if (IsWindowDocked(hwnd)) {
          DockLog("[BrowserDock C++] center ignored on docked window hwnd=0x%p", hwnd);
          result->Success(flutter::EncodableValue(false));
          return;
        }
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
      } else if (method == "prepareFrame") {
        if (!view_controller_) {
          result->Error("SURFACE_UNAVAILABLE", "Window renderer is unavailable");
          return;
        }
        frame_state_->waiters.push_back(std::move(result));
        if (frame_state_->waiters.size() == 1) {
          view_controller_->engine()->SetNextFrameCallback([state = frame_state_]() {
            auto waiters = std::move(state->waiters);
            state->waiters.clear();
            ++state->prepared_frames;
            for (auto& waiter : waiters) waiter->Success(flutter::EncodableValue(true));
          });
          view_controller_->ForceRedraw();
        }
        return;
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
          int x = read_num("x", 0);
          int y = read_num("y", 0);
          int w = read_num("width", 380);
          int h = read_num("height", 420);
          profile_hover_ = false;
          KillTimer(hwnd, kProfileHoverTimer);
          auto anchor_it = args->find(flutter::EncodableValue("hoverAnchor"));
          if (anchor_it != args->end()) {
            if (const auto* anchor = std::get_if<flutter::EncodableMap>(&anchor_it->second)) {
              const auto coordinate = [anchor](const char* key) -> LONG {
                auto it = anchor->find(flutter::EncodableValue(key));
                if (it == anchor->end()) return 0;
                if (const auto* value = std::get_if<int32_t>(&it->second)) return *value;
                if (const auto* value = std::get_if<int64_t>(&it->second)) return static_cast<LONG>(*value);
                return 0;
              };
              profile_anchor_ = {coordinate("left"), coordinate("top"),
                                 coordinate("right"), coordinate("bottom")};
              MONITORINFO monitor{sizeof(MONITORINFO)};
              const HMONITOR target_monitor = MonitorFromRect(&profile_anchor_, MONITOR_DEFAULTTONEAREST);
              if (GetMonitorInfo(target_monitor, &monitor)) {
                const UINT dpi = FlutterDesktopGetDpiForMonitor(target_monitor);
                w = MulDiv(380, dpi ? dpi : 96, 96);
                h = MulDiv(420, dpi ? dpi : 96, 96);
                const int gap = MulDiv(8, dpi ? dpi : 96, 96);
                const RECT bounds = ProfileFlyoutBounds(profile_anchor_, monitor.rcWork, w, h, gap);
                x = bounds.left;
                y = bounds.top;
                w = bounds.right - bounds.left;
                h = bounds.bottom - bounds.top;
                profile_hover_ = true;
                profile_hover_state_.Reset(GetTickCount64());
              }
            }
          }
          bool no_activate = true;
          auto no_act_it = args->find(flutter::EncodableValue("noActivate"));
          if (no_act_it != args->end()) {
            if (const auto* b = std::get_if<bool>(&no_act_it->second)) no_activate = *b;
          }
          SetWindowPos(hwnd, HWND_TOPMOST, x, y, w, h,
                       SWP_SHOWWINDOW | (no_activate ? SWP_NOACTIVATE : 0));
          if (profile_hover_) SetTimer(hwnd, kProfileHoverTimer, 50, nullptr);
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
        const auto window_regions = CaptureWindowRegions(RECT{vx, vy, vx + vw, vy + vh});

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
        res[flutter::EncodableValue("windows")] = flutter::EncodableValue(window_regions);
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
      } else if (method == "dockToParent" || method == "updateDockedBounds") {
        const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (!args) { result->Error("INVALID_ARGS", "Browser bounds required"); return; }
        const auto number = [args](const char* key) -> int {
          auto it = args->find(flutter::EncodableValue(key));
          if (it == args->end()) return 0;
          if (auto v = std::get_if<int32_t>(&it->second)) return *v;
          if (auto v = std::get_if<int64_t>(&it->second)) return static_cast<int>(*v);
          return 0;
        };
        const auto slot_it = args->find(flutter::EncodableValue("slotId"));
        const std::string slot_id = slot_it != args->end() && std::get_if<std::string>(&slot_it->second)
            ? std::get<std::string>(slot_it->second) : "chat:right";
        const bool success = method == "dockToParent"
            ? AttachDockedWindow(hwnd, slot_id, number("x"), number("y"), number("width"), number("height"))
            : SaveDockBounds(hwnd, number("x"), number("y"), number("width"), number("height"));
        result->Success(flutter::EncodableValue(success));
        return;
      } else if (method == "undockFromParent") {
        bool show = true;
        const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (args) {
          auto it = args->find(flutter::EncodableValue("showWindow"));
          if (it != args->end()) if (auto v = std::get_if<bool>(&it->second)) show = *v;
        }
        const bool restored = RestoreDockedWindow(hwnd, show);
        if (restored) {
          auto* view = registrar_->GetView();
          RECT client{};
          if (view && GetClientRect(hwnd, &client)) {
            MoveWindow(view->GetNativeWindow(), 0, 0,
                client.right - client.left, client.bottom - client.top, TRUE);
          }
          if (view_controller_) view_controller_->ForceRedraw();
          RedrawWindow(hwnd, nullptr, nullptr, RDW_INVALIDATE | RDW_ALLCHILDREN | RDW_FRAME);
        }
        result->Success(flutter::EncodableValue(restored));
        return;
      } else if (method == "isDocked") {
        result->Success(flutter::EncodableValue(IsWindowDocked(hwnd)));
        return;
      } else if (method == "setBrowserDockVisible") {
        const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
        if (hwnd == g_main_window && args) {
          auto visible = args->find(flutter::EncodableValue("visible"));
          auto route = args->find(flutter::EncodableValue("route"));
          const bool is_route = route != args->end() && std::get_if<bool>(&route->second) && std::get<bool>(route->second);
          if (visible != args->end()) if (auto value = std::get_if<bool>(&visible->second)) {
            const auto slot_it = args->find(flutter::EncodableValue("slotId"));
            const std::string slot_id = slot_it != args->end() && std::get_if<std::string>(&slot_it->second)
                ? std::get<std::string>(slot_it->second) : "chat:right";
            if (is_route) g_dock_route_visible = *value;
            else g_dock_slot_visible[slot_id] = *value;
            SyncDockedWindows();
          }
        }
        result->Success(flutter::EncodableValue(true));
        return;
      } else if (method == "browserDockDiagnostics") {
        flutter::EncodableMap data;
        data[flutter::EncodableValue("nativeResizeActive")] = flutter::EncodableValue(native_resize_active_);
        data[flutter::EncodableValue("resizeGestures")] = flutter::EncodableValue(resize_gestures_);
        data[flutter::EncodableValue("contentResizeRequests")] = flutter::EncodableValue(content_resize_requests_);
        data[flutter::EncodableValue("contentResizeApplied")] = flutter::EncodableValue(content_resize_applied_);
        data[flutter::EncodableValue("contentResizeSkipped")] = flutter::EncodableValue(content_resize_skipped_);
        data[flutter::EncodableValue("contentResizeMaxMs")] = flutter::EncodableValue(static_cast<int64_t>(content_resize_max_ms_));
        data[flutter::EncodableValue("contentResizeQueueMaxMs")] = flutter::EncodableValue(static_cast<int64_t>(content_resize_queue_max_ms_));
        RECT viewport{}, client{};
        if (auto* view = registrar_->GetView()) GetClientRect(view->GetNativeWindow(), &viewport);
        GetClientRect(hwnd, &client);
        data[flutter::EncodableValue("contentWidth")] = flutter::EncodableValue(static_cast<int32_t>(viewport.right));
        data[flutter::EncodableValue("contentHeight")] = flutter::EncodableValue(static_cast<int32_t>(viewport.bottom));
        data[flutter::EncodableValue("clientWidth")] = flutter::EncodableValue(static_cast<int32_t>(client.right));
        data[flutter::EncodableValue("clientHeight")] = flutter::EncodableValue(static_cast<int32_t>(client.bottom));
        data[flutter::EncodableValue("nativeDragActive")] = flutter::EncodableValue(native_drag_active_);
        data[flutter::EncodableValue("nativeDragUpdatePending")] = flutter::EncodableValue(drag_update_pending_);
        const auto encode_rect = [](RECT rect) {
          return flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("left"), flutter::EncodableValue(static_cast<int32_t>(rect.left))},
            {flutter::EncodableValue("top"), flutter::EncodableValue(static_cast<int32_t>(rect.top))},
            {flutter::EncodableValue("right"), flutter::EncodableValue(static_cast<int32_t>(rect.right))},
            {flutter::EncodableValue("bottom"), flutter::EncodableValue(static_cast<int32_t>(rect.bottom))}});
        };
        RECT window_rect{}, main_client{};
        GetWindowRect(hwnd, &window_rect);
        GetClientRect(g_main_window, &main_client);
        MapWindowPoints(g_main_window, nullptr, reinterpret_cast<POINT*>(&main_client), 2);
        data[flutter::EncodableValue("windowRect")] = encode_rect(window_rect);
        data[flutter::EncodableValue("preparedFrameCount")] = flutter::EncodableValue(frame_state_->prepared_frames);
        data[flutter::EncodableValue("profileHoverTracking")] = flutter::EncodableValue(profile_hover_);
        data[flutter::EncodableValue("profileAnchor")] = encode_rect(profile_anchor_);
        MONITORINFO flyout_monitor{sizeof(MONITORINFO)};
        if (GetMonitorInfo(MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST), &flyout_monitor)) {
          data[flutter::EncodableValue("monitorWorkArea")] = encode_rect(flyout_monitor.rcWork);
        }
        data[flutter::EncodableValue("mainClientRect")] = encode_rect(main_client);
        data[flutter::EncodableValue("mainMaximized")] = flutter::EncodableValue(IsZoomed(g_main_window) != FALSE);
        RECT main_rect{};
        GetWindowRect(g_main_window, &main_rect);
        flutter::EncodableList edge_tests;
        const POINT edge_points[] = {
          {main_rect.left + 1, (main_rect.top + main_rect.bottom) / 2},
          {main_rect.right - 1, (main_rect.top + main_rect.bottom) / 2},
          {(main_rect.left + main_rect.right) / 2, main_rect.top + 1},
          {(main_rect.left + main_rect.right) / 2, main_rect.bottom - 1}};
        for (const auto& point : edge_points) {
          edge_tests.push_back(flutter::EncodableValue(static_cast<int32_t>(SendMessage(g_main_window, WM_NCHITTEST, 0, MAKELPARAM(point.x, point.y)))));
        }
        data[flutter::EncodableValue("mainResizeHitTests")] = flutter::EncodableValue(edge_tests);
        data[flutter::EncodableValue("windowHwnd")] = flutter::EncodableValue(reinterpret_cast<int64_t>(hwnd));
        data[flutter::EncodableValue("windowThread")] = flutter::EncodableValue(static_cast<int64_t>(GetWindowThreadProcessId(hwnd, nullptr)));
        data[flutter::EncodableValue("isDocked")] = flutter::EncodableValue(IsWindowDocked(hwnd));
        data[flutter::EncodableValue("supported")] = flutter::EncodableValue(true);
        data[flutter::EncodableValue("mainHwnd")] = flutter::EncodableValue(reinterpret_cast<int64_t>(g_main_window));
        data[flutter::EncodableValue("mainThread")] = flutter::EncodableValue(static_cast<int64_t>(GetWindowThreadProcessId(g_main_window, nullptr)));
        flutter::EncodableList docked_windows;
        for (const auto& [browser, snapshot] : g_dock_snapshots) {
          docked_windows.push_back(flutter::EncodableValue(flutter::EncodableMap{
            {flutter::EncodableValue("hwnd"), flutter::EncodableValue(reinterpret_cast<int64_t>(browser))},
            {flutter::EncodableValue("slotId"), flutter::EncodableValue(snapshot.slot_id)},
            {flutter::EncodableValue("visible"), flutter::EncodableValue(IsWindowVisible(browser) != FALSE)}}));
          if (browser != hwnd && hwnd != g_main_window) continue;
          data[flutter::EncodableValue("slotId")] = flutter::EncodableValue(snapshot.slot_id);
          data[flutter::EncodableValue("browserHwnd")] = flutter::EncodableValue(reinterpret_cast<int64_t>(browser));
          data[flutter::EncodableValue("browserThread")] = flutter::EncodableValue(static_cast<int64_t>(GetWindowThreadProcessId(browser, nullptr)));
          data[flutter::EncodableValue("dpi")] = flutter::EncodableValue(static_cast<int32_t>(snapshot.dpi));
          data[flutter::EncodableValue("docked")] = flutter::EncodableValue(true);
          data[flutter::EncodableValue("visible")] = flutter::EncodableValue(IsWindowVisible(browser) != FALSE);
        }
        data[flutter::EncodableValue("windows")] = flutter::EncodableValue(docked_windows);
        result->Success(flutter::EncodableValue(data));
        return;
      } else {
        result->NotImplemented();
        return;
      }
      result->Success(flutter::EncodableValue(IsZoomed(hwnd) != FALSE));
    });
  }
  ~WindowControls() override {
    for (auto& waiter : frame_state_->waiters) {
      waiter->Error("WINDOW_CLOSED", "Window closed before its frame was ready");
    }
    frame_state_->waiters.clear();
    if (Window()) KillTimer(Window(), kProfileHoverTimer);
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
  static bool IsFlyoutInteraction(HWND flyout, HWND candidate) {
    // GA_ROOTOWNER alone would return the main app window for this owned
    // flyout. Walk owners so a dialog owned by the card counts, the main
    // window (and its unrelated dialogs) does not.
    for (HWND window = candidate ? GetAncestor(candidate, GA_ROOT) : nullptr;
         window; window = GetWindow(window, GW_OWNER)) {
      if (window == flyout) return true;
    }
    return false;
  }
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
  void QueueContentResize() {
    if (content_resize_pending_) return;
    content_resize_pending_ = true;
    content_resize_queued_at_ = GetTickCount64();
    if (!PostMessage(Window(), kResizeFlutterContent, 0, 0)) content_resize_pending_ = false;
  }
  void ApplyLatestContentSize() {
    HWND parent = Window();
    auto* view = registrar_->GetView();
    if (!parent || !view || IsIconic(parent)) return;
    HWND child = view->GetNativeWindow();
    RECT bounds{}, current{};
    if (!GetClientRect(parent, &bounds) || bounds.right <= 0 || bounds.bottom <= 0) return;
    if (GetClientRect(child, &current) && current.right == bounds.right &&
        current.bottom == bounds.bottom) {
      ++content_resize_skipped_;
      if (parent == g_main_window) SyncDockedWindows();
      return;
    }
    const ULONGLONG begin = GetTickCount64();
    content_resize_queue_max_ms_ = (std::max)(content_resize_queue_max_ms_,
        begin - content_resize_queued_at_);
    // Unlike MoveWindow(..., TRUE), this does not synchronously UpdateWindow
    // and wait for raster work. Flutter receives one latest viewport size.
    if (SetWindowPos(child, nullptr, 0, 0, bounds.right, bounds.bottom,
        SWP_NOZORDER | SWP_NOACTIVATE | SWP_NOCOPYBITS)) ++content_resize_applied_;
    content_resize_max_ms_ = (std::max)(content_resize_max_ms_, GetTickCount64() - begin);
    if (parent == g_main_window) SyncDockedWindows();
  }
  void Configure() {
    HWND hwnd = Window();
    if (!hwnd || configured_window_ == hwnd || IsWindowDocked(hwnd)) return;
    configured_window_ = hwnd;
    const LONG_PTR style = GetWindowLongPtr(hwnd, GWL_STYLE);
    const LONG_PTR custom = (style & ~WS_CAPTION) | WS_THICKFRAME | WS_CLIPCHILDREN;
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
  flutter::FlutterViewController* view_controller_ = nullptr;
  bool native_resize_active_ = false;
  bool resize_update_pending_ = false;
  POINT resize_cursor_{};
  RECT resize_bounds_{};
  SIZE resize_minimum_{};
  UINT resize_edge_ = 0;
  int resize_gestures_ = 0;
  bool content_resize_pending_ = false;
  int content_resize_requests_ = 0;
  int content_resize_applied_ = 0;
  int content_resize_skipped_ = 0;
  ULONGLONG content_resize_queued_at_ = 0;
  ULONGLONG content_resize_queue_max_ms_ = 0;
  ULONGLONG content_resize_max_ms_ = 0;
  bool native_drag_active_ = false;
  bool drag_update_pending_ = false;
  POINT drag_cursor_{};
  RECT drag_bounds_{};
  struct FrameState {
    std::vector<std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>> waiters;
    int prepared_frames = 0;
  };
  std::shared_ptr<FrameState> frame_state_ = std::make_shared<FrameState>();
  bool is_modal_ = false;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  int delegate_ = -1;
  HWND configured_window_ = nullptr;
  bool allow_destroy_ = false;
  bool auto_hide_ = false;
  static constexpr UINT_PTR kProfileHoverTimer = 0x47494D50;
  bool profile_hover_ = false;
  RECT profile_anchor_{};
  ProfileFlyoutHover profile_hover_state_;
  NOTIFYICONDATA tray_{};
  bool tray_active_ = false;
  bool tray_icon_owned_ = false;
  int tray_unread_ = 0;
  std::wstring tray_owner_;
};
}
void RegisterWindowControls(flutter::FlutterEngine* engine, HWND explicit_hwnd,
                            flutter::FlutterViewController* controller) {
  auto* registrar = flutter::PluginRegistrarManager::GetInstance()
      ->GetRegistrar<flutter::PluginRegistrarWindows>(
          engine->GetRegistrarForPlugin("GotoIMWindowControls"));
  registrar->AddPlugin(std::make_unique<WindowControls>(registrar, explicit_hwnd, controller));
}
