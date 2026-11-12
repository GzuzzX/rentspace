function formatTextMessage(textMessage) {
  if (typeof textMessage !== 'string' || textMessage.trim().length === 0) {
    throw new Error('Message text must be a non-empty string');
  }
  return {
    type: 'text',
    text: textMessage.trim(),
  };
}

function createBookingFlexBubble(bookingSummary) {
  if (!bookingSummary || typeof bookingSummary !== 'object') {
    throw new Error('bookingSummary must be an object');
  }
  const { spaceName, bookingDate, statusLabel, totalAmount, bookingId } = bookingSummary;

  return {
    type: 'flex',
    altText: `RentSpace Booking: ${spaceName || 'Reservation'}`,
    contents: {
      type: 'bubble',
      header: {
        type: 'box',
        layout: 'vertical',
        backgroundColor: '#1E293B',
        contents: [
          {
            type: 'text',
            text: 'RentSpace Notification',
            weight: 'bold',
            color: '#38BDF8',
            size: 'sm',
          },
          {
            type: 'text',
            text: spaceName || 'Booking Update',
            weight: 'bold',
            color: '#FFFFFF',
            size: 'lg',
            margin: 'md',
          },
        ],
      },
      body: {
        type: 'box',
        layout: 'vertical',
        contents: [
          {
            type: 'box',
            layout: 'horizontal',
            contents: [
              { type: 'text', text: 'Booking ID', color: '#64748B', size: 'sm' },
              { type: 'text', text: bookingId || '-', align: 'end', size: 'sm', color: '#0F172A' },
            ],
          },
          {
            type: 'box',
            layout: 'horizontal',
            margin: 'sm',
            contents: [
              { type: 'text', text: 'Date', color: '#64748B', size: 'sm' },
              { type: 'text', text: bookingDate || '-', align: 'end', size: 'sm', color: '#0F172A' },
            ],
          },
          {
            type: 'box',
            layout: 'horizontal',
            margin: 'sm',
            contents: [
              { type: 'text', text: 'Status', color: '#64748B', size: 'sm' },
              { type: 'text', text: statusLabel || 'Updated', align: 'end', weight: 'bold', size: 'sm', color: '#0284C7' },
            ],
          },
          {
            type: 'box',
            layout: 'horizontal',
            margin: 'sm',
            contents: [
              { type: 'text', text: 'Amount', color: '#64748B', size: 'sm' },
              { type: 'text', text: totalAmount ? `${totalAmount} THB` : '-', align: 'end', weight: 'bold', size: 'sm', color: '#0F172A' },
            ],
          },
        ],
      },
    },
  };
}

function createPaymentFlexBubble(paymentSummary) {
  if (!paymentSummary || typeof paymentSummary !== 'object') {
    throw new Error('paymentSummary must be an object');
  }
  const { bookingId, amountPaid, paymentStatus } = paymentSummary;

  return {
    type: 'flex',
    altText: `RentSpace Payment: ${paymentStatus || 'Status'}`,
    contents: {
      type: 'bubble',
      header: {
        type: 'box',
        layout: 'vertical',
        backgroundColor: '#0F172A',
        contents: [
          {
            type: 'text',
            text: 'Payment Confirmation',
            weight: 'bold',
            color: '#10B981',
            size: 'md',
          },
        ],
      },
      body: {
        type: 'box',
        layout: 'vertical',
        contents: [
          {
            type: 'box',
            layout: 'horizontal',
            contents: [
              { type: 'text', text: 'Booking ID', color: '#64748B', size: 'sm' },
              { type: 'text', text: bookingId || '-', align: 'end', size: 'sm' },
            ],
          },
          {
            type: 'box',
            layout: 'horizontal',
            margin: 'sm',
            contents: [
              { type: 'text', text: 'Status', color: '#64748B', size: 'sm' },
              { type: 'text', text: paymentStatus || 'Pending', align: 'end', weight: 'bold', size: 'sm' },
            ],
          },
          {
            type: 'box',
            layout: 'horizontal',
            margin: 'sm',
            contents: [
              { type: 'text', text: 'Total', color: '#64748B', size: 'sm' },
              { type: 'text', text: amountPaid ? `${amountPaid} THB` : '-', align: 'end', weight: 'bold', size: 'sm' },
            ],
          },
        ],
      },
    },
  };
}

module.exports = {
  formatTextMessage,
  createBookingFlexBubble,
  createPaymentFlexBubble,
};
