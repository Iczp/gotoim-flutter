# Authentication and HTTP

## Scope

The Flutter client follows the current UniApp contract: OpenIddict token
endpoint `POST /connect/token`, with the `password` grant for login and the
`refresh_token` grant for renewal. This is infrastructure only; user/profile
and IM pages are not part of this step.

```text
LoginPage -> AuthController -> OpenIdConnectAuthRepository
                                  |             |
                                  |             +-> TokenStorage (secure)
                                  v
                           OpenIddict /connect/token

Repository -> ApiClient (Dio) -> 401 -> one shared refresh -> retry once
SignalR -------------------------------> TokenStorage.readAccessToken()
```

## Environment

Set public, non-secret values in the root `.env.<flavor>` file:

| Key | Meaning |
| --- | --- |
| `API_BASE_URL` | API host used by the shared Dio client |
| `AUTH_BASE_URL` | OpenIddict host |
| `AUTH_TOKEN_PATH` | Token endpoint; normally `/connect/token` |
| `AUTH_CLIENT_ID` | Public mobile client id registered at the server |
| `AUTH_SCOPE` | Space-separated OAuth scopes, normally including `offline_access` |
| `AUTH_LOGIN_GRANT_TYPE` | Existing server's login grant, currently `password` |

Run a flavor with:

```powershell
flutter run --dart-define=APP_ENV=development
```

Do not place a client secret, password, access token, refresh token, or MinIO
credential in any `.env` file. A mobile/desktop client cannot keep a secret.
Production endpoints and the public `AUTH_CLIENT_ID` must be registered with
the backend before a real login can work.

## Token lifecycle

- `SecureTokenStorage` is the only concrete token persistence layer. UI and
  repositories depend only on `TokenStorage`.
- Login writes access and refresh tokens together.
- `DioApiClient` adds `Authorization: Bearer <access-token>`.
- A 401 starts one `refresh_token` request. Concurrent 401 requests await that
  same future, then retry once with the new token.
- If refresh fails, local tokens are cleared and the router sends the user to
  `/login`.
- SignalR receives a callback to read the same storage immediately before it
  connects or reconnects.

The current token adapter intentionally does not call a logout/revocation
endpoint because the exact backend route in the existing client is incomplete
(`revocat`). Add it only after confirming the server contract.

## UI and routing

`/splash` restores the stored session, `/login` is shown when no session
exists, and `/` is the currently empty authenticated application shell. The
redirect decision is centralised in `app_router.dart`; feature pages do not
perform their own auth checks.

## Adding an authenticated endpoint

Expose an application repository method, inject `ApiClient`, and keep Dio out
of widgets:

```dart
final result = await apiClient.get<Map<String, dynamic>>('/api/chat/sessions');
```

Do not use the `Dio` instance directly from a feature page. Add typed DTOs and
repository tests before migrating a real IM endpoint.
