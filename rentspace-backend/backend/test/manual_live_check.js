require('dotenv').config();
const { LineClient, generateLineSignature } = require('../src/line');

async function executeManualCheck() {
  const channelAccessToken = process.env.LINE_CHANNEL_ACCESS_TOKEN || '';
  const channelSecret = process.env.LINE_CHANNEL_SECRET || '';

  console.log('=== RentSpace LINE Client Verification ===');
  console.log(`Channel Token Configured: ${Boolean(channelAccessToken)}`);
  console.log(`Channel Secret Configured: ${Boolean(channelSecret)}`);

  const clientInstance = new LineClient({
    channelAccessToken,
    channelSecret,
  });

  const sampleBuffer = Buffer.from(JSON.stringify({ events: [] }), 'utf8');
  const generatedSignature = generateLineSignature(sampleBuffer, channelSecret || 'mock_secret');
  console.log(`Local HMAC-SHA256 Signature Generation: OK (${generatedSignature.slice(0, 10)}...)`);

  if (!clientInstance.isConfigured()) {
    console.log('\n[INFO] Real credentials missing in backend/.env.');
    console.log('Set LINE_CHANNEL_ACCESS_TOKEN and LINE_CHANNEL_SECRET to send real messages.\n');
    return;
  }

  try {
    console.log('\nContacting LINE API endpoint...');
    const botResponse = await clientInstance.sendRequest('/info', {});
    console.log('LINE Channel Connection Successful:', botResponse);
  } catch (apiFailure) {
    console.error('LINE Channel Connection Notice:', apiFailure.message);
  }
}

executeManualCheck();
