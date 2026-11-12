const { test, describe } = require('node:test');
const assert = require('node:assert/strict');

const {
  LineClient,
  formatTextMessage,
  createBookingFlexBubble,
  createPaymentFlexBubble,
  generateLineSignature,
  validateLineSignature,
} = require('../src/line');
const { AppError } = require('../src/utils/errors');

describe('LINE Signature Module', () => {
  const secretKey = 'test_channel_secret_key';
  const rawBodyBuffer = Buffer.from(JSON.stringify({ events: [] }), 'utf8');

  test('generates valid base64 HMAC-SHA256 signature', () => {
    const signature = generateLineSignature(rawBodyBuffer, secretKey);
    assert.equal(typeof signature, 'string');
    assert.ok(signature.length > 0);
  });

  test('validates correct signature', () => {
    const signature = generateLineSignature(rawBodyBuffer, secretKey);
    const isValid = validateLineSignature(rawBodyBuffer, signature, secretKey);
    assert.equal(isValid, true);
  });

  test('rejects tampered body buffer', () => {
    const signature = generateLineSignature(rawBodyBuffer, secretKey);
    const tamperedBuffer = Buffer.from('{"events":[{"id":"tampered"}]}', 'utf8');
    const isValid = validateLineSignature(tamperedBuffer, signature, secretKey);
    assert.equal(isValid, false);
  });

  test('rejects forged signature', () => {
    const forgedSignature = 'bad_signature_string';
    const isValid = validateLineSignature(rawBodyBuffer, forgedSignature, secretKey);
    assert.equal(isValid, false);
  });

  test('rejects empty or missing signature header', () => {
    assert.equal(validateLineSignature(rawBodyBuffer, '', secretKey), false);
    assert.equal(validateLineSignature(rawBodyBuffer, null, secretKey), false);
  });
});

describe('LINE Message Formatters', () => {
  test('formats plain text message structure', () => {
    const formatted = formatTextMessage('Hello RentSpace');
    assert.deepEqual(formatted, {
      type: 'text',
      text: 'Hello RentSpace',
    });
  });

  test('throws error for empty text message', () => {
    assert.throws(() => formatTextMessage('   '), {
      message: 'Message text must be a non-empty string',
    });
  });

  test('creates booking flex bubble message', () => {
    const flexBubble = createBookingFlexBubble({
      spaceName: 'Meeting Room A',
      bookingDate: '2026-11-20',
      statusLabel: 'Confirmed',
      totalAmount: 1500,
      bookingId: 'book-12345',
    });

    assert.equal(flexBubble.type, 'flex');
    assert.ok(flexBubble.altText.includes('Meeting Room A'));
    assert.equal(flexBubble.contents.type, 'bubble');
  });

  test('creates payment flex bubble message', () => {
    const flexBubble = createPaymentFlexBubble({
      bookingId: 'book-12345',
      amountPaid: 1500,
      paymentStatus: 'Approved',
    });

    assert.equal(flexBubble.type, 'flex');
    assert.ok(flexBubble.altText.includes('Payment'));
    assert.equal(flexBubble.contents.type, 'bubble');
  });
});

describe('LineClient API Dispatcher', () => {
  const mockToken = 'mock_line_access_token_123';
  const mockSecret = 'mock_line_channel_secret_456';

  test('detects configuration status correctly', () => {
    const unconfigured = new LineClient({ channelAccessToken: '', channelSecret: '' });
    assert.equal(unconfigured.isConfigured(), false);

    const configured = new LineClient({
      channelAccessToken: mockToken,
      channelSecret: mockSecret,
    });
    assert.equal(configured.isConfigured(), true);
  });

  test('sends push message with required authorization header', async () => {
    let capturedUrl = '';
    let capturedOptions = null;

    const mockFetch = async (url, options) => {
      capturedUrl = url;
      capturedOptions = options;
      return {
        ok: true,
        status: 200,
        headers: new Map([['content-type', 'application/json']]),
        json: async () => ({ status: 'success' }),
      };
    };

    const client = new LineClient({
      channelAccessToken: mockToken,
      channelSecret: mockSecret,
      fetchClient: mockFetch,
    });

    const pushResult = await client.pushMessage('user_line_001', 'Booking confirmed!');

    assert.equal(capturedUrl, 'https://api.line.me/v2/bot/message/push');
    assert.equal(capturedOptions.headers.Authorization, `Bearer ${mockToken}`);
    const parsedPayload = JSON.parse(capturedOptions.body);
    assert.equal(parsedPayload.to, 'user_line_001');
    assert.equal(parsedPayload.messages[0].text, 'Booking confirmed!');
    assert.deepEqual(pushResult, { status: 'success' });
  });

  test('sends reply message with replyToken', async () => {
    let capturedBody = null;

    const mockFetch = async (_url, options) => {
      capturedBody = JSON.parse(options.body);
      return {
        ok: true,
        status: 200,
        headers: new Map([['content-type', 'application/json']]),
        json: async () => ({ status: 'replied' }),
      };
    };

    const client = new LineClient({
      channelAccessToken: mockToken,
      channelSecret: mockSecret,
      fetchClient: mockFetch,
    });

    await client.replyMessage('reply_token_abc', 'Reply content');
    assert.equal(capturedBody.replyToken, 'reply_token_abc');
    assert.equal(capturedBody.messages[0].text, 'Reply content');
  });

  test('sends multicast to multiple recipients', async () => {
    let capturedBody = null;

    const mockFetch = async (_url, options) => {
      capturedBody = JSON.parse(options.body);
      return {
        ok: true,
        status: 200,
        headers: new Map(),
        text: async () => '',
      };
    };

    const client = new LineClient({
      channelAccessToken: mockToken,
      channelSecret: mockSecret,
      fetchClient: mockFetch,
    });

    await client.multicast(['user_1', 'user_2'], 'Multicast alert');
    assert.deepEqual(capturedBody.to, ['user_1', 'user_2']);
  });

  test('broadcast sends message to all followers', async () => {
    let capturedBody = null;

    const mockFetch = async (_url, options) => {
      capturedBody = JSON.parse(options.body);
      return {
        ok: true,
        status: 200,
        headers: new Map(),
        text: async () => '',
      };
    };

    const client = new LineClient({
      channelAccessToken: mockToken,
      channelSecret: mockSecret,
      fetchClient: mockFetch,
    });

    await client.broadcast('Broadcast alert');
    assert.equal(capturedBody.messages[0].text, 'Broadcast alert');
  });

  test('handles upstream LINE API failure with AppError 502', async () => {
    const mockFailingFetch = async () => ({
      ok: false,
      status: 401,
      text: async () => 'Invalid access token',
    });

    const client = new LineClient({
      channelAccessToken: 'invalid_token',
      channelSecret: mockSecret,
      fetchClient: mockFailingFetch,
    });

    await assert.rejects(
      async () => {
        await client.pushMessage('user_001', 'Test fail');
      },
      (error) => {
        assert.ok(error instanceof AppError);
        assert.equal(error.status, 502);
        assert.ok(error.message.includes('Invalid access token'));
        return true;
      }
    );
  });
});
