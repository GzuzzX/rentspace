require('dotenv').config();
const express = require('express');
const cors    = require('cors');
const { errorHandler } = require('./utils/errors');

const authRoutes    = require('./routes/auth');
const spaceRoutes   = require('./routes/spaces');
const bookingRoutes = require('./routes/bookings');
const paymentRoutes = require('./routes/payments');
const adminRoutes   = require('./routes/admin');
const { lineRouter }  = require('./line');

const app  = express();
const PORT = process.env.PORT || 3000;

// ─── Middleware ───────────────────────────────────────────────────────────────
app.use(cors());
app.use(express.json({
  verify: (req, _res, bufferChunk) => {
    req.rawBody = bufferChunk;
  },
}));
app.use(express.urlencoded({ extended: true }));

// ─── Health check ─────────────────────────────────────────────────────────────
app.get('/health',     (req, res) => res.json({ status: 'ok', data: { status: 'ok' }, time: new Date() }));
app.get('/api/health', (req, res) => res.json({ status: 'ok', data: { status: 'ok' }, time: new Date() }));

// ─── Routes ───────────────────────────────────────────────────────────────────
app.use('/api/auth',     authRoutes);
app.use('/api/spaces',   spaceRoutes);
app.use('/api/bookings', bookingRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/admin',    adminRoutes);
app.use('/api/line',     lineRouter);

// ─── 404 ──────────────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ error: 'Route not found' }));

// ─── Error handler ────────────────────────────────────────────────────────────
app.use(errorHandler);

// ─── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, () => {
  console.log(`🚀 RentSpace API running on http://localhost:${PORT}`);
});

module.exports = app;
