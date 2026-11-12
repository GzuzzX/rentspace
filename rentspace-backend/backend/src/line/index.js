const { LineClient } = require('./line_client');
const { createLineRouter } = require('./line_routes');
const {
  formatTextMessage,
  createBookingFlexBubble,
  createPaymentFlexBubble,
} = require('./line_formatters');
const {
  generateLineSignature,
  validateLineSignature,
} = require('./line_signature');

const lineClient = new LineClient();
const lineRouter = createLineRouter(lineClient);

module.exports = {
  LineClient,
  lineClient,
  lineRouter,
  createLineRouter,
  formatTextMessage,
  createBookingFlexBubble,
  createPaymentFlexBubble,
  generateLineSignature,
  validateLineSignature,
};
