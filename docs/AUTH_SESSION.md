# 登入態與 Token 架構（Firebase Auth · Flutter Web / 跨平台）

本文件對應專案中 `/lib/core/auth`、`/lib/services/auth_service.dart`、`/lib/core/network/authorized_http.dart`。

## 1. 為何不用「自己存 JWT」在 LocalStorage？

- **Firebase Auth** 已將 **Refresh Token／session** 交由官方 JS／原生 SDK 與瀏覽器儲存機制管理（Web 通常為 IndexedDB／LocalStorage 的組合，由 Firebase 實作）。
- App 只需：
  - 監聽 **`authStateChanges`** → Login / Auto Login / Logout UI。
  - **取得短命 ID Token** (`User.getIdToken`) → 對後端發 **`Authorization: Bearer`**。
- **禁止**將 **密碼**、完整個資 JSON 自行寫入 LocalStorage。

## 2. Token 類型（你的後端會看到的是哪一種）

| 項目 | 說明 |
|------|------|
| ID Token | JWT，短命；給後端 `Bearer`；可用 Firebase Admin／JWKS 驗簽 |
| Refresh Token | 長效，由 SDK 保管，**勿**自行解析或寫入明文儲存區 |

## 3. 程式內流程（儲存／恢復）

1. `Firebase.initializeApp`  
2. **`AuthBootstrap.ensureFirebasePersistence()`**（僅 Web）：`setPersistence(Persistence.LOCAL)`，關閉瀏覽器後重開仍還原 session。  
3. **`AuthService`** 訂閱底層 `authStateChanges` 同步訪客／已登入 UI。  
4. 呼叫後端 API：**`auth.authorizedHttp()`** 自動帶 Bearer（見下節）。

### F5／StreamBuilder 曾「像被登出」的原因（已修）

`FirebaseAuth.authStateChanges()` 底層為 **broadcast**，**晚訂閱**的 `StreamBuilder` **不會收到**已經發過的「第一個事件」。若另一個 `listen` 先訂閱，UI 可能永遠停在 `null`。

**作法：** 對外提供的 `authChanges` 使用 **`Stream.multi`**，每個新監聽者先 `add(currentUser)` 再 `addStream(底層)`，等同「行為主題（BehaviorSubject）」的前綴快照。

## 4. API：`Authorization: Bearer`

```dart
final api = auth.authorizedHttp();
final res = await api.get(Uri.parse('https://your.api/v1/profile'));
// 若後端回 401，可改用 api.getWithFreshTokenOnUnauthorized(uri)
api.close(); // App dispose 時
```

`getIdToken(forceRefresh: true)` 用於自訂重試邏輯（例如僅在 401 時強制換新 ID Token）。

## 5. 模組邊界（會員系統擴充）

| 層級 | 職責 |
|------|------|
| `AuthService` | Email 註冊／登入／登出、session 串流、管理員 claim、包一層 HTTP |
| `AuthorizedHttpFacade` | 僅負責 Bearer，不含業務 |
| `FederatedAuthPort` | 預留 Google／Apple OAuth 實作（避免 `AuthService` 膨脹） |

## 6. React / 其他前端對照

- 同樣使用 **Firebase JS SDK** `onAuthStateChanged` + **持續性 `LOCAL`**。  
- 對 API：`getIdToken()` → `Authorization: Bearer`。  
- 不要自行把 refresh token 存 localStorage 字串欄位再拼 JWT。

## 7. iOS / Android（未來同一套）

- `AuthBootstrap` 僅 Web 呼叫 `setPersistence`；行動端預設即持久化。  
- 仍使用同一 `AuthService` 與 `authorizedHttp`；若改 `IOClient` 請注入 `http.Client`。

## 8. 安全實踐摘要

- 後端**必須**驗證 ID Token（或 Session Cookie 方案），勿信任僅帶 uid 的 header。  
- ID Token 過期：先 `getIdToken(false)`，若後端 401 再 `forceRefresh: true`；仍失敗則導向登入。  
- **serviceAccountKey.json** 僅能放伺服器／管理腳本，勿進前端 bundle。
