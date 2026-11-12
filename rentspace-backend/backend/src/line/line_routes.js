const express = require('express');
const { AppError } = require('../utils/errors');
const { authenticate, requireRole } = require('../middleware/auth');

function createLineRouter(lineClientInstance) {
  const router = express.Router();

  router.get('/health', (req, res) => {
    res.json({
      configured: lineClientInstance.isConfigured(),
      endpoint: '/api/line',
    });
  });

  router.post('/webhook', (req, res, next) => {
    try {
      const signatureHeader = req.headers['x-line-signature'];
      const rawBodyBuffer = req.rawBody || Buffer.from(JSON.stringify(req.body || {}), 'utf8');

      const isValidSignature = lineClientInstance.verifyWebhookSignature(
        rawBodyBuffer,
        signatureHeader
      );

      if (!isValidSignature) {
        throw new AppError('Invalid LINE signature', 401);
      }

      const eventList = req.body?.events || [];
      res.status(200).json({ received: eventList.length });
    } catch (routeError) {
      next(routeError);
    }
  });

  router.post('/push', authenticate, requireRole('admin'), async (req, res, next) => {
    try {
      const { recipientUserId, message } = req.body;
      if (!recipientUserId || !message) {
        throw new AppError('recipientUserId and message are required', 400);
      }
      const pushOutcome = await lineClientInstance.pushMessage(recipientUserId, message);
      res.json({ success: true, details: pushOutcome });
    } catch (routeError) {
      next(routeError);
    }
  });

  return router;
}

module.exports = { createLineRouter };
