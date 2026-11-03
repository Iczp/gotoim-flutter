# Single-engine multiview feasibility

Checked 2026-11-03: [multiview_desktop 2.0.2](https://pub.dev/packages/multiview_desktop) describes a single engine and isolate with multiple native views; its Windows runner integration must be assessed against this project's `windows/runner/flutter_window.cpp`, `main.cpp`, custom controls and plugin registration. This is a publisher claim, not a project test. [Flutter desktop windowing announcement](https://flutter.dev/blog/desktop-windowing-apis) describes the official API; installed Flutter 3.47.0 stable and its actual available API must be checked before relying on it. Current production plugin is [desktop_multi_window 0.3.1](https://pub.dev/packages/desktop_multi_window).

No isolated prototype has been built and no migration gate is met. In particular, plugin lifecycle, WebView2, input methods, focus, DPI, tray and close behaviour are **untested** in a child multiview. License, source maintenance and package SDK constraints remain to be audited from the package source. Do not change the production runner or infer memory savings from the design alone.

| Capability | Child view | Evidence |
|---|---|---|
| window controls / tray | untested | no prototype |
| WebView2 | untested | no prototype |
| Drift and shared state | untested | no prototype |
| file picker / drag / clipboard | untested | no prototype |
| notifications / deep links | untested | no prototype |
| shortcuts / IME / focus | untested | no prototype |
| media / theme / DPI / close | untested | no prototype |
