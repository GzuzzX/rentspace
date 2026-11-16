const { DEFAULT_WEEK_HOURS } = require("./schema_bootstrap");
const { toIsoDate, deriveBookingAppStatus } = require("./snapshot_builder");

function parseValidIsoDate(rawDate) {
  const clean = String(rawDate || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(clean)) return null;
  const [year, month, day] = clean.split("-").map(Number);
  const parsed = new Date(year, month - 1, day);
  if (
    parsed.getFullYear() !== year ||
    parsed.getMonth() !== month - 1 ||
    parsed.getDate() !== day
  ) {
    return null;
  }
  return { year, month, day, dateStr: clean };
}

function shiftIsoDate(dateStr, offsetDays) {
  const [year, month, day] = dateStr.split("-").map(Number);
  const shifted = new Date(year, month - 1, day + offsetDays);
  const yyyy = shifted.getFullYear();
  const mm = String(shifted.getMonth() + 1).padStart(2, "0");
  const dd = String(shifted.getDate()).padStart(2, "0");
  return `${yyyy}-${mm}-${dd}`;
}

function validateTimeBounds(startMinutes, endMinutes, dateSpec) {
  const isIntRange = Number.isInteger(startMinutes) && Number.isInteger(endMinutes);
  if (!isIntRange || startMinutes < 0 || endMinutes > 1440 || endMinutes <= startMinutes) {
    return "เวลาสิ้นสุดต้องอยู่หลังเวลาเริ่ม";
  }
  const duration = endMinutes - startMinutes;
  if (duration < 60 || duration > 720) {
    return "ระยะเวลาจองต้องอยู่ระหว่าง 60 นาทีถึง 12 ชั่วโมง";
  }
  const startAt = new Date(
    dateSpec.year,
    dateSpec.month - 1,
    dateSpec.day,
    Math.floor(startMinutes / 60),
    startMinutes % 60
  );
  if (startAt.getTime() <= Date.now()) {
    return "ต้องเลือกเวลาในอนาคต";
  }
  return null;
}

function parseBookingInput(requestBody) {
  const spaceId = Number(requestBody.spaceId || requestBody.space_id);
  const dateSpec = parseValidIsoDate(String(requestBody.date || requestBody.start_date || "").substring(0, 10));
  const days = requestBody.days != null ? Number(requestBody.days) : 1;
  const startMinutes = requestBody.startMinutes != null ? Number(requestBody.startMinutes) : 540;
  const endMinutes = requestBody.endMinutes != null ? Number(requestBody.endMinutes) : 660;
  const attendees = requestBody.attendees != null ? Number(requestBody.attendees) : 1;
  const zone = String(requestBody.zone || "โซนหลัก (พื้นที่มาตรฐาน)").trim() || "โซนหลัก (พื้นที่มาตรฐาน)";
  const renterNote = String(requestBody.renterNote || "").trim();

  if (!Number.isInteger(spaceId) || spaceId <= 0 || !dateSpec) {
    return { error: "ข้อมูลพื้นที่หรือวันที่จองไม่ถูกต้อง" };
  }
  if (!Number.isInteger(days) || days < 1 || days > 14 || !Number.isInteger(attendees) || attendees < 1) {
    return { error: "จำนวนวันหรือผู้เข้าใช้งานไม่ถูกต้อง" };
  }
  const timeError = validateTimeBounds(startMinutes, endMinutes, dateSpec);
  if (timeError) return { error: timeError };
  return {
    bookingInput: { spaceId, dateSpec, days, startMinutes, endMinutes, attendees, zone, renterNote },
  };
}

function parseHoursList(rawHours) {
  if (Array.isArray(rawHours) && rawHours.length === 7) return rawHours;
  if (typeof rawHours === "string") {
    try {
      const parsed = JSON.parse(rawHours);
      if (Array.isArray(parsed) && parsed.length === 7) return parsed;
    } catch (_parseErr) {
      return JSON.parse(DEFAULT_WEEK_HOURS);
    }
  }
  return JSON.parse(DEFAULT_WEEK_HOURS);
}

function resolveBlockWindowMs(blockRow) {
  if (blockRow.start_at && blockRow.end_at) {
    return {
      startMs: new Date(blockRow.start_at).getTime(),
      endMs: new Date(blockRow.end_at).getTime(),
    };
  }
  const startIso = toIsoDate(blockRow.start_date);
  const endIso = toIsoDate(blockRow.end_date);
  const [sy, sm, sd] = startIso.split("-").map(Number);
  const [ey, em, ed] = endIso.split("-").map(Number);
  return {
    startMs: new Date(sy, sm - 1, sd, 0, 0, 0, 0).getTime(),
    endMs: new Date(ey, em - 1, ed, 23, 59, 59, 999).getTime(),
  };
}

function hasBlockConflict(blocks, slotStartMs, slotEndMs) {
  return blocks.some((blockRow) => {
    const windowMs = resolveBlockWindowMs(blockRow);
    return slotStartMs < windowMs.endMs && slotEndMs > windowMs.startMs;
  });
}

function isSpaceAvailableOnDays(hoursList, blocks, bookingInput) {
  const { dateSpec, days, startMinutes, endMinutes } = bookingInput;
  for (let offset = 0; offset < days; offset += 1) {
    const dayDate = new Date(dateSpec.year, dateSpec.month - 1, dateSpec.day + offset);
    const dayHours = hoursList[(dayDate.getDay() + 6) % 7];
    if (!dayHours || !dayHours.open || startMinutes < Number(dayHours.start) || endMinutes > Number(dayHours.end)) {
      return false;
    }
    const slotStartMs = new Date(
      dayDate.getFullYear(),
      dayDate.getMonth(),
      dayDate.getDate(),
      Math.floor(startMinutes / 60),
      startMinutes % 60
    ).getTime();
    const slotEndMs = new Date(
      dayDate.getFullYear(),
      dayDate.getMonth(),
      dayDate.getDate(),
      Math.floor(endMinutes / 60),
      endMinutes % 60
    ).getTime();
    if (hasBlockConflict(blocks, slotStartMs, slotEndMs)) return false;
  }
  return true;
}

function hasBookingOverlap(bookingRows, bookingInput, endDate) {
  for (const bookingRow of bookingRows) {
    const status = deriveBookingAppStatus(bookingRow);
    if (status === "ownerRejected" || status === "canceled") continue;
    const first = toIsoDate(bookingRow.start_date);
    const last = shiftIsoDate(first, Math.max(1, Number(bookingRow.days_count || 1)) - 1);
    const existingStart = bookingRow.start_minutes != null ? Number(bookingRow.start_minutes) : 540;
    const existingEnd = bookingRow.end_minutes != null ? Number(bookingRow.end_minutes) : 660;
    const dateOverlap = bookingInput.dateSpec.dateStr <= last && endDate >= first;
    const timeOverlap = existingStart < bookingInput.endMinutes && existingEnd > bookingInput.startMinutes;
    if (dateOverlap && timeOverlap) return true;
  }
  return false;
}

function formatClockTimestamp(dateStr, minutes) {
  const hh = String(Math.floor(minutes / 60)).padStart(2, "0");
  const mm = String(minutes % 60).padStart(2, "0");
  return `${dateStr} ${hh}:${mm}:00`;
}

async function lockBookableSpace(connection, bookingInput) {
  const [spaceRows] = await connection.query(
    `SELECT s.*, u.status AS owner_status, u.role AS owner_role
     FROM spaces s JOIN users u ON u.user_id = s.owner_id
     WHERE s.space_id = ? FOR UPDATE`,
    [bookingInput.spaceId]
  );
  if (spaceRows.length === 0) return { failure: { status: 404, body: { error: "ไม่พบพื้นที่" } } };
  const spaceRow = spaceRows[0];
  if (spaceRow.status !== "approved" || spaceRow.owner_status === "suspended" || spaceRow.owner_role === "disabled") {
    return { failure: { status: 409, body: { error: "พื้นที่นี้ยังไม่เปิดรับจอง" } } };
  }
  const maxCapacity = Math.max(1, Number(spaceRow.capacity || 10));
  if (bookingInput.attendees > maxCapacity) {
    return { failure: { status: 400, body: { error: `จำนวนผู้เข้าใช้งานต้องอยู่ระหว่าง 1–${maxCapacity} ท่าน` } } };
  }
  return { spaceRow };
}

async function executeBookingTransaction(connection, userId, bookingInput) {
  const spaceCheck = await lockBookableSpace(connection, bookingInput);
  if (spaceCheck.failure) return spaceCheck.failure;

  const spaceRow = spaceCheck.spaceRow;
  const [blocks] = await connection.query("SELECT * FROM room_blocks WHERE space_id = ? FOR UPDATE", [bookingInput.spaceId]);
  const hoursList = parseHoursList(spaceRow.hours_json);
  if (!isSpaceAvailableOnDays(hoursList, blocks, bookingInput)) {
    return { status: 409, body: { error: "อยู่นอกเวลาเปิดหรือเป็นช่วงปิด" } };
  }
  const endDate = shiftIsoDate(bookingInput.dateSpec.dateStr, bookingInput.days - 1);
  const [existingRows] = await connection.query(
    "SELECT booking_id, start_date, start_minutes, end_minutes, days_count, status, app_status FROM bookings WHERE space_id = ? FOR UPDATE",
    [bookingInput.spaceId]
  );
  if (hasBookingOverlap(existingRows, bookingInput, endDate)) {
    return { status: 409, body: { error: "ช่วงเวลานี้มีการจองแล้ว" } };
  }
  const hours = Math.max(1, Math.ceil((bookingInput.endMinutes - bookingInput.startMinutes) / 60));
  const totalPrice = Math.round(Number(spaceRow.price_per_day || 350)) * hours * bookingInput.days;
  const platformFee = Math.round(totalPrice * 0.05);
  const [inserted] = await connection.query(
    `INSERT INTO bookings (space_id, customer_id, start_date, end_date, start_time, end_time, total_price, status, is_paid, start_minutes, end_minutes, days_count, attendees, zone, renter_note, platform_fee, app_status)
     VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?, ?, ?, 'ownerReview')`,
    [
      bookingInput.spaceId,
      userId,
      bookingInput.dateSpec.dateStr,
      endDate,
      formatClockTimestamp(bookingInput.dateSpec.dateStr, bookingInput.startMinutes),
      formatClockTimestamp(endDate, bookingInput.endMinutes),
      totalPrice,
      bookingInput.startMinutes,
      bookingInput.endMinutes,
      bookingInput.days,
      bookingInput.attendees,
      bookingInput.zone,
      bookingInput.renterNote,
      platformFee,
    ]
  );
  await connection.commit();
  return { status: 201, body: { id: String(inserted.insertId), booking_id: inserted.insertId }, committed: true };
}

async function createBookingTransactional(db, userId, requestBody) {
  const parsed = parseBookingInput(requestBody || {});
  if (parsed.error) return { status: 400, body: { error: parsed.error } };
  const connection = await db.getConnection();
  let committed = false;
  try {
    await connection.beginTransaction();
    const outcome = await executeBookingTransaction(connection, userId, parsed.bookingInput);
    committed = Boolean(outcome.committed);
    return { status: outcome.status, body: outcome.body };
  } finally {
    if (!committed) {
      await connection.rollback().catch((rollbackErr) => {
        console.warn("Booking rollback warning:", rollbackErr.message);
      });
    }
    connection.release();
  }
}

function safeGuardError(err) {
  console.error("Booking guard error:", err && (err.message || err.code || String(err)));
  return "เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์";
}

function computeBookingEndsAt(bookingRecord) {
  const startIso = toIsoDate(bookingRecord.start_date);
  const daysCount = Math.max(1, Number(bookingRecord.days_count || 1));
  const endIso = bookingRecord.end_date
    ? toIsoDate(bookingRecord.end_date)
    : shiftIsoDate(startIso, daysCount - 1);
  const [ey, em, ed] = endIso.split("-").map(Number);
  let fallbackEndMinutes = 660;
  if (bookingRecord.end_time) {
    const parsedEnd =
      bookingRecord.end_time instanceof Date
        ? bookingRecord.end_time
        : new Date(bookingRecord.end_time);
    if (!Number.isNaN(parsedEnd.getTime())) {
      fallbackEndMinutes = parsedEnd.getHours() * 60 + parsedEnd.getMinutes();
    }
  }
  const endMinutes =
    bookingRecord.end_minutes != null ? Number(bookingRecord.end_minutes) : fallbackEndMinutes;
  return new Date(ey, em - 1, ed, Math.floor(endMinutes / 60), endMinutes % 60, 0, 0);
}

function guardSpaceAccess(db) {
  return async (req, res, next) => {
    try {
      const [rows] = await db.query("SELECT * FROM spaces WHERE space_id = ? LIMIT 1", [req.params.id]);
      if (rows.length === 0) {
        return res.status(404).json({ error: "ไม่พบพื้นที่" });
      }
      const spaceRecord = rows[0];
      const isAllowed = req.user.role === "admin" || Number(spaceRecord.owner_id) === Number(req.user.id);
      if (!isAllowed) {
        return res.status(403).json({ error: "ไม่มีสิทธิ์จัดการพื้นที่นี้" });
      }
      req.spaceRecord = spaceRecord;
      return next();
    } catch (err) {
      return res.status(500).json({ error: safeGuardError(err) });
    }
  };
}

function hasBookingPermission(user, bookingRecord, accessMode) {
  if (user.role === "admin" && accessMode !== "renter") return true;
  const userId = Number(user.id);
  const isRenter = Number(bookingRecord.customer_id) === userId;
  const isOwner = Number(bookingRecord.space_owner_id) === userId;
  switch (accessMode) {
    case "admin":
      return user.role === "admin";
    case "ownerOrAdmin":
      return isOwner;
    case "renter":
      return isRenter;
    case "participantOrAdmin":
      return isRenter || isOwner;
    default:
      return false;
  }
}

function guardBookingAccess(db, options) {
  return async (req, res, next) => {
    try {
      const [rows] = await db.query(
        `SELECT b.*, s.owner_id AS space_owner_id
         FROM bookings b LEFT JOIN spaces s ON s.space_id = b.space_id
         WHERE b.booking_id = ? LIMIT 1`,
        [req.params.id]
      );
      if (rows.length === 0) {
        return res.status(404).json({ error: "ไม่พบรายการจอง" });
      }
      const bookingRecord = rows[0];
      if (!hasBookingPermission(req.user, bookingRecord, options.access)) {
        return res.status(403).json({ error: "ไม่มีสิทธิ์ทำรายการกับการจองนี้" });
      }
      const validStatuses =
        req.user.role === "admin" && options.adminStatuses
          ? options.adminStatuses
          : options.allowedStatuses;
      const currentStatus = deriveBookingAppStatus(bookingRecord);
      if (validStatuses && !validStatuses.includes(currentStatus)) {
        return res.status(409).json({ error: "สถานะการจองไม่รองรับการทำรายการนี้" });
      }
      req.bookingRecord = bookingRecord;
      return next();
    } catch (err) {
      return res.status(500).json({ error: safeGuardError(err) });
    }
  };
}

module.exports = {
  createBookingTransactional,
  computeBookingEndsAt,
  hasBookingPermission,
  guardSpaceAccess,
  guardBookingAccess,
};
