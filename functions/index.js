const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");

initializeApp();
const auth = getAuth();

/** 須與 Flutter `kFirebaseFunctionsRegion` 一致。 */
const REGION = "us-central1";

exports.adminListAuthUsers = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "需要登入");
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "僅管理員可列出使用者");
  }
  const rawMax = Number(request.data?.maxResults);
  const max = Math.min(Math.max(Number.isFinite(rawMax) ? rawMax : 100, 1), 1000);
  const pageToken =
    typeof request.data?.pageToken === "string" && request.data.pageToken.length > 0
      ? request.data.pageToken
      : undefined;
  try {
    const result = await auth.listUsers(max, pageToken);
    return {
      users: result.users.map((u) => ({
        uid: u.uid,
        email: u.email ?? null,
        displayName: u.displayName ?? null,
        emailVerified: u.emailVerified,
        disabled: u.disabled,
        creationTime: u.metadata.creationTime,
        lastSignInTime: u.metadata.lastSignInTime ?? null,
      })),
      nextPageToken: result.pageToken ?? null,
    };
  } catch (e) {
    console.error(e);
    throw new HttpsError("internal", e.message || "listUsers 失敗");
  }
});

exports.adminUpdateAuthUser = onCall({region: REGION}, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "需要登入");
  }
  if (request.auth.token.admin !== true) {
    throw new HttpsError("permission-denied", "僅管理員可更新使用者");
  }
  const uid = request.data?.uid;
  if (typeof uid !== "string" || uid.length === 0) {
    throw new HttpsError("invalid-argument", "需要 uid");
  }
  const patch = {};
  if (Object.prototype.hasOwnProperty.call(request.data, "email")) {
    const em = request.data.email;
    if (em === null || em === "") {
      throw new HttpsError(
        "invalid-argument",
        "不支援清空 email；請改為其他有效信箱",
      );
    }
    if (typeof em === "string") {
      patch.email = em.trim();
    }
  }
  if (Object.prototype.hasOwnProperty.call(request.data, "displayName")) {
    const dn = request.data.displayName;
    patch.displayName =
      dn === null || dn === "" ? null : String(dn).trim();
  }
  if (Object.prototype.hasOwnProperty.call(request.data, "password")) {
    const pw = request.data.password;
    if (pw != null && String(pw).length > 0) {
      if (String(pw).length < 6) {
        throw new HttpsError("invalid-argument", "密碼至少 6 字元");
      }
      patch.password = String(pw);
    }
  }
  if (Object.prototype.hasOwnProperty.call(request.data, "disabled")) {
    patch.disabled = !!request.data.disabled;
  }
  if (Object.prototype.hasOwnProperty.call(request.data, "emailVerified")) {
    patch.emailVerified = !!request.data.emailVerified;
  }
  if (Object.keys(patch).length === 0) {
    throw new HttpsError("invalid-argument", "沒有任何要更新的欄位");
  }
  try {
    await auth.updateUser(uid, patch);
    return {ok: true};
  } catch (e) {
    console.error(e);
    const code = e.code || "";
    if (code === "auth/email-already-exists") {
      throw new HttpsError("already-exists", e.message || "email 已被使用");
    }
    if (code === "auth/invalid-email") {
      throw new HttpsError("invalid-argument", e.message || "email 格式無效");
    }
    throw new HttpsError("internal", e.message || "updateUser 失敗");
  }
});
