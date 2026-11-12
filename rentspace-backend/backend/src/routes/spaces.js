const router = require('express').Router();
const { v4: uuidv4 } = require('uuid');
const pool   = require('../db');
const { authenticate, requireRole } = require('../middleware/auth');
const { AppError } = require('../utils/errors');

// ─── Helper ──────────────────────────────────────────────────────────────────
function parseSpace(row) {
  return {
    ...row,
    amenities: typeof row.amenities === 'string' ? JSON.parse(row.amenities) : row.amenities,
    hours:     typeof row.hours     === 'string' ? JSON.parse(row.hours)     : row.hours,
  };
}

// ─── GET /api/spaces ─────────────────────────────────────────────────────────
// Public (approved only). Query params: category, search, sort
router.get('/', async (req, res, next) => {
  try {
    const { category, search, sort } = req.query;
    let sql = `
      SELECT s.*, u.name AS owner_name,
        COALESCE(AVG(r.rating), NULL) AS avg_rating,
        COUNT(r.booking_id) AS review_count
      FROM spaces s
      JOIN users u ON u.id = s.owner_id
      LEFT JOIN reviews r ON r.booking_id IN (
        SELECT id FROM bookings WHERE space_id = s.id AND status = 'completed'
      )
      WHERE s.status = 'approved'
    `;
    const params = [];

    if (category) { sql += ' AND s.category = ?'; params.push(category); }
    if (search)   {
      sql += ' AND (s.name LIKE ? OR s.location LIKE ? OR s.description LIKE ?)';
      const q = `%${search}%`;
      params.push(q, q, q);
    }

    sql += ' GROUP BY s.id';

    if (sort === 'priceAsc')      sql += ' ORDER BY s.price ASC';
    else if (sort === 'priceDesc') sql += ' ORDER BY s.price DESC';
    else if (sort === 'capacityDesc') sql += ' ORDER BY s.capacity DESC';
    else sql += ' ORDER BY avg_rating DESC, review_count DESC'; // recommended

    const [rows] = await pool.query(sql, params);
    res.json(rows.map(parseSpace));
  } catch (err) { next(err); }
});

// ─── GET /api/spaces/:id ─────────────────────────────────────────────────────
router.get('/:id', async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT s.*, u.name AS owner_name,
        COALESCE(AVG(r.rating), NULL) AS avg_rating,
        COUNT(r.booking_id) AS review_count
       FROM spaces s
       JOIN users u ON u.id = s.owner_id
       LEFT JOIN reviews r ON r.booking_id IN (
         SELECT id FROM bookings WHERE space_id = s.id AND status = 'completed'
       )
       WHERE s.id = ?
       GROUP BY s.id`,
      [req.params.id]
    );
    if (!rows.length) throw new AppError('Space not found', 404);
    res.json(parseSpace(rows[0]));
  } catch (err) { next(err); }
});

// ─── POST /api/spaces ────────────────────────────────────────────────────────
router.post('/', authenticate, requireRole('owner'), async (req, res, next) => {
  try {
    const { name, category, location, price, capacity, description, image, amenities, hours } = req.body;
    if (!name || !category || !location || !price || !capacity || !description) {
      throw new AppError('Missing required fields');
    }
    if (price <= 0) throw new AppError('Price must be positive');
    if (capacity <= 0) throw new AppError('Capacity must be positive');

    const id = uuidv4();
    await pool.query(
      `INSERT INTO spaces (id, owner_id, name, category, location, price, capacity, description, image, amenities, hours, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
      [
        id,
        req.user.id,
        name.trim(),
        category.trim(),
        location.trim(),
        Number(price),
        Number(capacity),
        description.trim(),
        image || '',
        JSON.stringify(amenities || []),
        JSON.stringify(hours || []),
      ]
    );
    res.status(201).json({ id, status: 'pending' });
  } catch (err) { next(err); }
});

// ─── PUT /api/spaces/:id ─────────────────────────────────────────────────────
router.put('/:id', authenticate, requireRole('owner', 'admin'), async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    const space = rows[0];

    if (req.user.role === 'owner' && space.owner_id !== req.user.id) {
      throw new AppError('You can only edit your own spaces', 403);
    }

    const { name, category, location, price, capacity, description, image, amenities, hours } = req.body;
    await pool.query(
      `UPDATE spaces SET name=?, category=?, location=?, price=?, capacity=?,
       description=?, image=?, amenities=?, hours=?, status='pending', review_reason=NULL
       WHERE id=?`,
      [
        (name || space.name).trim(),
        (category || space.category).trim(),
        (location || space.location).trim(),
        price !== undefined ? Number(price) : space.price,
        capacity !== undefined ? Number(capacity) : space.capacity,
        (description || space.description).trim(),
        image !== undefined ? image : space.image,
        JSON.stringify(amenities || JSON.parse(space.amenities)),
        JSON.stringify(hours     || JSON.parse(space.hours)),
        req.params.id,
      ]
    );
    res.json({ message: 'Space updated, pending re-approval' });
  } catch (err) { next(err); }
});

// ─── DELETE /api/spaces/:id ──────────────────────────────────────────────────
router.delete('/:id', authenticate, requireRole('owner', 'admin'), async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT owner_id FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    if (req.user.role === 'owner' && rows[0].owner_id !== req.user.id) {
      throw new AppError('Forbidden', 403);
    }
    await pool.query('DELETE FROM spaces WHERE id = ?', [req.params.id]);
    res.json({ message: 'Space deleted' });
  } catch (err) { next(err); }
});

// ─── GET /api/spaces/:id/reviews ─────────────────────────────────────────────
router.get('/:id/reviews', async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      `SELECT r.rating, r.comment, r.created_at, u.name AS renter_name
       FROM reviews r
       JOIN bookings b ON b.id = r.booking_id
       JOIN users u ON u.id = b.renter_id
       WHERE b.space_id = ?
       ORDER BY r.created_at DESC`,
      [req.params.id]
    );
    res.json(rows);
  } catch (err) { next(err); }
});

// ─── GET /api/spaces/:id/slots?date=YYYY-MM-DD ───────────────────────────────
// Returns available hourly slots and busy slot labels for a date
router.get('/:id/slots', async (req, res, next) => {
  try {
    const { date } = req.query;
    if (!date) throw new AppError('date query param required');

    const [spaceRows] = await pool.query('SELECT hours FROM spaces WHERE id = ?', [req.params.id]);
    if (!spaceRows.length) throw new AppError('Space not found', 404);

    const hours = JSON.parse(spaceRows[0].hours);
    const jsDate = new Date(date);
    // JS: 0=Sun, 1=Mon... our hours array: index 0=Mon per Flutter (weekday-1)
    const dayIndex = (jsDate.getDay() + 6) % 7; // convert to Mon=0
    const day = hours[dayIndex];

    if (!day || !day.open) {
      return res.json({ open: false, slots: [], busyLabels: [] });
    }

    // Active bookings that overlap the date
    const [bookings] = await pool.query(
      `SELECT start_minutes, end_minutes, days_count, status
       FROM bookings
       WHERE space_id = ? AND status NOT IN ('owner_rejected','canceled')
         AND booking_date <= ? AND end_date >= ?`,
      [req.params.id, date, date]
    );

    // Blocked periods
    const [blocked] = await pool.query(
      `SELECT start_at, end_at, reason FROM blocked_periods
       WHERE space_id = ? AND start_at < DATE_ADD(?, INTERVAL 1 DAY) AND end_at > ?`,
      [req.params.id, date, date]
    );

    const busyLabels = [
      ...bookings.map(b => `Booked ${minuteLabel(b.start_minutes)}–${minuteLabel(b.end_minutes)}${b.days_count > 1 ? ` (${b.days_count} days)` : ''}`),
      ...blocked.map(b => `Blocked (${b.reason})`),
    ];

    // Build hourly slots
    const slots = [];
    for (let m = day.start; m + 60 <= day.end; m += 60) {
      const isBusy = bookings.some(b => m < b.end_minutes && m + 60 > b.start_minutes);
      slots.push({ start: m, end: m + 60, available: !isBusy });
    }

    res.json({ open: true, slots, busyLabels });
  } catch (err) { next(err); }
});

// ─── PUT /api/spaces/:id/availability ────────────────────────────────────────
router.put('/:id/availability', authenticate, requireRole('owner'), async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT owner_id FROM spaces WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Space not found', 404);
    if (rows[0].owner_id !== req.user.id) throw new AppError('Forbidden', 403);

    const { days, blocks } = req.body; // days: array of 7 {open,start,end}; blocks: [{start,end,reason}]
    if (!days || days.length !== 7) throw new AppError('Must provide 7-day schedule');

    // Update hours in spaces table
    await pool.query('UPDATE spaces SET hours = ? WHERE id = ?', [JSON.stringify(days), req.params.id]);

    // Replace blocked periods
    await pool.query('DELETE FROM blocked_periods WHERE space_id = ?', [req.params.id]);
    if (blocks && blocks.length) {
      const values = blocks.map(b => [uuidv4(), req.params.id, b.start, b.end, b.reason || '']);
      await pool.query(
        'INSERT INTO blocked_periods (id, space_id, start_at, end_at, reason) VALUES ?',
        [values]
      );
    }
    res.json({ message: 'Availability updated' });
  } catch (err) { next(err); }
});

// ─── POST /api/spaces/:id/favorite ───────────────────────────────────────────
router.post('/:id/favorite', authenticate, requireRole('renter'), async (req, res, next) => {
  try {
    const [space] = await pool.query('SELECT id FROM spaces WHERE id = ?', [req.params.id]);
    if (!space.length) throw new AppError('Space not found', 404);

    const [fav] = await pool.query(
      'SELECT 1 FROM favorites WHERE user_id = ? AND space_id = ?',
      [req.user.id, req.params.id]
    );

    if (fav.length) {
      await pool.query('DELETE FROM favorites WHERE user_id = ? AND space_id = ?', [req.user.id, req.params.id]);
      res.json({ favorited: false });
    } else {
      await pool.query('INSERT INTO favorites (user_id, space_id) VALUES (?, ?)', [req.user.id, req.params.id]);
      res.json({ favorited: true });
    }
  } catch (err) { next(err); }
});

// ─── GET /api/spaces/mine (owner's own spaces) ───────────────────────────────
router.get('/owner/mine', authenticate, requireRole('owner'), async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT * FROM spaces WHERE owner_id = ? ORDER BY name',
      [req.user.id]
    );
    res.json(rows.map(parseSpace));
  } catch (err) { next(err); }
});

// ─── Helpers ─────────────────────────────────────────────────────────────────
function minuteLabel(m) {
  return `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}`;
}

module.exports = router;
