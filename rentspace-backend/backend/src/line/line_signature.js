const crypto = require('node:crypto');

function generateLineSignature(rawBodyBuffer, secretKey) {
  if (!Buffer.isBuffer(rawBodyBuffer)) {
    throw new TypeError('rawBodyBuffer must be a Buffer instance');
  }
  if (typeof secretKey !== 'string' || secretKey.length === 0) {
    throw new Error('LINE channel secret cannot be empty');
  }
  return crypto
    .createHmac('sha256', secretKey)
    .update(rawBodyBuffer)
    .digest('base64');
}

function validateLineSignature(rawBodyBuffer, signatureHeader, secretKey) {
  if (!signatureHeader || typeof signatureHeader !== 'string') {
    return false;
  }
  const computedSignature = generateLineSignature(rawBodyBuffer, secretKey);
  const sourceBuffer = Buffer.from(signatureHeader, 'utf8');
  const targetBuffer = Buffer.from(computedSignature, 'utf8');

  if (sourceBuffer.length !== targetBuffer.length) {
    return false;
  }
  return crypto.timingSafeEqual(sourceBuffer, targetBuffer);
}

module.exports = {
  generateLineSignature,
  validateLineSignature,
};
