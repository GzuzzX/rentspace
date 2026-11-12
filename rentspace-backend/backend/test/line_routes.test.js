const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const express = require('express');

const {
  LineClient,
  createLineRouter,
  generateLineSignature,
} = require('../src/line');

describe('LINE Routes Integration', () => {
  const secretKey = 'route_secret_key';
  const lineClientInstance = new LineClient({
    channelAccessToken: 'token_123',
    channelSecret: secretKey,
  });

  const app = express();
  app.use(express.json({
    verify: (req, _res, bufferChunk) => {
      req.rawBody = bufferChunk;
    },
  }));
  app.use('/api/line', createLineRouter(lineClientInstance));
  app.use((err, req, res, next) => {
    res.status(err.status || 500).json({ error: err.message });
  });

  test('GET /api/line/health reports configuration status', async () => {
    const server = app.listen(0);
    const port = server.address().port;

    try {
      const response = await fetch(`http://localhost:${port}/api/line/health`);
      assert.equal(response.status, 200);
      const body = await response.json();
      assert.equal(body.configured, true);
      assert.equal(body.endpoint, '/api/line');
    } finally {
      server.close();
    }
  });

  test('POST /api/line/webhook verifies valid signature header', async () => {
    const server = app.listen(0);
    const port = server.address().port;

    try {
      const eventPayload = { events: [{ type: 'message', message: { text: 'ping' } }] };
      const rawPayload = JSON.stringify(eventPayload);
      const signature = generateLineSignature(Buffer.from(rawPayload, 'utf8'), secretKey);

      const response = await fetch(`http://localhost:${port}/api/line/webhook`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-line-signature': signature,
        },
        body: rawPayload,
      });

      assert.equal(response.status, 200);
      const responseBody = await response.json();
      assert.equal(responseBody.received, 1);
    } finally {
      server.close();
    }
  });

  test('POST /api/line/webhook rejects invalid signature with 401', async () => {
    const server = app.listen(0);
    const port = server.address().port;

    try {
      const eventPayload = { events: [] };
      const rawPayload = JSON.stringify(eventPayload);

      const response = await fetch(`http://localhost:${port}/api/line/webhook`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-line-signature': 'invalid_signature_hash',
        },
        body: rawPayload,
      });

      assert.equal(response.status, 401);
    } finally {
      server.close();
    }
  });
});
