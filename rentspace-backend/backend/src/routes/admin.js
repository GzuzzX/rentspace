const router = require('express').Router();
const pool   = require('../db');
const { authenticate, requireRole } = require('../middleware/auth');
const { AppError } = require('../utils/errors');

const adminOnly = [authenticate, requireRole('admin')];

// ─── GET /api/admin/spaces ────────────────────────────────────────────────────
// All spaces (optionally filter by status)
router.get('/spaces', ...adminOnly, async (req, res, next) => {
  try {
    const { status } = req.query;
    let sql = 'SELECT s.*, u.name AS owner_name FROM spaces s JOIN users u ON u.id = s.owner_id';
    const params = [];
    if (status) { sql += ' WHERE s.status = ?'; params.push(status); }
    sql += ' ORDER BY s.status, s.name';
    const [rows] = await pool.query(sql, params);
    res.json(rows.map(r => ({
      ...r,
      amenities: typeof r.amenities === 'string' ? JSON.parse(r.amenities) : r.amenities,
      hours:     typeof r.hours     === 'string' ? JSON.parse(r.hours)     : r.hours,
    })));
  } catch (err) { next(err); }
});

// ─── PUT /api/admin/spaces/:id/approve ───────────────────────────────────────
router.put('/spaces/:id/approve', ...adminOnly, async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT status FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    await pool.query(
      `UPDATE spaces SET status='approved', review_reason=NULL WHERE id=?`,
      [req.params.id]
    );
    res.json({ message: 'Space approved' });
  } catch (err) { next(err); }
});

// ─── PUT /api/admin/spaces/:id/reject ────────────────────────────────────────
router.put('/spaces/:id/reject', ...adminOnly, async (req, res, next) => {
  try {
    const { reason } = req.body;
    if (!reason?.trim()) throw new AppError('Please provide a rejection reason');
    const [rows] = await pool.query('SELECT status FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    await pool.query(
      `UPDATE spaces SET status='rejected', review_reason=? WHERE id=?`,
      [reason.trim(), req.params.id]
    );
    res.json({ message: 'Space rejected' });
  } catch (err) { next(err); }
});

// ─── PUT /api/admin/spaces/:id/activate ──────────────────────────────────────
// Re-activate a previously rejected space
router.put('/spaces/:id/activate', ...adminOnly, async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT id FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    await pool.query(
      `UPDATE spaces SET status='approved', review_reason=NULL WHERE id=?`,
      [req.params.id]
    );
    res.json({ message: 'Space activated' });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/users ─────────────────────────────────────────────────────
router.get('/users', ...adminOnly, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT id, role, name, email, phone, bank_info, active FROM users ORDER BY role, name'
    );
    res.json(rows);
  } catch (err) { next(err); }
});

// ─── PUT /api/admin/users/:id/toggle ─────────────────────────────────────────
// Activate / deactivate a user account
router.put('/users/:id/toggle', ...adminOnly, async (req, res, next) => {
  try {
    if (req.params.id === req.user.id) throw new AppError('Cannot disable your own account');
    const [rows] = await pool.query('SELECT active FROM users WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('User not found', 404);
    const newActive = !rows[0].active;
    await pool.query('UPDATE users SET active=? WHERE id=?', [newActive, req.params.id]);
    res.json({ active: newActive });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/issues ────────────────────────────────────────────────────
router.get('/issues', ...adminOnly, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT i.*, u.name AS reporter_name
       FROM issues i JOIN users u ON u.id = i.reporter_id
       ORDER BY i.closed ASC, i.id DESC`
    );
    res.json(rows);
  } catch (err) { next(err); }
});

// ─── PUT /api/admin/issues/:id/close ─────────────────────────────────────────
router.put('/issues/:id/close', ...adminOnly, async (req, res, next) => {
  try {
    const { resolution } = req.body;
    if (!resolution?.trim()) throw new AppError('Please provide a resolution');
    const [rows] = await pool.query('SELECT closed FROM issues WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Issue not found', 404);
    if (rows[0].closed) throw new AppError('Issue already closed');
    await pool.query(
      'UPDATE issues SET closed=1, resolution=? WHERE id=?',
      [resolution.trim(), req.params.id]
    );
    res.json({ message: 'Issue closed' });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/bookings ──────────────────────────────────────────────────
router.get('/bookings', ...adminOnly, async (req, res, next) => {
  try {
    const { status } = req.query;
    let sql = `
      SELECT b.*, p.paid_out_at,
             ur.name AS renter_name, uo.name AS owner_name
      FROM bookings b
      LEFT JOIN payments p ON p.booking_id = b.id
      JOIN users ur ON ur.id = b.renter_id
      JOIN users uo ON uo.id = b.owner_id
    `;
    const params = [];
    if (status) { sql += ' WHERE b.status = ?'; params.push(status); }
    sql += ' ORDER BY b.created_at DESC';
    const [rows] = await pool.query(sql, params);
    res.json(rows);
  } catch (err) { next(err); }
});

// ─── POST /api/admin/issues (any logged-in user can file an issue) ────────────
router.post('/issues', authenticate, async (req, res, next) => {
  try {
    const { subject, detail } = req.body;
    if (!detail?.trim()) throw new AppError('Please provide details');
    const { v4: uuidv4 } = require('uuid');
    const id = uuidv4();
    await pool.query(
      'INSERT INTO issues (id, reporter_id, subject, detail) VALUES (?, ?, ?, ?)',
      [id, req.user.id, subject || 'General Issue', detail.trim()]
    );
    res.status(201).json({ id, message: 'Issue filed' });
  } catch (err) { next(err); }
});

// ─── GET /api/admin/audit ─────────────────────────────────────────────────────
router.get('/audit', ...adminOnly, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT * FROM audit_log ORDER BY acted_at DESC LIMIT 200'
    );
    res.json(rows);
  } catch (err) { next(err); }
});

module.exports = router;
