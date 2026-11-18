const crypto = require("node:crypto");
const jwt = require("jsonwebtoken");

let argon2 = null;
try {
  argon2 = require("@node-rs/argon2");
} catch (_err) {
  argon2 = null;
}

const IS_PRODUCTION = process.env.NODE_ENV === "production";
if (IS_PRODUCTION && !process.env.JWT_SECRET) {
  throw new Error("JWT_SECRET must be set when NODE_ENV=production");
}
const JWT_SECRET = process.env.JWT_SECRET || crypto.randomBytes(48).toString("hex");
const revokedTokens = new Map();

function sha256Hex(rawText) {
  return crypto.createHash("sha256").update(String(rawText)).digest("hex");
}

function pruneRevokedTokens(nowSeconds) {
  for (const [tokenHash, expiresAt] of revokedTokens) {
    if (expiresAt <= nowSeconds) revokedTokens.delete(tokenHash);
  }
}

function resolveTokenExpiryEpoch(rawToken) {
  const nowSeconds = Math.floor(Date.now() / 1000);
  const decoded = jwt.decode(rawToken);
  if (decoded && Number(decoded.exp) > 0) {
    return Math.floor(Number(decoded.exp));
  }
  return nowSeconds + 7 * 86400;
}

function revokeToken(rawToken) {
  if (!rawToken) return;
  const nowSeconds = Math.floor(Date.now() / 1000);
  const expiresAt = resolveTokenExpiryEpoch(rawToken);
  pruneRevokedTokens(nowSeconds);
  revokedTokens.set(sha256Hex(rawToken), expiresAt);
}

function isTokenRevoked(rawToken) {
  if (!rawToken) return true;
  return revokedTokens.has(sha256Hex(rawToken));
}

async function recordSession(db, userId, rawToken) {
  if (!db || !userId || !rawToken) return;
  const tokenHash = sha256Hex(rawToken);
  const expiresAtEpoch = resolveTokenExpiryEpoch(rawToken);
  await db.query("DELETE FROM auth_sessions WHERE expires_at <= NOW()");
  await db.query(
    "INSERT INTO auth_sessions (user_id, token_hash, expires_at) VALUES (?, ?, FROM_UNIXTIME(?)) ON DUPLICATE KEY UPDATE user_id = VALUES(user_id), expires_at = VALUES(expires_at)",
    [userId, tokenHash, expiresAtEpoch]
  );
}

async function revokeSession(db, rawToken) {
  if (!rawToken) return;
  revokeToken(rawToken);
  if (!db) return;
  await db.query("DELETE FROM auth_sessions WHERE token_hash = ?", [sha256Hex(rawToken)]);
}

async function revokeOtherUserSessions(db, userId, keepRawToken) {
  if (!db || !userId) return;
  if (!keepRawToken) {
    await db.query("DELETE FROM auth_sessions WHERE user_id = ?", [userId]);
    return;
  }
  await db.query(
    "DELETE FROM auth_sessions WHERE user_id = ? AND token_hash <> ?",
    [userId, sha256Hex(keepRawToken)]
  );
}

async function isSessionActive(db, userId, rawToken) {
  if (!db || !userId || !rawToken) return false;
  if (isTokenRevoked(rawToken)) return false;
  const [sessionRows] = await db.query(
    "SELECT session_id FROM auth_sessions WHERE user_id = ? AND token_hash = ? AND expires_at > NOW() LIMIT 1",
    [userId, sha256Hex(rawToken)]
  );
  return sessionRows.length > 0;
}

function hashPassword(plainPassword) {
  const text = String(plainPassword);
  if (argon2) {
    return argon2.hashSync(text);
  }
  return sha256Hex(text);
}

function verifyScryptHash(storedHash, plainPassword) {
  const parts = storedHash.split(/[$:]/);
  if (parts.length !== 3) return false;
  const salt = Buffer.from(parts[1], "hex");
  const expected = Buffer.from(parts[2], "hex");
  const derived = crypto.scryptSync(String(plainPassword), salt, expected.length, {
    N: 16384,
    r: 8,
    p: 1,
    maxmem: 64 * 1024 * 1024,
  });
  return crypto.timingSafeEqual(expected, derived);
}

function verifyPassword(storedHash, plainPassword) {
  if (!storedHash || !plainPassword) return false;
  const text = String(plainPassword);
  if (storedHash.startsWith("$argon2") && argon2) {
    try {
      return argon2.verifySync(storedHash, text);
    } catch (_err) {
      return false;
    }
  }
  if (storedHash.startsWith("scrypt$") || storedHash.startsWith("scrypt:")) {
    try {
      return verifyScryptHash(storedHash, text);
    } catch (_err) {
      return false;
    }
  }
  if (/^[a-f0-9]{64}$/i.test(storedHash)) {
    const expected = Buffer.from(storedHash.toLowerCase(), "hex");
    const actual = Buffer.from(sha256Hex(text), "hex");
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  }
  return false;
}

function normalizeRoleForApp(dbRole) {
  if (dbRole === "customer" || dbRole === "user") return "renter";
  if (dbRole === "owner" || dbRole === "admin") return dbRole;
  return "renter";
}

function normalizeRoleForDb(appRole) {
  if (appRole === "renter" || appRole === "user") return "customer";
  if (appRole === "owner" || appRole === "admin") return appRole;
  return "customer";
}

function isValidEmail(email) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(String(email || "").trim());
}

function isValidPhone(phone) {
  return /^[0-9+\- ]{8,15}$/.test(String(phone || "").trim());
}

function extractUsernameSeed(rawUsername, email) {
  const cleanName = typeof rawUsername === "string" ? rawUsername.trim() : "";
  if (cleanName) return cleanName;
  const cleanEmail = typeof email === "string" ? email.split("@")[0].trim() : "";
  return cleanEmail || "user";
}

function buildUniqueUsername(rawUsername, email) {
  const safeBase = extractUsernameSeed(rawUsername, email).replace(/\s+/g, "_").slice(0, 32);
  return `${safeBase}_${crypto.randomBytes(6).toString("hex")}`;
}

function signToken(userRow) {
  const payload = {
    id: userRow.user_id,
    user_id: userRow.user_id,
    username: userRow.username,
    email: userRow.email,
    role: normalizeRoleForApp(userRow.role),
    dbRole: userRow.role,
  };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: "7d", jwtid: crypto.randomUUID() });
}

function expandAllowedRoles(allowedRoles) {
  const list = Array.isArray(allowedRoles) ? allowedRoles : [allowedRoles];
  const expanded = new Set();
  for (const role of list) {
    if (!role) continue;
    expanded.add(role);
    if (role === "customer" || role === "renter" || role === "user") {
      expanded.add("customer");
      expanded.add("renter");
      expanded.add("user");
    }
  }
  return expanded;
}

async function findActiveAccount(userId, dbOverride) {
  const db = dbOverride || require("./db_config").promise();
  const [accounts] = await db.query(
    "SELECT role, status FROM users WHERE user_id = ? LIMIT 1",
    [userId]
  );
  return accounts[0] || null;
}

function isAccountSuspended(account) {
  return (
    !account ||
    account.status === "suspended" ||
    account.status === "disabled" ||
    account.role === "disabled"
  );
}

function hasAllowedRole(allowedSet, decodedUser) {
  if (allowedSet.size === 0) return true;
  return allowedSet.has(decodedUser.role) || allowedSet.has(decodedUser.dbRole);
}

async function authorizeDecodedToken(decodedUser, allowedSet, request, response, nextFn) {
  try {
    const db = require("./db_config").promise();
    const sessionActive = await isSessionActive(db, decodedUser.id, request.rawToken);
    if (!sessionActive) {
      return response.status(401).json({ error: "Invalid or expired token" });
    }
    const account = await findActiveAccount(decodedUser.id, db);
    if (isAccountSuspended(account)) {
      return response.status(401).json({ error: "บัญชีถูกระงับหรือไม่พบบัญชี" });
    }
    decodedUser.dbRole = account.role;
    decodedUser.role = normalizeRoleForApp(account.role);
    request.user = decodedUser;
    if (!hasAllowedRole(allowedSet, decodedUser)) {
      return response.status(403).json({ error: "Access denied: insufficient permissions" });
    }
    return nextFn();
  } catch (_dbErr) {
    return response.status(503).json({ error: "Database unavailable" });
  }
}

const verifyToken = (allowedRoles = []) => {
  const roles = expandAllowedRoles(allowedRoles);
  return (req, res, next) => {
    const authHeader = req.headers["authorization"];
    const token = authHeader && authHeader.split(" ")[1];
    if (!token) {
      return res.status(401).json({ error: "Access token missing" });
    }
    if (isTokenRevoked(token)) {
      return res.status(401).json({ error: "Invalid or expired token" });
    }
    jwt.verify(token, JWT_SECRET, (err, decodedUser) => {
      if (err) {
        return res.status(401).json({ error: "Invalid or expired token" });
      }
      req.rawToken = token;
      void authorizeDecodedToken(decodedUser, roles, req, res, next);
    });
  };
};

function resolveClientAddress(request) {
  const forwarded = request.headers?.["x-forwarded-for"];
  if (typeof forwarded === "string" && forwarded.trim()) {
    return forwarded.split(",")[0].trim();
  }
  return request.ip || request.socket?.remoteAddress || "unknown";
}

function pruneWindowAttempts(attemptList, cutoffEpoch) {
  return attemptList.filter((timestamp) => timestamp > cutoffEpoch);
}

function pruneExpiredBuckets(attemptBuckets, cutoffEpoch) {
  for (const [clientKey, attemptList] of attemptBuckets) {
    if (pruneWindowAttempts(attemptList, cutoffEpoch).length === 0) {
      attemptBuckets.delete(clientKey);
    }
  }
}

function createAuthRateLimiter({ windowMs = 60000, maxAttempts = 40 } = {}) {
  const attemptBuckets = new Map();
  return function authRateLimiter(request, response, nextFn) {
    const nowEpoch = Date.now();
    const cutoffEpoch = nowEpoch - windowMs;
    const clientAddress = resolveClientAddress(request);
    const activeAttempts = pruneWindowAttempts(
      attemptBuckets.get(clientAddress) || [],
      cutoffEpoch
    );
    if (activeAttempts.length >= maxAttempts) {
      attemptBuckets.set(clientAddress, activeAttempts);
      return response.status(429).json({
        error: "คำขอเข้าสู่ระบบถี่เกินไป กรุณารอสักครู่แล้วลองใหม่",
      });
    }
    activeAttempts.push(nowEpoch);
    attemptBuckets.set(clientAddress, activeAttempts);
    if (attemptBuckets.size > 500) pruneExpiredBuckets(attemptBuckets, cutoffEpoch);
    return nextFn();
  };
}

module.exports = {
  JWT_SECRET,
  sha256Hex,
  hashPassword,
  verifyPassword,
  revokeToken,
  isTokenRevoked,
  recordSession,
  revokeSession,
  revokeOtherUserSessions,
  isSessionActive,
  isValidEmail,
  isValidPhone,
  buildUniqueUsername,
  normalizeRoleForApp,
  normalizeRoleForDb,
  signToken,
  verifyToken,
  createAuthRateLimiter,
};
