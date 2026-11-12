const router  = require('express').Router();
const bcrypt  = require('bcryptjs');
const jwt     = require('jsonwebtoken');
const { v4: uuidv4 } = require('uuid');
const pool    = require('../db');
const { authenticate } = require('../middleware/auth');
const { AppError } = require('../utils/errors');

function signToken(userId) {
  return jwt.sign({ sub: userId }, process.env.JWT_SECRET, {
    expiresIn: process.env.JWT_EXPIRES_IN || '7d',
  });
}

function validEmail(s) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s.trim());
}

function validPhone(s) {
  return /^[0-9+\- ]{8,15}$/.test(s.trim());
}

// ─── POST /api/auth/register ────────────────────────────────────────────────
router.post('/register', async (req, res, next) => {
  try {
    const { name, email, password, role, phone } = req.body;

    if (role === 'admin') throw new AppError('Cannot register as admin');
    if (!['renter', 'owner'].includes(role)) throw new AppError('Invalid role');
    if (!name?.trim() || !validEmail(email)) {
      throw new AppError('Please provide a valid name and email');
    }
    if (!validPhone(phone)) throw new AppError('Invalid phone number format');
    if (!password || password.length < 8) {
      throw new AppError('Password must be at least 8 characters');
    }

    const [exists] = await pool.query(
      'SELECT id FROM users WHERE email = ?',
      [email.trim().toLowerCase()]
    );
    if (exists.length) throw new AppError('Email already in use');

    const hash = await bcrypt.hash(password, 12);
    const id   = uuidv4();

    await pool.query(
      `INSERT INTO users (id, role, name, email, password_hash, phone, bank_info, active)
       VALUES (?, ?, ?, ?, ?, ?, '', true)`,
      [id, role, name.trim(), email.trim().toLowerCase(), hash, phone.trim()]
    );

    res.status(201).json({ token: signToken(id), userId: id, role });
  } catch (err) { next(err); }
});

// ─── POST /api/auth/login ────────────────────────────────────────────────────
router.post('/login', async (req, res, next) => {
  try {
    const { email, password } = req.body;
    if (!email || !password) throw new AppError('Email and password required');

    const [rows] = await pool.query(
      'SELECT * FROM users WHERE email = ?',
      [email.trim().toLowerCase()]
    );
    if (!rows.length) throw new AppError('Invalid email or password');

    const user = rows[0];
    if (!user.active) throw new AppError('This account has been disabled');

    const match = await bcrypt.compare(password, user.password_hash);
    if (!match) throw new AppError('Invalid email or password');

    res.json({
      token: signToken(user.id),
      user: {
        id:       user.id,
        name:     user.name,
        email:    user.email,
        role:     user.role,
        phone:    user.phone,
        bankInfo: user.bank_info,
      },
    });
  } catch (err) { next(err); }
});

// ─── GET /api/auth/me ────────────────────────────────────────────────────────
router.get('/me', authenticate, async (req, res, next) => {
  try {
    const u = req.user;
    // Also fetch favorites if renter
    let favorites = [];
    if (u.role === 'renter') {
      const [favRows] = await pool.query(
        'SELECT space_id FROM favorites WHERE user_id = ?',
        [u.id]
      );
      favorites = favRows.map(r => r.space_id);
    }
    res.json({
      id:       u.id,
      name:     u.name,
      email:    u.email,
      role:     u.role,
      phone:    u.phone,
      bankInfo: u.bank_info,
      active:   u.active,
      favorites,
    });
  } catch (err) { next(err); }
});

// ─── PUT /api/auth/profile ───────────────────────────────────────────────────
router.put('/profile', authenticate, async (req, res, next) => {
  try {
    const { name, email, phone, bankInfo } = req.body;
    const u = req.user;

    if (!name?.trim() || !validEmail(email)) {
      throw new AppError('Please provide a valid name and email');
    }
    if (!validPhone(phone)) throw new AppError('Invalid phone number format');

    const [dup] = await pool.query(
      'SELECT id FROM users WHERE email = ? AND id != ?',
      [email.trim().toLowerCase(), u.id]
    );
    if (dup.length) throw new AppError('Email already in use');

    await pool.query(
      `UPDATE users SET name = ?, email = ?, phone = ?, bank_info = ? WHERE id = ?`,
      [
        name.trim(),
        email.trim().toLowerCase(),
        phone.trim(),
        bankInfo !== undefined ? bankInfo.trim() : u.bank_info,
        u.id,
      ]
    );
    res.json({ message: 'Profile updated' });
  } catch (err) { next(err); }
});

// ─── PUT /api/auth/password ──────────────────────────────────────────────────
router.put('/password', authenticate, async (req, res, next) => {
  try {
    const { currentPassword, newPassword, confirmPassword } = req.body;

    const [rows] = await pool.query('SELECT password_hash FROM users WHERE id = ?', [req.user.id]);
    const match  = await bcrypt.compare(currentPassword, rows[0].password_hash);
    if (!match) throw new AppError('Current password is incorrect');
    if (newPassword !== confirmPassword) throw new AppError('Passwords do not match');
    if (!newPassword || newPassword.length < 8) {
      throw new AppError('New password must be at least 8 characters');
    }

    const hash = await bcrypt.hash(newPassword, 12);
    await pool.query('UPDATE users SET password_hash = ? WHERE id = ?', [hash, req.user.id]);
    res.json({ message: 'Password changed' });
  } catch (err) { next(err); }
});

module.exports = router;
