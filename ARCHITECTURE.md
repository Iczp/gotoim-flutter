# Flutter foundation

This package deliberately contains no migrated feature page. It establishes:

- `app/`: bootstrap, routing, responsive application shell;
- `core/`: contracts for network, credentials, real-time transport, windowing,
  and platform integration;
- conditional platform adapters in `core/platform`;
- Riverpod as the only state-management entry point.

Feature code must depend on contracts such as `ApiClient`, `TokenStorage`,
`SignalRGateway`, and `WindowService`, never on platform plugins or `dart:io`.
Concrete Dio, Drift, SignalR, secure storage, JSBridge, permission, media and
desktop-window implementations are intentionally deferred until their feature
work begins.

## Responsive policy

- `< 600`: mobile shell
- `600..1023`: tablet shell
- `>= 1024`: desktop shell

The classification uses layout width, so Android tablets, iPads, desktop apps
and browser windows share one responsive policy without feature code testing a
runtime platform.
