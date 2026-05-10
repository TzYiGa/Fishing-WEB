/**
 * Usage:
 *   npm init -y
 *   npm i firebase-admin
 *   node set-admin.js
 *
 * Optional:
 *   node set-admin.js your-email@example.com
 *
 * Required file:
 *   ./serviceAccountKey.json
 */

const admin = require("firebase-admin");
const path = require("path");
const crypto = require("crypto");

const email = process.argv[2] || "admin@a.com";

const keyPath = path.resolve(__dirname, "serviceAccountKey.json");
let serviceAccount;
try {
  serviceAccount = require(keyPath);
} catch (_) {
  console.error("Missing serviceAccountKey.json in project root.");
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
  projectId: serviceAccount.project_id,
});

function generatePassword() {
  const base = crypto.randomBytes(12).toString("base64url");
  return `${base}Aa1!`;
}

async function main() {
  const password = generatePassword();
  let user;
  try {
    user = await admin.auth().getUserByEmail(email);
    await admin.auth().updateUser(user.uid, {
      password,
      emailVerified: true,
    });
  } catch (err) {
    if (err && err.code === "auth/user-not-found") {
      user = await admin.auth().createUser({
        email,
        password,
        emailVerified: true,
      });
    } else {
      throw err;
    }
  }

  await admin.auth().setCustomUserClaims(user.uid, { admin: true });
  console.log("Admin account is ready.");
  console.log(`Email: ${email}`);
  console.log(`Password: ${password}`);
  console.log(`UID: ${user.uid}`);
  console.log("Custom claims: { admin: true }");
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    if (err && err.code === "auth/configuration-not-found") {
      console.error(
        "Firebase Authentication is not initialized or Email/Password is disabled for this project."
      );
      console.error(
        "Go to Firebase Console -> Authentication -> Get started, then enable Email/Password."
      );
    }
    console.error(err);
    process.exit(1);
  });
