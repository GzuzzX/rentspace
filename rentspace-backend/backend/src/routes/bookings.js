const router = require('express').Router();
const { v4: uuidv4 } = require('uuid');
const pool   = require('../db');
const { authenticate, requireRole } = require('../middleware/auth');
const { AppError } = require('../utils/errors');

const MIN_DURATION = 60;   // minutes
const MAX_DURATION = 720;  // 12 hours
const MAX_DAYS     = 14;

function calcRent(price, start, end, days = 1) {
  const hours = Math.ceil((end - start) / 60);
  return price * hours * days;
}

function parseBooking(row) {
  return {
    id:           row.id,
    spaceId:      row.space_id,
    ownerId:      row.owner_id,
    renterId:     row.renter_id,
    spaceName:    row.space_name,
    date:         row.booking_date,
    startMinutes: row.start_minutes,
    endMinutes:   row.end_minutes,
    days:         row.days_count,
    attendees:    row.attendees,
    zone:         row.zone,
    renterNote:   row.renter_note,
    rentAmount:   row.rent_amount,
    status:       row.status,
    reason:       row.reason,
    createdAt:    row.created_at,
    approvedAt:   row.approved_at,
    confirmedAt:  row.confirmed_at,
    completedAt:  row.completed_at,
    paidOutAt:    row.paid_out_at,
  };
}

// ─── GET /api/bookings ────────────────────────────────────────────────────────
// Renter sees their bookings; Owner sees bookings on their spaces; Admin sees all
router.get('/', authenticate, async (req, res, next) => {
  try {
    let sql   = 'SELECT b.*, p.paid_out_at FROM bookings b LEFT JOIN payments p ON p.booking_id = b.id WHERE 1=1';
    const params = [];

    if (req.user.role === 'renter') {
      sql += ' AND b.renter_id = ?'; params.push(req.user.id);
    } else if (req.user.role === 'owner') {
      sql += ' AND b.owner_id = ?';  params.push(req.user.id);
    }
    // admin: no extra filter

    const { status, spaceId } = req.query;
    if (status)  { sql += ' AND b.status = ?';   params.push(status);  }
    if (spaceId) { sql += ' AND b.space_id = ?'; params.push(spaceId); }

    sql += ' ORDER BY b.created_at DESC';

    const [rows] = await pool.query(sql, params);
    res.json(rows.map(parseBooking));
  } catch (err) { next(err); }
});

// ─── GET /api/bookings/:id ────────────────────────────────────────────────────
router.get('/:id', authenticate, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT b.*, p.paid_out_at FROM bookings b LEFT JOIN payments p ON p.booking_id = b.id WHERE b.id = ?',
      [req.params.id]
    );
    if (!rows.length) throw new AppError('Booking not found', 404);
    const booking = rows[0];

    // Access check
    if (req.user.role !== 'admin' &&
        booking.renter_id !== req.user.id &&
        booking.owner_id  !== req.user.id) {
      throw new AppError('Forbidden', 403);
    }

    // Attach slips
    const [slips] = await pool.query(
      'SELECT id, file_name, note, submitted_at, rejection_reason FROM payment_slips WHERE booking_id = ? ORDER BY id',
      [req.params.id]
    );
    // Attach review
    const [reviews] = await pool.query(
      'SELECT rating, comment, created_at FROM reviews WHERE booking_id = ?',
      [req.params.id]
    );

    res.json({ ...parseBooking(booking), slips, review: reviews[0] || null });
  } catch (err) { next(err); }
});

// ─── POST /api/bookings ───────────────────────────────────────────────────────
router.post('/', authenticate, requireRole('renter'), async (req, res, next) => {
  try {
    const { spaceId, date, startMinutes, endMinutes, days = 1, attendees = 1, zone, renterNote } = req.body;

    if (!spaceId || !date || startMinutes == null || endMinutes == null) {
      throw new AppError('Missing required fields');
    }

    const duration = endMinutes - startMinutes;
    if (startMinutes < 0 || endMinutes > 1440 || endMinutes <= startMinutes) {
      throw new AppError('End time must be after start time');
    }
    if (duration < MIN_DURATION) throw new AppError(`Minimum booking duration is ${MIN_DURATION} minutes`);
    if (duration > MAX_DURATION) throw new AppError(`Maximum booking duration is ${MAX_DURATION / 60} hours`);
    if (days < 1 || days > MAX_DAYS) throw new AppError(`Days must be between 1 and ${MAX_DAYS}`);

    // Fetch space
    const [spaceRows] = await pool.query(
      'SELECT id, owner_id, name, price, status FROM spaces WHERE id = ?',
      [spaceId]
    );
    if (!spaceRows.length) throw new AppError('Space not found', 404);
    const space = spaceRows[0];
    if (space.status !== 'approved') throw new AppError('Space is not available for booking');

    // Conflict check
    const [conflicts] = await pool.query(
      `SELECT id FROM bookings
       WHERE space_id = ? AND status NOT IN ('owner_rejected','canceled')
         AND booking_date <= DATE_ADD(?, INTERVAL ? DAY)
         AND end_date >= ?
         AND start_minutes < ? AND end_minutes > ?`,
      [spaceId, date, days - 1, date, endMinutes, startMinutes]
    );
    if (conflicts.length) throw new AppError('Selected time slot is already booked');

    const rentAmount = calcRent(space.price, startMinutes, endMinutes, days);
    const id = uuidv4();

    await pool.query(
      `INSERT INTO bookings
         (id, space_id, owner_id, renter_id, space_name, booking_date,
          start_minutes, end_minutes, days_count, attendees, zone, renter_note, rent_amount, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'owner_review')`,
      [
        id, spaceId, space.owner_id, req.user.id, space.name,
        date, startMinutes, endMinutes, days, attendees,
        zone || 'Main Zone (Standard)', renterNote || '', rentAmount,
      ]
    );

    res.status(201).json({ id, rentAmount, status: 'owner_review' });
  } catch (err) { next(err); }
});

// ─── POST /api/bookings/:id/approve (owner) ───────────────────────────────────
router.post('/:id/approve', authenticate, requireRole('owner'), async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Booking not found', 404);
    const b = rows[0];
    if (b.owner_id !== req.user.id) throw new AppError('Forbidden', 403);
    if (b.status !== 'owner_review') throw new AppError('Booking is not awaiting your review');

    // Conflict check (another booking may have snuck in)
    const [conflicts] = await pool.query(
      `SELECT id FROM bookings
       WHERE space_id = ? AND id != ? AND status NOT IN ('owner_rejected','canceled')
         AND booking_date <= DATE_ADD(?, INTERVAL ? DAY)
         AND end_date >= ?
         AND start_minutes < ? AND end_minutes > ?`,
      [b.space_id, b.id, b.booking_date, b.days_count - 1, b.booking_date, b.end_minutes, b.start_minutes]
    );
    if (conflicts.length) throw new AppError('Time slot conflict detected, cannot approve');

    await pool.query(
      `UPDATE bookings SET status='payment_due', approved_at=NOW() WHERE id=?`,
      [req.params.id]
    );
    // Create payment row
    await pool.query(
      'INSERT INTO payments (booking_id, amount) VALUES (?, ?)',
      [req.params.id, b.rent_amount]
    );
    res.json({ message: 'Booking approved, awaiting payment' });
  } catch (err) { next(err); }
});

// ─── POST /api/bookings/:id/reject (owner) ────────────────────────────────────
router.post('/:id/reject', authenticate, requireRole('owner'), async (req, res, next) => {
  try {
    const { reason } = req.body;
    if (!reason?.trim()) throw new AppError('Please provide a rejection reason');

    const [rows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Booking not found', 404);
    const b = rows[0];
    if (b.owner_id !== req.user.id) throw new AppError('Forbidden', 403);
    if (b.status !== 'owner_review') throw new AppError('Booking is not awaiting your review');

    await pool.query(
      `UPDATE bookings SET status='owner_rejected', reason=? WHERE id=?`,
      [reason.trim(), req.params.id]
    );
    res.json({ message: 'Booking rejected' });
  } catch (err) { next(err); }
});

// ─── POST /api/bookings/:id/cancel (renter or owner) ─────────────────────────
router.post('/:id/cancel', authenticate, async (req, res, next) => {
  try {
    const [rows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Booking not found', 404);
    const b = rows[0];

    const isRenter = req.user.role === 'renter' && b.renter_id === req.user.id;
    const isOwner  = req.user.role === 'owner'  && b.owner_id  === req.user.id;
    const isAdmin  = req.user.role === 'admin';
    if (!isRenter && !isOwner && !isAdmin) throw new AppError('Forbidden', 403);

    const cancelable = ['owner_review', 'payment_due', 'slip_review', 'slip_rejected'];
    if (!cancelable.includes(b.status)) {
      throw new AppError('This booking cannot be cancelled at this stage');
    }

    await pool.query(
      `UPDATE bookings SET status='canceled', reason=? WHERE id=?`,
      [req.body.reason?.trim() || 'Cancelled', req.params.id]
    );
    res.json({ message: 'Booking cancelled' });
  } catch (err) { next(err); }
});

// ─── POST /api/bookings/:id/review (renter leaves review after completed) ────
router.post('/:id/review', authenticate, requireRole('renter'), async (req, res, next) => {
  try {
    const { rating, comment } = req.body;
    if (!rating || rating < 1 || rating > 5) throw new AppError('Rating must be 1–5');
    if (!comment?.trim()) throw new AppError('Please provide a comment');

    const [rows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.id]);
    if (!rows.length) throw new AppError('Booking not found', 404);
    const b = rows[0];
    if (b.renter_id !== req.user.id) throw new AppError('Forbidden', 403);
    if (b.status !== 'completed') throw new AppError('Can only review completed bookings');

    const [existing] = await pool.query('SELECT 1 FROM reviews WHERE booking_id = ?', [req.params.id]);
    if (existing.length) throw new AppError('You have already reviewed this booking');

    await pool.query(
      'INSERT INTO reviews (booking_id, rating, comment) VALUES (?, ?, ?)',
      [req.params.id, rating, comment.trim()]
    );
    res.status(201).json({ message: 'Review submitted' });
  } catch (err) { next(err); }
});

module.exports = router;
