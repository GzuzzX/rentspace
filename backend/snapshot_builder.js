const { normalizeRoleForApp } = require("./auth_security");
const { DEFAULT_WEEK_HOURS } = require("./schema_bootstrap");

const THAI_OFFSET_MS = 7 * 60 * 60 * 1000;

function buildThaiDate(year, month, day, hours = 0, minutes = 0, seconds = 0, ms = 0) {
  return new Date(Date.UTC(year, month - 1, day, hours, minutes, seconds, ms) - THAI_OFFSET_MS);
}

function getThaiDateParts(dateObj) {
  const shifted = new Date(dateObj.getTime() + THAI_OFFSET_MS);
  return {
    year: shifted.getUTCFullYear(),
    month: shifted.getUTCMonth() + 1,
    day: shifted.getUTCDate(),
    hours: shifted.getUTCHours(),
    minutes: shifted.getUTCMinutes(),
    weekdayIndex: (shifted.getUTCDay() + 6) % 7,
  };
}

function toIsoDate(rawValue) {
  if (!rawValue) return "2026-11-15";
  if (rawValue instanceof Date) {
    const parts = getThaiDateParts(rawValue);
    const monthText = String(parts.month).padStart(2, "0");
    const dayText = String(parts.day).padStart(2, "0");
    return `${parts.year}-${monthText}-${dayText}`;
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

const LEGACY_CATEGORY_MAP = {
  meeting_room: "ห้องประชุม",
  study_room: "Co-working",
  event_space: "พื้นที่อีเวนต์",
  studio: "สตูดิโอ",
};

function normalizeSpaceCategory(rawCategory) {
  const clean = String(rawCategory || "").trim();
  if (!clean) return "ห้องประชุม";
  return LEGACY_CATEGORY_MAP[clean] || clean;
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
    category: normalizeSpaceCategory(row.category),
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

const LEGACY_BOOKING_STATUS_MAP = {
  pending: "ownerReview",
  confirmed: "confirmed",
  completed: "completed",
  rejected: "ownerRejected",
  cancelled: "canceled",
};

function deriveBookingAppStatus(row) {
  if (row.app_status) return row.app_status;
  if (row.status === "approved") return row.is_paid ? "confirmed" : "paymentDue";
  return LEGACY_BOOKING_STATUS_MAP[row.status] || "ownerReview";
}

function extractNaiveWallClockMinutes(rawText) {
  if (/[zZ]|[+-]\d{2}:?\d{2}$/.test(rawText.trim())) return null;
  const clockMatch = /(?:T|\s)(\d{2}):(\d{2})/.exec(rawText);
  if (!clockMatch) return null;
  return Number(clockMatch[1]) * 60 + Number(clockMatch[2]);
}

function extractMinutes(datetimeVal, fallbackMinutes) {
  if (!datetimeVal) return fallbackMinutes;
  if (typeof datetimeVal === "string") {
    const naiveMinutes = extractNaiveWallClockMinutes(datetimeVal);
    if (naiveMinutes != null) return naiveMinutes;
  }
  const parsed = new Date(datetimeVal);
  if (Number.isNaN(parsed.getTime())) return fallbackMinutes;
  const parts = getThaiDateParts(parsed);
  return parts.hours * 60 + parts.minutes;
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
    : `${toIsoDate(row.start_date)}T00:00:00.000+07:00`;
  const endIso = row.end_at
    ? toIsoDateTime(row.end_at)
    : `${toIsoDate(row.end_date)}T23:59:00.000+07:00`;
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

function resolveReviewSpaceId(reviewRow, bookingById) {
  if (reviewRow.space_id != null) return String(reviewRow.space_id);
  const relatedBooking = bookingById.get(String(reviewRow.booking_id));
  return relatedBooking ? relatedBooking.space_id : "2001";
}

function mapSlipsAndReviews(paymentRows, reviewRows, bookingById) {
  const mappedSlips = paymentRows.map((paymentRow) => ({
    id: String(paymentRow.payment_id),
    booking_id: String(paymentRow.booking_id),
    file_name: paymentRow.file_name || "slip.jpg",
    image_data: paymentRow.image_data || "",
    image_url: normalizeImageUrl(paymentRow.slip_image_url),
    submitted_at: toIsoDateTime(paymentRow.paid_at || paymentRow.created_at) || new Date().toISOString(),
    note: paymentRow.note || paymentRow.transaction_ref || "",
    rejection_reason: paymentRow.rejection_reason || "",
  }));

  const mappedReviews = reviewRows.map((reviewRow) => ({
    id: String(reviewRow.review_id),
    booking_id: String(reviewRow.booking_id),
    space_id: resolveReviewSpaceId(reviewRow, bookingById),
    rating: Number(reviewRow.rating),
    comment: reviewRow.review_comment || "",
    created_at: toIsoDateTime(reviewRow.created_at) || new Date().toISOString(),
  }));
  return { mappedSlips, mappedReviews };
}

function collectPairedPhoneIds(viewerId, visibleBookings) {
  const pairedIds = new Set([viewerId]);
  for (const bookingRecord of visibleBookings) {
    pairedIds.add(bookingRecord.renter_id);
    pairedIds.add(bookingRecord.owner_id);
  }
  return pairedIds;
}

function redactUsersForViewer(users, viewerId, isAdmin, visibleBookings) {
  if (isAdmin) return users;
  const pairedPhoneIds = collectPairedPhoneIds(viewerId, visibleBookings);
  return users.map((userRecord) => {
    const isSelf = userRecord.id === viewerId;
    return {
      ...userRecord,
      email: isSelf ? userRecord.email : "",
      bank_info: isSelf ? userRecord.bank_info : "",
      phone: isSelf || pairedPhoneIds.has(userRecord.id) ? userRecord.phone : "",
    };
  });
}

function redactSpacesForViewer(spaces, viewerId, isAdmin, visibleBookings) {
  if (isAdmin) return spaces;
  const bookedSpaceIds = new Set(
    visibleBookings.map((bookingRecord) => bookingRecord.space_id)
  );
  return spaces
    .filter(
      (spaceRecord) =>
        spaceRecord.owner_id === viewerId ||
        spaceRecord.status === "approved" ||
        bookedSpaceIds.has(spaceRecord.id)
    )
    .map((spaceRecord) =>
      spaceRecord.owner_id === viewerId
        ? spaceRecord
        : { ...spaceRecord, review_reason: "" }
    );
}

function mapVisibleIssues(issueRows, viewerId, isAdmin) {
  return issueRows
    .filter((issueRow) => isAdmin || String(issueRow.reporter_id) === viewerId)
    .map((issueRow) => ({
      id: String(issueRow.id || issueRow.issue_id),
      reporter_id: String(issueRow.reporter_id),
      subject: issueRow.subject,
      detail: issueRow.detail,
      closed: Boolean(issueRow.closed),
      resolution: issueRow.resolution || "",
    }));
}

function buildBusySlots(bookings) {
  return bookings
    .filter((bookingRecord) => bookingRecord.status !== "ownerRejected" && bookingRecord.status !== "canceled")
    .map((bookingRecord) => ({
      space_id: bookingRecord.space_id,
      booking_date: bookingRecord.booking_date,
      start_minutes: bookingRecord.start_minutes,
      end_minutes: bookingRecord.end_minutes,
      days_count: bookingRecord.days_count,
    }));
}

async function queryAdminSnapshotRows(db) {
  const [bookingRows] = await db.query("SELECT * FROM bookings ORDER BY booking_id DESC");
  const [paymentRows] = await db.query("SELECT * FROM payments ORDER BY payment_id ASC");
  const [issueRows] = await db.query("SELECT * FROM issues ORDER BY created_at DESC");
  const [logRows] = await db.query("SELECT * FROM admin_logs ORDER BY log_id DESC LIMIT 200");
  return {
    bookingRows,
    busySourceRows: bookingRows,
    paymentRows,
    issueRows,
    logRows,
  };
}

async function queryParticipantSnapshotRows(db, currentUserId) {
  const [bookingRows] = await db.query(
    `SELECT b.* FROM bookings b
     LEFT JOIN spaces s ON s.space_id = b.space_id
     WHERE b.customer_id = ? OR s.owner_id = ?
     ORDER BY b.booking_id DESC`,
    [currentUserId, currentUserId]
  );
  const [busySourceRows] = await db.query(
    `SELECT booking_id, space_id, customer_id, start_date, start_time, end_time,
            start_minutes, end_minutes, days_count, status, is_paid, app_status
     FROM bookings
     WHERE COALESCE(NULLIF(app_status, ''), status) NOT IN ('ownerRejected', 'canceled', 'rejected', 'cancelled')
     ORDER BY booking_id DESC`
  );
  const [paymentRows] = await db.query(
    `SELECT p.* FROM payments p
     JOIN bookings b ON b.booking_id = p.booking_id
     LEFT JOIN spaces s ON s.space_id = b.space_id
     WHERE b.customer_id = ? OR s.owner_id = ?
     ORDER BY p.payment_id ASC`,
    [currentUserId, currentUserId]
  );
  const [issueRows] = await db.query(
    "SELECT * FROM issues WHERE reporter_id = ? ORDER BY created_at DESC",
    [currentUserId]
  );
  return {
    bookingRows,
    busySourceRows,
    paymentRows,
    issueRows,
    logRows: [],
  };
}

function filterParticipantScope(bookings, mappedSlips, viewerId, isAdmin) {
  if (isAdmin) {
    return { visibleBookings: bookings, slips: mappedSlips };
  }
  const visibleBookings = bookings.filter(
    (bookingRecord) => bookingRecord.renter_id === viewerId || bookingRecord.owner_id === viewerId
  );
  const visibleBookingIds = new Set(visibleBookings.map((bookingRecord) => bookingRecord.id));
  const slips = mappedSlips.filter((slip) => visibleBookingIds.has(slip.booking_id));
  return { visibleBookings, slips };
}

function mapAdminLogEntries(logRows, isAdmin) {
  if (!isAdmin) return [];
  return logRows.map((logEntry) => ({
    acted_at: toIsoDateTime(logEntry.created_at) || new Date().toISOString(),
    actor: logEntry.admin_name || "System",
    action: `${logEntry.action}: ${logEntry.details}`,
  }));
}

async function buildSnapshot(db, currentUserId) {
  const [userRows] = await db.query("SELECT * FROM users ORDER BY user_id ASC");
  const [spaceRows] = await db.query("SELECT * FROM spaces ORDER BY space_id ASC");
  const [blockRows] = await db.query("SELECT * FROM room_blocks ORDER BY block_id ASC");
  const [reviewRows] = await db.query(
    "SELECT r.*, b.space_id FROM reviews r LEFT JOIN bookings b ON b.booking_id = r.booking_id ORDER BY r.review_id DESC"
  );
  const [favRows] = await db.query("SELECT space_id FROM user_favorites WHERE user_id = ?", [currentUserId]);
  const amenityMap = await loadAmenityMap(db);

  const viewerId = String(currentUserId);
  const users = userRows.map(mapUserRow);
  const viewer = users.find((candidate) => candidate.id === viewerId);
  const isAdmin = Boolean(viewer && viewer.role === "admin");

  const scopedRows = isAdmin
    ? await queryAdminSnapshotRows(db)
    : await queryParticipantSnapshotRows(db, currentUserId);

  const spaces = spaceRows.map((spaceRow) => mapSpaceRow(spaceRow, amenityMap));
  const spaceById = new Map(spaces.map((spaceRecord) => [spaceRecord.id, spaceRecord]));
  const bookings = scopedRows.bookingRows.map((bookingRow) => mapBookingRow(bookingRow, spaceById));
  const bookingById = new Map(bookings.map((bookingRecord) => [bookingRecord.id, bookingRecord]));
  const busySourceBookings = isAdmin
    ? bookings
    : scopedRows.busySourceRows.map((bookingRow) => mapBookingRow(bookingRow, spaceById));
  const { mappedSlips, mappedReviews } = mapSlipsAndReviews(
    scopedRows.paymentRows,
    reviewRows,
    bookingById
  );
  const { visibleBookings, slips } = filterParticipantScope(bookings, mappedSlips, viewerId, isAdmin);

  return {
    userId: viewerId,
    users: redactUsersForViewer(users, viewerId, isAdmin, visibleBookings),
    favorites: favRows.map((favoriteRow) => String(favoriteRow.space_id)),
    spaces: redactSpacesForViewer(spaces, viewerId, isAdmin, visibleBookings),
    blocks: blockRows.map(mapBlockRow),
    bookings: visibleBookings,
    slips,
    reviews: mappedReviews,
    issues: mapVisibleIssues(scopedRows.issueRows, viewerId, isAdmin),
    busy: buildBusySlots(busySourceBookings),
    logs: mapAdminLogEntries(scopedRows.logRows, isAdmin),
  };
}

module.exports = {
  THAI_OFFSET_MS,
  buildThaiDate,
  getThaiDateParts,
  extractMinutes,
  normalizeSpaceCategory,
  toIsoDate,
  toIsoDateTime,
  deriveBookingAppStatus,
  buildSnapshot,
};
