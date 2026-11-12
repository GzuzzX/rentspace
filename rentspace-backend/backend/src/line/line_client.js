const { AppError } = require('../utils/errors');
const { validateLineSignature } = require('./line_signature');
const {
  formatTextMessage,
  createBookingFlexBubble,
  createPaymentFlexBubble,
} = require('./line_formatters');

class LineClient {
  constructor(options = {}) {
    this.channelAccessToken = options.channelAccessToken || process.env.LINE_CHANNEL_ACCESS_TOKEN || '';
    this.channelSecret = options.channelSecret || process.env.LINE_CHANNEL_SECRET || '';
    this.apiBaseUrl = options.apiBaseUrl || 'https://api.line.me/v2/bot';
    this.fetchClient = options.fetchClient || globalThis.fetch;
  }

  isConfigured() {
    return Boolean(this.channelAccessToken && this.channelSecret);
  }

  verifyWebhookSignature(rawBodyBuffer, signatureHeader) {
    if (!this.channelSecret) {
      throw new AppError('LINE channel secret is not configured on server', 500);
    }
    return validateLineSignature(rawBodyBuffer, signatureHeader, this.channelSecret);
  }

  buildHeaders() {
    if (!this.channelAccessToken) {
      throw new AppError('LINE channel access token is missing', 500);
    }
    return {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${this.channelAccessToken}`,
    };
  }

  normalizeMessages(messageInput) {
    if (typeof messageInput === 'string') {
      return [formatTextMessage(messageInput)];
    }
    if (Array.isArray(messageInput)) {
      if (messageInput.length === 0) {
        throw new AppError('Message list cannot be empty', 400);
      }
      return messageInput.map((entry) =>
        typeof entry === 'string' ? formatTextMessage(entry) : entry
      );
    }
    if (typeof messageInput === 'object' && messageInput !== null) {
      return [messageInput];
    }
    throw new AppError('Invalid message input format', 400);
  }

  async sendRequest(endpointPath, bodyContent) {
    const urlEndpoint = `${this.apiBaseUrl}${endpointPath}`;
    const authHeaders = this.buildHeaders();

    const httpResponse = await this.fetchClient(urlEndpoint, {
      method: 'POST',
      headers: authHeaders,
      body: JSON.stringify(bodyContent),
    });

    if (!httpResponse.ok) {
      const errorContent = await httpResponse.text();
      throw new AppError(`LINE API request failed [${httpResponse.status}]: ${errorContent}`, 502);
    }

    const headerContentType = httpResponse.headers?.get?.('content-type') || '';
    if (headerContentType.includes('application/json')) {
      return await httpResponse.json();
    }
    return { success: true };
  }

  async pushMessage(recipientUserId, messageInput) {
    if (!recipientUserId || typeof recipientUserId !== 'string') {
      throw new AppError('Recipient LINE user ID is required', 400);
    }
    const messageList = this.normalizeMessages(messageInput);
    return await this.sendRequest('/message/push', {
      to: recipientUserId,
      messages: messageList,
    });
  }

  async replyMessage(replyToken, messageInput) {
    if (!replyToken || typeof replyToken !== 'string') {
      throw new AppError('Reply token is required', 400);
    }
    const messageList = this.normalizeMessages(messageInput);
    return await this.sendRequest('/message/reply', {
      replyToken,
      messages: messageList,
    });
  }

  async multicast(recipientList, messageInput) {
    if (!Array.isArray(recipientList) || recipientList.length === 0) {
      throw new AppError('Recipient list must contain at least one ID', 400);
    }
    const messageList = this.normalizeMessages(messageInput);
    return await this.sendRequest('/message/multicast', {
      to: recipientList,
      messages: messageList,
    });
  }

  async broadcast(messageInput) {
    const messageList = this.normalizeMessages(messageInput);
    return await this.sendRequest('/message/broadcast', {
      messages: messageList,
    });
  }

  async getProfile(userId) {
    if (!userId || typeof userId !== 'string') {
      throw new AppError('User ID is required to fetch profile', 400);
    }
    const urlEndpoint = `${this.apiBaseUrl}/profile/${encodeURIComponent(userId)}`;
    const httpResponse = await this.fetchClient(urlEndpoint, {
      method: 'GET',
      headers: this.buildHeaders(),
    });

    if (!httpResponse.ok) {
      const errorContent = await httpResponse.text();
      throw new AppError(`Failed to fetch LINE profile [${httpResponse.status}]: ${errorContent}`, 502);
    }

    return await httpResponse.json();
  }

  async notifyBooking(recipientUserId, bookingSummary) {
    const flexBubble = createBookingFlexBubble(bookingSummary);
    return await this.pushMessage(recipientUserId, flexBubble);
  }

  async notifyPayment(recipientUserId, paymentSummary) {
    const flexBubble = createPaymentFlexBubble(paymentSummary);
    return await this.pushMessage(recipientUserId, flexBubble);
  }
}

module.exports = { LineClient };
