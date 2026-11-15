const { normalizeRoleForApp } = require("./auth_security");
const { DEFAULT_WEEK_HOURS } = require("./schema_bootstrap");

function toIsoDate(rawValue) {
  if (!rawValue) return "2026-11-15";
  if (rawValue instanceof Date) {
    const year = rawValue.getFullYear();
    const month = String(rawValue.getMonth() + 1).padStart(2, "0");
    const day = String(rawValue.getDate()).padStart(2, "0");
    return `${year}-${month}-${day}`;
  }
  return String(rawValue).substring(0, 10);
}

function toIsoDateTime(rawValue) {
  if (!rawValue) return null;
  if (rawValue instanceof Date) return rawValue.toISOString();
  const parsed = new Date(rawValue);
  return Number.isNaN(parsed.getTime()) ? String(rawValue) : parsed.toISOString();
}

function parseJsonOrFallback(rawText, fallback) {
  if (!rawText) return fallback;
  if (typeof rawText === "object") return rawText;
  try {
    return JSON.parse(rawText);
  } catch (_err) {
    return fallback;
  }
}

function mapUserRow(row) {
  return {
    id: String(row.user_id),
    name: row.name || row.username,
    email: row.email || "",
    role: normalizeRoleForApp(row.role),
    phone: row.phone || "",
    bank_info: row.bank_info || "",
    active: row.status !== "suspended" && row.role !== "disabled",
  };
}

function normalizeImageUrl(rawUrl) {
  if (!rawUrl) return "";
  const relative = String(rawUrl).replace(/^https?:\/\/(localhost|127\.0\.0\.1):\d+/, "");
  return relative === "/test-slip.png" ? "/uploads/test-slip.png" : relative;
}

function mapSpaceRow(row, amenityMap) {
  const defaultHours = JSON.parse(DEFAULT_WEEK_HOURS);
  const customAmenities = parseJsonOrFallback(row.amenities_json, null);
  const joinedAmenities = amenityMap.get(String(row.space_id)) || ["Wi-Fi", "เครื่องปรับอากาศ"];
  const rawStatus = row.status === "hidden" ? "rejected" : row.status || "pending";
  return {
    id: String(row.space_id),
    owner_id: String(row.owner_id),
    name: row.title || "",
    category: row.category || "ห้องประชุม",
    location: row.location || "",
    price: Math.max(1, Math.round(Number(row.price_per_day || 350))),
    capacity: Number(row.capacity || 10),
    description: row.description || "",
    image: normalizeImageUrl(row.image_url),
    amenities: Array.isArray(customAmenities) && customAmenities.length > 0 ? customAmenities : joinedAmenities,
    status: ["pending", "approved", "rejected"].includes(rawStatus) ? rawStatus : "pending",
    hours: parseJsonOrFallback(row.hours_json, defaultHours),
    avg_rating: row.rating != null ? Number(row.rating) : null,
    review_count: Number(row.rating_count || 0),
    review_reason: row.review_reason || "",
  };
}

function deriveBookingAppStatus(row) {
  if (row.app_status) return row.app_status;
  switch (row.status) {
    case "pending":
      return "ownerReview";
    case "approved":
      return row.is_paid ? "confirmed" : "paymentDue";
    case "confirmed":
      return "confirmed";
    case "completed":
      return "completed";
    case "rejected":
      return "ownerRejected";
    case "cancelled":
      return "canceled";
    default:
      return "ownerReview";
  }
}

function extractMinutes(datetimeVal, fallbackMinutes) {
  if (!datetimeVal) return fallbackMinutes;
  const dateObj = datetimeVal instanceof Date ? datetimeVal : new Date(datetimeVal);
  if (Number.isNaN(dateObj.getTime())) return fallbackMinutes;
  return dateObj.getHours() * 60 + dateObj.getMinutes();
}

function mapBookingRow(row, spaceById) {
  const space = spaceById.get(String(row.space_id));
  const startMin = row.start_minutes != null ? Number(row.start_minutes) : extractMinutes(row.start_time, 540);
  const endMin = row.end_minutes != null ? Number(row.end_minutes) : extractMinutes(row.end_time, 660);
  const safeEnd = endMin > startMin ? endMin : Math.min(1440, startMin + 60);
  const hours = Math.max(1, Math.ceil((safeEnd - startMin) / 60));
  const daysCount = Math.max(1, Number(row.days_count || 1));
  const fallbackRent = (space ? space.price : 350) * hours * daysCount;
  const rentAmount = row.total_price != null && Number(row.total_price) > 0 ? Math.round(Number(row.total_price)) : fallbackRent;
  const status = deriveBookingAppStatus(row);
  return {
    id: String(row.booking_id),
    space_id: String(row.space_id),
    owner_id: space ? space.owner_id : "1001",
    renter_id: String(row.customer_id),
    space_name: space ? space.name : `Space #${row.space_id}`,
    booking_date: toIsoDate(row.start_date),
    start_minutes: startMin,
    end_minutes: safeEnd,
    rent_amount: rentAmount,
    platform_fee: row.platform_fee != null ? Number(row.platform_fee) : Math.round(rentAmount * 0.05),
    days_count: daysCount,
    attendees: Math.max(1, Number(row.attendees || 1)),
    zone: row.zone || "โซนหลัก (พื้นที่มาตรฐาน)",
    renter_note: row.renter_note || "",
    status,
    reason: row.reason || "",
    reason_kind: row.reason_kind || "none",
    created_at: toIsoDateTime(row.created_at) || new Date().toISOString(),
    approved_at: toIsoDateTime(row.approved_at),
    slip_rejected_at: toIsoDateTime(row.slip_rejected_at),
    confirmed_at: toIsoDateTime(row.confirmed_at),
    completed_at: toIsoDateTime(row.completed_at),
    paid_out_at: toIsoDateTime(row.paid_out_at),
    payout_slip_name: row.payout_slip_name || "",
    payout_slip_url: normalizeImageUrl(row.payout_slip_url),
    payout_slip_data: row.payout_slip_data || "",
    payout_note: row.payout_note || "",
  };
}

function mapBlockRow(row) {
  const startIso = row.start_at
    ? toIsoDateTime(row.start_at)
    : `${toIsoDate(row.start_date)}T00:00:00.000Z`;
  const endIso = row.end_at
    ? toIsoDateTime(row.end_at)
    : `${toIsoDate(row.end_date)}T23:59:00.000Z`;
  return {
    id: String(row.block_id),
    space_id: String(row.space_id),
    start_at: startIso,
    end_at: endIso,
    reason: row.reason || "ปิดปรับปรุง",
  };
}

async function loadAmenityMap(db) {
  const [rows] = await db.query(
    `SELECT sa.space_id, a.name
     FROM space_amenities sa
     JOIN amenities a ON a.amenity_id = sa.amenity_id`
  );
  const map = new Map();
  for (const row of rows) {
    const key = String(row.space_id);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(row.name);
  }
  return map;
}

async function buildSnapshot(db, currentUserId) {
  const [userRows] = await db.query("SELECT * FROM users ORDER BY user_id ASC");
  const [spaceRows] = await db.query("SELECT * FROM spaces ORDER BY space_id ASC");
  const [bookingRows] = await db.query("SELECT * FROM bookings ORDER BY booking_id DESC");
  const [blockRows] = await db.query("SELECT * FROM room_blocks ORDER BY block_id ASC");
  const [paymentRows] = await db.query("SELECT * FROM payments ORDER BY payment_id ASC");
  const [reviewRows] = await db.query("SELECT * FROM reviews ORDER BY review_id DESC");
  const [favRows] = await db.query("SELECT space_id FROM user_favorites WHERE user_id = ?", [currentUserId]);
  const [issueRows] = await db.query("SELECT * FROM issues ORDER BY created_at DESC");
  const [logRows] = await db.query("SELECT * FROM admin_logs ORDER BY log_id DESC LIMIT 200");
  const amenityMap = await loadAmenityMap(db);

  const users = userRows.map(mapUserRow);
  const spaces = spaceRows.map((r) => mapSpaceRow(r, amenityMap));
  const spaceById = new Map(spaces.map((s) => [s.id, s]));
  const bookings = bookingRows.map((b) => mapBookingRow(b, spaceById));
  const bookingById = new Map(bookings.map((b) => [b.id, b]));

  const slips = paymentRows.map((p) => ({
    id: String(p.payment_id),
    booking_id: String(p.booking_id),
    file_name: p.file_name || "slip.jpg",
    image_data: p.image_data || "",
    image_url: normalizeImageUrl(p.slip_image_url),
    submitted_at: toIsoDateTime(p.paid_at || p.created_at) || new Date().toISOString(),
    note: p.note || p.transaction_ref || "",
    rejection_reason: p.rejection_reason || "",
  }));

  const reviews = reviewRows.map((r) => {
    const relatedBooking = bookingById.get(String(r.booking_id));
    return {
      id: String(r.review_id),
      booking_id: String(r.booking_id),
      space_id: relatedBooking ? relatedBooking.space_id : "2001",
      rating: Number(r.rating),
      comment: r.review_comment || "",
      created_at: toIsoDateTime(r.created_at) || new Date().toISOString(),
    };
  });

  const busy = bookings
    .filter((b) => b.status !== "ownerRejected" && b.status !== "canceled")
    .map((b) => ({
      space_id: b.space_id,
      booking_date: b.booking_date,
      start_minutes: b.start_minutes,
      end_minutes: b.end_minutes,
      days_count: b.days_count,
    }));

  return {
    userId: String(currentUserId),
    users,
    favorites: favRows.map((f) => String(f.space_id)),
    spaces,
    blocks: blockRows.map(mapBlockRow),
    bookings,
    slips,
    reviews,
    issues: issueRows.map((i) => ({
      id: String(i.id || i.issue_id),
      reporter_id: String(i.reporter_id),
      subject: i.subject,
      detail: i.detail,
      closed: Boolean(i.closed),
      resolution: i.resolution || "",
    })),
    busy,
    logs: logRows.map((l) => ({
      acted_at: toIsoDateTime(l.created_at) || new Date().toISOString(),
      actor: l.admin_name || "System",
      action: `${l.action}: ${l.details}`,
    })),
  };
}

module.exports = {
  toIsoDate,
  toIsoDateTime,
  buildSnapshot,
};
