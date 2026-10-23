#ifndef RUNNER_WINDOW_CONTROLS_H_
#define RUNNER_WINDOW_CONTROLS_H_

#include <windows.h>
#include <flutter/flutter_engine.h>
#include <flutter/flutter_view_controller.h>

void SetMainWindowHandle(HWND hwnd);
HWND GetMainWindowHandle();
void SetMainChildContentHandle(HWND hwnd);
HWND GetMainChildContentHandle();
void ConfigureSubWindowNative(HWND sub_hwnd, HWND child_hwnd);
void AttachChildViewResizeSubclass(HWND child_hwnd);
void RegisterWindowControls(flutter::FlutterEngine* engine, HWND explicit_hwnd = nullptr,
                            flutter::FlutterViewController* controller = nullptr);

#endif  // RUNNER_WINDOW_CONTROLS_H_
