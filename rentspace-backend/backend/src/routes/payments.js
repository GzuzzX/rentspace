const router = require('express').Router();
const multer = require('multer');
const pool   = require('../db');
const { authenticate, requireRole } = require('../middleware/auth');
const { AppError } = require('../utils/errors');

// Store slips in memory (saved to DB as BLOB)
const upload = multer({
  storage: multer.memoryStorage(),
  limits:  { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter(req, file, cb) {
    if (!['image/jpeg', 'image/png'].includes(file.mimetype)) {
      return cb(new AppError('Only JPG/PNG allowed'));
    }
    cb(null, true);
  },
});

// ─── GET /api/payments/:bookingId ────────────────────────────────────────────
router.get('/:bookingId', authenticate, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT * FROM payments WHERE booking_id = ?',
      [req.params.bookingId]
    );
    if (!rows.length) throw new AppError('Payment record not found', 404);

    const [slips] = await pool.query(
      `SELECT id, file_name, note, submitted_at, rejection_reason
       FROM payment_slips WHERE booking_id = ? ORDER BY id`,
      [req.params.bookingId]
    );

    res.json({ ...rows[0], slips });
  } catch (err) { next(err); }
});

// ─── GET /api/payments/:bookingId/slip/:slipId/image ─────────────────────────
// Serves the raw image bytes (for Flutter Image.memory)
router.get('/:bookingId/slip/:slipId/image', authenticate, async (req, res, next) => {
  try {
    const [rows] = await pool.query(
      'SELECT image_data, file_name FROM payment_slips WHERE id = ? AND booking_id = ?',
      [req.params.slipId, req.params.bookingId]
    );
    if (!rows.length) throw new AppError('Slip not found', 404);
    const slip = rows[0];
    const ext  = slip.file_name.toLowerCase().endsWith('.png') ? 'png' : 'jpeg';
    res.set('Content-Type', `image/${ext}`);
    res.send(slip.image_data);
  } catch (err) { next(err); }
});

// ─── POST /api/payments/:bookingId/slip ──────────────────────────────────────
// Renter uploads payment slip (multipart/form-data: file, note)
router.post('/:bookingId/slip', authenticate, requireRole('renter'),
  upload.single('file'), async (req, res, next) => {
    try {
      const [bookRows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.bookingId]);
      if (!bookRows.length) throw new AppError('Booking not found', 404);
      const b = bookRows[0];
      if (b.renter_id !== req.user.id) throw new AppError('Forbidden', 403);

      if (!['payment_due', 'slip_rejected'].includes(b.status)) {
        throw new AppError('Booking is not awaiting payment');
      }
      if (!req.file) throw new AppError('Please attach a payment slip image');

      await pool.query(
        `INSERT INTO payment_slips (booking_id, file_name, image_data, note)
         VALUES (?, ?, ?, ?)`,
        [req.params.bookingId, req.file.originalname, req.file.buffer, req.body.note || '']
      );
      await pool.query(
        `UPDATE bookings SET status='slip_review', slip_rejected_at=NULL, reason='' WHERE id=?`,
        [req.params.bookingId]
      );

      res.status(201).json({ message: 'Slip uploaded, awaiting review' });
    } catch (err) { next(err); }
  }
);

// ─── POST /api/payments/:bookingId/review (admin: approve/reject slip) ───────
router.post('/:bookingId/review', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const { approve, reason } = req.body;

    const [bookRows] = await pool.query('SELECT * FROM bookings WHERE id = ?', [req.params.bookingId]);
    if (!bookRows.length) throw new AppError('Booking not found', 404);
    const b = bookRows[0];
    if (b.status !== 'slip_review') throw new AppError('No slip pending review');

    const [slipRows] = await pool.query(
      'SELECT id FROM payment_slips WHERE booking_id = ? ORDER BY id DESC LIMIT 1',
      [req.params.bookingId]
    );
    if (!slipRows.length) throw new AppError('No slip found');

    if (approve) {
      await pool.query(
        `UPDATE bookings SET status='confirmed', confirmed_at=NOW() WHERE id=?`,
        [req.params.bookingId]
      );
      await pool.query(
        `UPDATE payment_slips SET rejection_reason=NULL WHERE id=?`,
        [slipRows[0].id]
      );
    } else {
      if (!reason?.trim()) throw new AppError('Please provide a rejection reason');
      await pool.query(
        `UPDATE bookings SET status='slip_rejected', slip_rejected_at=NOW(), reason=? WHERE id=?`,
        [reason.trim(), req.params.bookingId]
      );
      await pool.query(
        `UPDATE payment_slips SET rejection_reason=? WHERE id=?`,
        [reason.trim(), slipRows[0].id]
      );
    }

    res.json({ message: approve ? 'Slip approved, booking confirmed' : 'Slip rejected' });
  } catch (err) { next(err); }
});

// ─── POST /api/payments/:bookingId/payout (admin: mark owner paid) ───────────
router.post('/:bookingId/payout', authenticate, requireRole('admin'), async (req, res, next) => {
  try {
    const [bookRows] = await pool.query('SELECT status FROM bookings WHERE id = ?', [req.params.bookingId]);
    if (!bookRows.length) throw new AppError('Booking not found', 404);
    if (bookRows[0].status !== 'completed') throw new AppError('Booking is not completed');

    const [payRows] = await pool.query('SELECT paid_out_at FROM payments WHERE booking_id = ?', [req.params.bookingId]);
    if (!payRows.length) throw new AppError('Payment record not found', 404);
    if (payRows[0].paid_out_at) throw new AppError('Already paid out');

    await pool.query('UPDATE payments SET paid_out_at=NOW() WHERE booking_id=?', [req.params.bookingId]);
    res.json({ message: 'Payout recorded' });
  } catch (err) { next(err); }
});

module.exports = router;
