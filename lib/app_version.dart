/// Build version injected by `--dart-define=APP_VERSION=...`.
/// Falls back to `dev` when running local debug without deploy script.
const String kAppVersion = String.fromEnvironment(
  "APP_VERSION",
  defaultValue: "dev",
);
