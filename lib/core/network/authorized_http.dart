import "package:http/http.dart" as http;

/// Firebase ID Token 供應器（不要改存 LocalStorage）；由 [FirebaseUser.getIdToken] 取得短命 JWT，
/// Refresh 交由 Firebase SDK 處理，過期或撤銷時回傳 `null` 表示應視為登出。
typedef IdTokenSupplier = Future<String?> Function({bool forceRefresh});

/// `Authorization: Bearer <Firebase ID Token>` · 不包含密碼與電子郵件。
class AuthorizedHttpFacade {
  AuthorizedHttpFacade({
    http.Client? client,
    required this.resolveIdToken,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final IdTokenSupplier resolveIdToken;

  Future<Map<String, String>> authHeaders([
    Map<String, String>? headers,
    bool forceRefreshToken = false,
  ]) async {
    final merged = {...?headers};
    final token = await resolveIdToken(forceRefresh: forceRefreshToken);
    if (token != null && token.isNotEmpty) {
      merged["Authorization"] = "Bearer $token";
    }
    return merged;
  }

  Future<http.Response> getWithFreshTokenOnUnauthorized(Uri url,
      {Map<String, String>? headers}) async {
    var res = await get(url, headers: headers);
    if (res.statusCode == 401) {
      res = await _client.get(url, headers: await authHeaders(headers, true));
    }
    return res;
  }

  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    return _client.get(url, headers: await authHeaders(headers));
  }

  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _client.post(url, headers: await authHeaders(headers), body: body);
  }

  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) async {
    return _client.put(url, headers: await authHeaders(headers), body: body);
  }

  Future<http.Response> delete(Uri url, {Map<String, String>? headers}) async {
    return _client.delete(url, headers: await authHeaders(headers));
  }

  /// 若在非 Web 上使用 `dart:io` 的長連線可自行替換為 `IOClient`，並在完成 App 後呼叫。
  void close() => _client.close();
}
