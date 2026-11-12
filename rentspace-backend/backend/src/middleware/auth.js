const jwt = require('jsonwebtoken');
const pool = require('../db');
const { AppError } = require('../utils/errors');

/** Attach req.user from Bearer JWT. Throws 401 if missing/invalid. */
async function authenticate(req, res, next) {
  try {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      throw new AppError('Unauthorized', 401);
    }
    const token = header.slice(7);
    const payload = jwt.verify(token, process.env.JWT_SECRET);

    const [rows] = await pool.query(
      'SELECT id, role, name, email, phone, bank_info, active FROM users WHERE id = ?',
      [payload.sub]
    );
    if (!rows.length || !rows[0].active) {
      throw new AppError('Unauthorized', 401);
    }
    req.user = rows[0];
    next();
  } catch (err) {
    if (err instanceof AppError) return next(err);
    next(new AppError('Unauthorized', 401));
  }
}

/** Require specific role(s). Call after authenticate(). */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!roles.includes(req.user.role)) {
      return next(new AppError('Forbidden', 403));
    }
    next();
  };
}

module.exports = { authenticate, requireRole };
