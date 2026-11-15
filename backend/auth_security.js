const crypto = require("node:crypto");
const jwt = require("jsonwebtoken");

let argon2 = null;
try {
  argon2 = require("@node-rs/argon2");
} catch (_err) {
  argon2 = null;
}

const JWT_SECRET = process.env.JWT_SECRET || "your_super_secret_jwt_key_here";

function sha256Hex(rawText) {
  return crypto.createHash("sha256").update(String(rawText)).digest("hex");
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
  return storedHash === sha256Hex(text) || storedHash === text;
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

function signToken(userRow) {
  const payload = {
    id: userRow.user_id,
    user_id: userRow.user_id,
    username: userRow.username,
    email: userRow.email,
    role: normalizeRoleForApp(userRow.role),
    dbRole: userRow.role,
  };
  return jwt.sign(payload, JWT_SECRET, { expiresIn: "7d" });
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

const verifyToken = (allowedRoles = []) => {
  const roles = expandAllowedRoles(allowedRoles);
  return (req, res, next) => {
    const authHeader = req.headers["authorization"];
    const token = authHeader && authHeader.split(" ")[1];
    if (!token) {
      return res.status(401).json({ error: "Access token missing" });
    }
    jwt.verify(token, JWT_SECRET, (err, decodedUser) => {
      if (err) {
        return res.status(401).json({ error: "Invalid or expired token" });
      }
      req.user = decodedUser;
      if (roles.size > 0 && !roles.has(decodedUser.role) && !roles.has(decodedUser.dbRole)) {
        return res.status(403).json({ error: "Access denied: insufficient permissions" });
      }
      return next();
    });
  };
};

module.exports = {
  JWT_SECRET,
  sha256Hex,
  hashPassword,
  verifyPassword,
  normalizeRoleForApp,
  normalizeRoleForDb,
  signToken,
  verifyToken,
};
