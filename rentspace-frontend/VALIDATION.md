# Validation status — 2026-11-15

The previous 144-test report described an older implementation and is not evidence for this version.

Default Flutter tests now exclude the live database suite. Run live tests only against a disposable seeded database using `flutter test --dart-define=RUN_LIVE_TESTS=true --dart-define=API_BASE_URL=http://localhost:3001/api`. The suite writes data. Tokens are obtained by login instead of embedded in source.

Backend `npm test` runs authentication unit tests. `npm run test:integration` uses a live database and must only target a disposable database.

Set a strong persistent JWT_SECRET before starting the backend. Without it, a random process-local key is used; sessions expire on restart. Restart the backend to load code changes and log in again.

Image decoding now tolerates damaged Base64 values. Existing damaged images still need replacement from their original files.

Full device, concurrency, and end-to-end validation remains required before release.
