#include "flutter_window.h"

#include <optional>
#include <commctrl.h>
#include "window_controls.h"

#include "flutter/generated_plugin_registrant.h"
#include "desktop_multi_window/desktop_multi_window_plugin.h"

namespace {
constexpr UINT kRedrawAfterShow = WM_APP + 0x47;
LRESULT CALLBACK StartupCoverProc(HWND hwnd, UINT message, WPARAM wparam,
    LPARAM lparam, UINT_PTR id, DWORD_PTR) {
  if (message == WM_NCHITTEST) return HTTRANSPARENT;
  if (message == WM_ERASEBKGND) return 1;
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    HDC dc = BeginPaint(hwnd, &paint);
    RECT area{};
    GetClientRect(hwnd, &area);
    HBRUSH background = CreateSolidBrush(RGB(243, 247, 245));
    FillRect(dc, &area, background);
    DeleteObject(background);
    SetBkMode(dc, TRANSPARENT);
    const int scale = GetDpiForWindow(hwnd);
    HFONT title = CreateFontW(-MulDiv(30, scale, 96), 0, 0, 0, FW_SEMIBOLD,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    HGDIOBJ old_font = SelectObject(dc, title);
    SetTextColor(dc, RGB(7, 168, 106));
    RECT text = area;
    text.top = (area.bottom - MulDiv(90, scale, 96)) / 2;
    text.bottom = text.top + MulDiv(50, scale, 96);
    DrawTextW(dc, L"Goto IM", -1, &text, DT_CENTER | DT_SINGLELINE | DT_VCENTER);
    HFONT body = CreateFontW(-MulDiv(14, scale, 96), 0, 0, 0, FW_NORMAL,
        FALSE, FALSE, FALSE, DEFAULT_CHARSET, OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY, DEFAULT_PITCH, L"Segoe UI");
    SelectObject(dc, body);
    SetTextColor(dc, RGB(100, 116, 109));
    text.top = text.bottom + MulDiv(12, scale, 96);
    text.bottom = text.top + MulDiv(30, scale, 96);
    DrawTextW(dc, L"正在准备工作区…", -1, &text, DT_CENTER | DT_SINGLELINE | DT_VCENTER);
    SelectObject(dc, old_font);
    DeleteObject(title);
    DeleteObject(body);
    EndPaint(hwnd, &paint);
    return 0;
  }
  if (message == WM_NCDESTROY) RemoveWindowSubclass(hwnd, StartupCoverProc, id);
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // Paint an opaque native cover BEFORE creating the engine/registering plugins.
  // It stays above the Flutter view until that engine presents its first frame.
  startup_cover_ = CreateWindowExW(0, L"STATIC", L"", WS_CHILD | WS_VISIBLE,
      0, 0, frame.right, frame.bottom, GetHandle(), nullptr,
      GetModuleHandle(nullptr), nullptr);
  if (startup_cover_) SetWindowSubclass(startup_cover_, StartupCoverProc, 1, 0);
  Show();
  if (startup_cover_) UpdateWindow(startup_cover_);

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  DesktopMultiWindowSetWindowCreatedCallback([](void *controller) {
    auto *flutter_view_controller =
        reinterpret_cast<flutter::FlutterViewController *>(controller);
    auto *registry = flutter_view_controller->engine();
    RegisterPlugins(registry);

    HWND child_hwnd = flutter_view_controller->view()->GetNativeWindow();
    HWND top_hwnd = GetAncestor(child_hwnd, GA_ROOT);
    if (top_hwnd && IsWindow(top_hwnd)) {
      ConfigureSubWindowNative(top_hwnd, child_hwnd);
    }
    RegisterWindowControls(flutter_view_controller->engine(), top_hwnd, flutter_view_controller);
  });
  SetMainWindowHandle(GetHandle());
  HWND child_hwnd = flutter_controller_->view()->GetNativeWindow();
  SetMainChildContentHandle(child_hwnd);
  SetChildContent(child_hwnd);
  AttachChildViewResizeSubclass(child_hwnd);
  RegisterWindowControls(flutter_controller_->engine(), GetHandle(), flutter_controller_.get());

  if (startup_cover_) SetWindowPos(startup_cover_, HWND_TOP, 0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
  flutter_controller_->engine()->SetNextFrameCallback([this]() {
    if (startup_cover_) { DestroyWindow(startup_cover_); startup_cover_ = nullptr; }
    this->Show();
    PostMessage(GetHandle(), kRedrawAfterShow, 0, 0);
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_NCHITTEST && startup_cover_) {
    RECT bounds{};
    GetWindowRect(hwnd, &bounds);
    const int x = static_cast<short>(LOWORD(lparam));
    const int y = static_cast<short>(HIWORD(lparam));
    const int edge = MulDiv(8, GetDpiForWindow(hwnd), 96);
    if (!IsZoomed(hwnd) && x > bounds.left + edge && x < bounds.right - edge &&
        y > bounds.top + edge && y < bounds.top + MulDiv(38, GetDpiForWindow(hwnd), 96)) {
      return HTCAPTION;
    }
  }
  if (message == WM_SIZE && startup_cover_) {
    RECT client{};
    GetClientRect(hwnd, &client);
    MoveWindow(startup_cover_, 0, 0, client.right, client.bottom, TRUE);
  }
  // Present a fresh frame only after ShowWindow and its size/visibility messages
  // have returned to the platform message loop.
  if (message == kRedrawAfterShow && flutter_controller_) {
    flutter_controller_->ForceRedraw();
    return 0;
  }

  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
