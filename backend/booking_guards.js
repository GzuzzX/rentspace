const fs = require("node:fs");
const path = require("node:path");
const { DEFAULT_WEEK_HOURS } = require("./schema_bootstrap");
const {
  toIsoDate,
  deriveBookingAppStatus,
  buildThaiDate,
  getThaiDateParts,
  extractMinutes,
} = require("./snapshot_builder");

const LIFECYCLE_WINDOW_MS = 24 * 60 * 60 * 1000;

function parseValidIsoDate(rawDate) {
  const clean = String(rawDate || "").trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(clean)) return null;
  const [year, month, day] = clean.split("-").map(Number);
  const parsed = new Date(Date.UTC(year, month - 1, day));
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return { year, month, day, dateStr: clean };
}

function shiftIsoDate(dateStr, offsetDays) {
  const [year, month, day] = dateStr.split("-").map(Number);
  const shifted = new Date(Date.UTC(year, month - 1, day + offsetDays));
  const yyyy = shifted.getUTCFullYear();
  const mm = String(shifted.getUTCMonth() + 1).padStart(2, "0");
  const dd = String(shifted.getUTCDate()).padStart(2, "0");
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
  const startAt = buildThaiDate(
    dateSpec.year,
    dateSpec.month,
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
    startMs: buildThaiDate(sy, sm, sd, 0, 0, 0, 0).getTime(),
    endMs: buildThaiDate(ey, em, ed, 23, 59, 59, 999).getTime(),
  };
}

function hasBlockConflict(blocks, slotStartMs, slotEndMs) {
  return blocks.some((blockRow) => {
    const windowMs = resolveBlockWindowMs(blockRow);
    return slotStartMs < windowMs.endMs && slotEndMs > windowMs.startMs;
  });
}

function toThaiSlotMs(dayParts, minutes) {
  return buildThaiDate(
    dayParts.year,
    dayParts.month,
    dayParts.day,
    Math.floor(minutes / 60),
    minutes % 60
  ).getTime();
}

function isSpaceAvailableOnDays(hoursList, blocks, bookingInput) {
  const { dateSpec, days, startMinutes, endMinutes } = bookingInput;
  for (let offset = 0; offset < days; offset += 1) {
    const dayParts = getThaiDateParts(
      buildThaiDate(dateSpec.year, dateSpec.month, dateSpec.day + offset, 12, 0)
    );
    const dayHours = hoursList[dayParts.weekdayIndex];
    if (!dayHours || !dayHours.open || startMinutes < Number(dayHours.start) || endMinutes > Number(dayHours.end)) {
      return false;
    }
    const slotStartMs = toThaiSlotMs(dayParts, startMinutes);
    const slotEndMs = toThaiSlotMs(dayParts, endMinutes);
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
  const dayCarry = Math.floor(minutes / 1440);
  const targetDate = dayCarry > 0 ? shiftIsoDate(dateStr, dayCarry) : dateStr;
  const clockMinutes = ((minutes % 1440) + 1440) % 1440;
  const hh = String(Math.floor(clockMinutes / 60)).padStart(2, "0");
  const mm = String(clockMinutes % 60).padStart(2, "0");
  return `${targetDate} ${hh}:${mm}:00`;
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
  await sweepExpiredBookings(connection, new Date(), bookingInput.spaceId);
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

async function withTransaction(db, rollbackLabel, runTransaction, hooks = {}) {
  const connection = await db.getConnection();
  let outcome = null;
  try {
    await connection.beginTransaction();
    outcome = await runTransaction(connection);
    return outcome;
  } finally {
    if (!outcome || !outcome.committed) {
      if (hooks.onRollback) hooks.onRollback(outcome);
      await connection.rollback().catch((rollbackErr) => {
        console.warn(`${rollbackLabel} rollback warning:`, rollbackErr.message);
      });
    } else if (hooks.onCommit) {
      hooks.onCommit(outcome);
    }
    connection.release();
  }
}

async function createBookingTransactional(db, userId, requestBody) {
  const parsed = parseBookingInput(requestBody || {});
  if (parsed.error) return { status: 400, body: { error: parsed.error } };
  const outcome = await withTransaction(db, "Booking", (connection) =>
    executeBookingTransaction(connection, userId, parsed.bookingInput)
  );
  return { status: outcome.status, body: outcome.body };
}

function safeGuardError(err) {
  console.error("Booking guard error:", err && (err.message || err.code || String(err)));
  return "เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์";
}

function computeBookingStartsAt(bookingRecord) {
  const startIso = toIsoDate(bookingRecord.start_date);
  const [sy, sm, sd] = startIso.split("-").map(Number);
  const fallbackStartMinutes = extractMinutes(bookingRecord.start_time, 540);
  const startMinutes =
    bookingRecord.start_minutes != null ? Number(bookingRecord.start_minutes) : fallbackStartMinutes;
  return buildThaiDate(sy, sm, sd, Math.floor(startMinutes / 60), startMinutes % 60, 0, 0);
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
    const rawMinutes = extractMinutes(bookingRecord.end_time, -1);
    if (rawMinutes >= 0) {
      fallbackEndMinutes = rawMinutes === 0 ? 1440 : rawMinutes;
    }
  }
  const endMinutes =
    bookingRecord.end_minutes != null ? Number(bookingRecord.end_minutes) : fallbackEndMinutes;
  return buildThaiDate(ey, em, ed, Math.floor(endMinutes / 60), endMinutes % 60, 0, 0);
}

function parseTimestampMs(rawTimestamp) {
  if (!rawTimestamp) return null;
  const parsed = rawTimestamp instanceof Date ? rawTimestamp : new Date(rawTimestamp);
  const millis = parsed.getTime();
  return Number.isNaN(millis) ? null : millis;
}

function resolveExpiryAnchorMs(bookingRecord, currentStatus) {
  if (currentStatus === "ownerReview") return parseTimestampMs(bookingRecord.created_at);
  if (currentStatus === "paymentDue") return parseTimestampMs(bookingRecord.approved_at);
  if (currentStatus === "slipRejected") return parseTimestampMs(bookingRecord.slip_rejected_at);
  return null;
}

function evaluateBookingLifecycleTransition(bookingRecord, nowDate = new Date()) {
  const currentStatus = deriveBookingAppStatus(bookingRecord);
  const nowMs = nowDate.getTime();
  if (currentStatus === "confirmed") {
    const autoCompleteMs = computeBookingEndsAt(bookingRecord).getTime() + LIFECYCLE_WINDOW_MS;
    if (nowMs < autoCompleteMs) return null;
    return { nextDbStatus: "completed", nextAppStatus: "completed", reason: "", reasonKind: "none" };
  }
  const anchorMs = resolveExpiryAnchorMs(bookingRecord, currentStatus);
  if (anchorMs == null) return null;
  const deadlineMs = Math.min(anchorMs + LIFECYCLE_WINDOW_MS, computeBookingStartsAt(bookingRecord).getTime());
  if (nowMs < deadlineMs) return null;
  return {
    nextDbStatus: "cancelled",
    nextAppStatus: "canceled",
    reason: "หมดเวลาดำเนินการภายใน 24 ชั่วโมง",
    reasonKind: "expiredBySystem",
  };
}

async function applyLifecycleTransition(db, bookingId, transition) {
  if (transition.nextDbStatus === "completed") {
    await db.query(
      `UPDATE bookings
       SET status = 'completed', app_status = 'completed', completed_at = COALESCE(completed_at, NOW())
       WHERE booking_id = ? AND status = 'confirmed'`,
      [bookingId]
    );
    return;
  }
  await db.query(
    `UPDATE bookings
     SET status = 'cancelled', app_status = 'canceled', reason = ?, reason_kind = ?
     WHERE booking_id = ? AND status IN ('pending', 'approved')`,
    [transition.reason, transition.reasonKind, bookingId]
  );
}

async function sweepExpiredBookings(db, nowDate = new Date(), spaceId = null) {
  const queryText = spaceId != null
    ? "SELECT * FROM bookings WHERE space_id = ? AND status IN ('pending', 'approved', 'confirmed') FOR UPDATE"
    : "SELECT * FROM bookings WHERE status IN ('pending', 'approved', 'confirmed')";
  const queryParams = spaceId != null ? [spaceId] : [];
  const [candidateRows] = await db.query(queryText, queryParams);
  let updatedCount = 0;
  for (const bookingRow of candidateRows) {
    const transition = evaluateBookingLifecycleTransition(bookingRow, nowDate);
    if (!transition) continue;
    await applyLifecycleTransition(db, bookingRow.booking_id, transition);
    updatedCount += 1;
  }
  return updatedCount;
}

async function resolveActiveBookingStatus(db, bookingRecord) {
  const transition = evaluateBookingLifecycleTransition(bookingRecord);
  if (transition && transition.nextAppStatus === "canceled") {
    await applyLifecycleTransition(db, bookingRecord.booking_id, transition);
    bookingRecord.status = transition.nextDbStatus;
    bookingRecord.app_status = transition.nextAppStatus;
    bookingRecord.reason = transition.reason;
    bookingRecord.reason_kind = transition.reasonKind;
    return transition.nextAppStatus;
  }
  return deriveBookingAppStatus(bookingRecord);
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
  if (accessMode === "admin") return user.role === "admin";
  if (accessMode === "ownerOrAdmin") return isOwner;
  if (accessMode === "renter") return isRenter;
  return accessMode === "participantOrAdmin" && (isRenter || isOwner);
}

async function fetchBookingWithOwner(db, bookingId) {
  const [rows] = await db.query(
    `SELECT b.*, s.owner_id AS space_owner_id
     FROM bookings b LEFT JOIN spaces s ON s.space_id = b.space_id
     WHERE b.booking_id = ? LIMIT 1`,
    [bookingId]
  );
  return rows[0] || null;
}

function guardBookingAccess(db, options) {
  return async (req, res, next) => {
    try {
      const bookingRecord = await fetchBookingWithOwner(db, req.params.id);
      if (!bookingRecord) {
        return res.status(404).json({ error: "ไม่พบรายการจอง" });
      }
      if (!hasBookingPermission(req.user, bookingRecord, options.access)) {
        return res.status(403).json({ error: "ไม่มีสิทธิ์ทำรายการกับการจองนี้" });
      }
      const validStatuses =
        req.user.role === "admin" && options.adminStatuses
          ? options.adminStatuses
          : options.allowedStatuses;
      const currentStatus = await resolveActiveBookingStatus(db, bookingRecord);
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

function decodeUploadPath(rawPath) {
  try {
    return decodeURIComponent(String(rawPath || ""));
  } catch (_decodeErr) {
    return null;
  }
}

function resolveSlipAccessSpec(requestPath) {
  const decodedPath = decodeUploadPath(requestPath);
  if (decodedPath === null) return { invalid: true };
  const fileName = path.basename(decodedPath);
  if (!/^(slip|payout)_/i.test(fileName)) return null;
  const match = /^(slip|payout)_(\d+)_[A-Za-z0-9._-]+$/i.exec(fileName);
  if (!match) return { invalid: true };
  const accessMode =
    match[1].toLowerCase() === "payout" ? "ownerOrAdmin" : "participantOrAdmin";
  return { bookingId: match[2], accessMode };
}

async function authorizeSlipBooking(db, accessSpec, request, response, nextFn) {
  try {
    const bookingRecord = await fetchBookingWithOwner(db, accessSpec.bookingId);
    if (!bookingRecord) {
      return response.status(404).json({ error: "ไม่พบรายการจอง" });
    }
    if (!hasBookingPermission(request.user, bookingRecord, accessSpec.accessMode)) {
      return response.status(403).json({ error: "ไม่มีสิทธิ์เข้าถึงไฟล์สลิปนี้" });
    }
    return nextFn();
  } catch (err) {
    return response.status(500).json({ error: safeGuardError(err) });
  }
}

function guardSlipUploadAccess(db, authMiddleware) {
  return (request, response, nextFn) => {
    const accessSpec = resolveSlipAccessSpec(request.path);
    if (!accessSpec) return nextFn();
    if (accessSpec.invalid) {
      return response.status(403).json({ error: "ไม่มีสิทธิ์เข้าถึงไฟล์สลิปนี้" });
    }
    if (request.user) {
      return authorizeSlipBooking(db, accessSpec, request, response, nextFn);
    }
    return authMiddleware(request, response, () => {
      void authorizeSlipBooking(db, accessSpec, request, response, nextFn);
    });
  };
}

function removeUploadedFileSafe(filePath, fileOps = fs) {
  if (!filePath || !fileOps.existsSync(filePath)) return;
  try {
    fileOps.unlinkSync(filePath);
  } catch (unlinkErr) {
    console.warn("Slip cleanup warning:", unlinkErr.message);
  }
}

async function executeSlipTransaction(connection, slipSpec, fileOps) {
  fileOps.writeFileSync(slipSpec.storedFilePath, slipSpec.fileBuffer);
  await connection.query(
    `INSERT INTO payments (booking_id, amount, payment_method, status, transaction_ref, slip_image_url, paid_at, file_name, note, image_data)
     VALUES (?, ?, 'bank_transfer', 'submitted', ?, ?, NOW(), ?, ?, ?)`,
    [
      slipSpec.bookingId,
      slipSpec.amount,
      `SLIP-${slipSpec.bookingId}`,
      slipSpec.imageUrl,
      slipSpec.originalFileName,
      slipSpec.note,
      slipSpec.base64Content,
    ]
  );
  const [updateOutcome] = await connection.query(
    "UPDATE bookings SET app_status = 'slipReview', slip_image_url = ? WHERE booking_id = ? AND app_status IN ('paymentDue', 'slipRejected')",
    [slipSpec.imageUrl, slipSpec.bookingId]
  );
  if (!updateOutcome || updateOutcome.affectedRows === 0) {
    return {
      status: 409,
      body: { error: "สถานะการจองไม่รองรับการทำรายการนี้" },
      committed: false,
    };
  }
  await connection.commit();
  return {
    status: 201,
    body: { ok: true, image_url: slipSpec.imageUrl },
    committed: true,
  };
}

async function submitPaymentSlipTransactional(db, slipSpec, fileOps = fs) {
  const outcome = await withTransaction(
    db,
    "Slip",
    (connection) => executeSlipTransaction(connection, slipSpec, fileOps),
    { onRollback: () => removeUploadedFileSafe(slipSpec.storedFilePath, fileOps) }
  );
  return { status: outcome.status, body: outcome.body };
}

async function applyGuardedBookingUpdate(db, sqlText, queryParams) {
  const [updateOutcome] = await db.query(sqlText, queryParams);
  if (!updateOutcome || updateOutcome.affectedRows === 0) {
    return {
      status: 409,
      body: { error: "สถานะการจองไม่รองรับการทำรายการนี้" },
    };
  }
  return { status: 200, body: { ok: true } };
}

function buildSlipReviewQueries(reviewSpec) {
  if (reviewSpec.approve) {
    return {
      bookingSql:
        "UPDATE bookings SET status = 'confirmed', app_status = 'confirmed', is_paid = 1, confirmed_at = NOW(), reason = '', reason_kind = 'none' WHERE booking_id = ? AND app_status = 'slipReview'",
      bookingParams: [reviewSpec.bookingId],
      paymentSql:
        "UPDATE payments SET status = 'verified' WHERE booking_id = ? ORDER BY payment_id DESC LIMIT 1",
      paymentParams: [reviewSpec.bookingId],
    };
  }
  return {
    bookingSql:
      "UPDATE bookings SET app_status = 'slipRejected', slip_rejected_at = NOW(), reason = ?, reason_kind = 'slipRejected' WHERE booking_id = ? AND app_status = 'slipReview'",
    bookingParams: [reviewSpec.reason, reviewSpec.bookingId],
    paymentSql:
      "UPDATE payments SET status = 'rejected', rejection_reason = ? WHERE booking_id = ? ORDER BY payment_id DESC LIMIT 1",
    paymentParams: [reviewSpec.reason, reviewSpec.bookingId],
  };
}

async function executeSlipReviewTransaction(connection, reviewSpec) {
  const queries = buildSlipReviewQueries(reviewSpec);
  const [bookingOutcome] = await connection.query(queries.bookingSql, queries.bookingParams);
  if (!bookingOutcome || bookingOutcome.affectedRows === 0) {
    return {
      status: 409,
      body: { error: "สถานะการจองไม่รองรับการทำรายการนี้" },
      committed: false,
    };
  }
  await connection.query(queries.paymentSql, queries.paymentParams);
  await connection.commit();
  return { status: 200, body: { ok: true }, committed: true };
}

function normalizeSlipReviewSpec(reviewSpec) {
  const cleanReason = String((reviewSpec && reviewSpec.reason) || "").trim();
  if (!reviewSpec || (!reviewSpec.approve && !cleanReason)) {
    return { error: "กรุณาระบุเหตุผลที่ปฏิเสธสลิป" };
  }
  return { normalizedSpec: { ...reviewSpec, reason: cleanReason } };
}

async function reviewPaymentSlipTransactional(db, reviewSpec) {
  const validation = normalizeSlipReviewSpec(reviewSpec);
  if (validation.error) {
    return { status: 400, body: { error: validation.error } };
  }
  const outcome = await withTransaction(db, "Slip review", (connection) =>
    executeSlipReviewTransaction(connection, validation.normalizedSpec)
  );
  return { status: outcome.status, body: outcome.body };
}

async function toggleSpaceFavorite(db, userId, spaceId) {
  const [spaceRows] = await db.query(
    "SELECT space_id FROM spaces WHERE space_id = ? LIMIT 1",
    [spaceId]
  );
  if (spaceRows.length === 0) {
    return { status: 404, body: { error: "ไม่พบพื้นที่" } };
  }
  const [existing] = await db.query(
    "SELECT 1 FROM user_favorites WHERE user_id = ? AND space_id = ?",
    [userId, spaceId]
  );
  if (existing.length > 0) {
    await db.query("DELETE FROM user_favorites WHERE user_id = ? AND space_id = ?", [userId, spaceId]);
  } else {
    await db.query("INSERT INTO user_favorites (user_id, space_id) VALUES (?, ?)", [userId, spaceId]);
  }
  return { status: 200, body: { ok: true } };
}

const SAFE_IMAGE_PREFIXES = ["/uploads/", "/api/spaces/"];
const BASE64_IMAGE_PREFIXES = ["data:image/png;base64,", "data:image/jpeg;base64,"];

function isSafeImageInput(rawUrl) {
  if (!rawUrl) return true;
  const clean = String(rawUrl).trim();
  if (!clean) return true;
  if (BASE64_IMAGE_PREFIXES.some((prefix) => clean.startsWith(prefix))) {
    return clean.length <= 8 * 1024 * 1024;
  }
  if (SAFE_IMAGE_PREFIXES.some((prefix) => clean.startsWith(prefix))) {
    return true;
  }
  return /^https?:\/\/[^\s<>"]+$/i.test(clean);
}

function hasMinuteBounds(start, end) {
  return start >= 0 && end <= 1440 && start < end;
}

function isValidHourEntry(dayEntry) {
  if (!dayEntry || typeof dayEntry !== "object") return false;
  const start = Number(dayEntry.start);
  const end = Number(dayEntry.end);
  if (!Number.isInteger(start) || !Number.isInteger(end)) return false;
  return hasMinuteBounds(start, end);
}

function isValidHoursList(days) {
  return Array.isArray(days) && days.length === 7 && days.every(isValidHourEntry);
}

function pickFirstDefined(candidates, fallback) {
  for (const candidate of candidates) {
    if (candidate !== undefined && candidate !== null) return candidate;
  }
  return fallback;
}

function hasMissingCoreFields(fields, body, existingSpace) {
  if (!fields.title || !fields.category || !fields.location) return true;
  const requiresDescription = !existingSpace || body.description !== undefined;
  return requiresDescription && !fields.description;
}

function hasInvalidSpaceNumbers(fields) {
  const invalidPrice = !Number.isFinite(fields.price) || fields.price <= 0;
  const invalidCapacity = !Number.isInteger(fields.capacity) || fields.capacity <= 0;
  return invalidPrice || invalidCapacity;
}

function validateCoreSpaceFields(fields, body, existingSpace) {
  if (hasMissingCoreFields(fields, body, existingSpace) || hasInvalidSpaceNumbers(fields)) {
    return "กรอกข้อมูลพื้นที่ คำอธิบาย ราคา และความจุให้ครบถ้วน";
  }
  if (!isSafeImageInput(fields.imageUrl)) {
    return "รูปแบบลิงก์หรือไฟล์รูปภาพไม่ถูกต้อง";
  }
  return null;
}

function resolveSpaceHoursJson(rawHours, existingSpace) {
  if (rawHours === undefined || rawHours === null) {
    const existingHours = existingSpace ? existingSpace.hours_json : null;
    return { hoursJson: existingHours || DEFAULT_WEEK_HOURS };
  }
  if (!isValidHoursList(rawHours)) {
    return { error: "เวลาเปิดปิดของแต่ละวันไม่ถูกต้อง" };
  }
  return { hoursJson: JSON.stringify(rawHours) };
}

function resolveSpaceAmenities(rawAmenities, existingSpace) {
  if (rawAmenities === undefined) {
    if (existingSpace) {
      return {
        amenities: [],
        amenitiesJson: existingSpace.amenities_json ?? null,
        shouldSyncAmenities: false,
      };
    }
    return { amenities: [], amenitiesJson: "[]", shouldSyncAmenities: true };
  }
  if (!Array.isArray(rawAmenities)) {
    return { error: "รูปแบบรายการสิ่งอำนวยความสะดวกไม่ถูกต้อง" };
  }
  const cleaned = rawAmenities.map((entry) => String(entry || "").trim()).filter(Boolean);
  return { amenities: cleaned, amenitiesJson: JSON.stringify(cleaned), shouldSyncAmenities: true };
}

function resolveSpaceMutationInput(rawBody, existingSpace = null) {
  const body = rawBody && typeof rawBody === "object" ? rawBody : {};
  const base = existingSpace || {};
  const fields = {
    title: String(pickFirstDefined([body.name, body.title, base.title], "")).trim(),
    category: String(pickFirstDefined([body.category, base.category], "ห้องประชุม")).trim(),
    location: String(pickFirstDefined([body.location, base.location], "")).trim(),
    price: Number(pickFirstDefined([body.price, body.price_per_day, base.price_per_day], 0)),
    capacity: Number(pickFirstDefined([body.capacity, base.capacity], 10)),
    description: String(pickFirstDefined([body.description, base.description], "")).trim(),
    imageUrl: String(pickFirstDefined([body.image, body.image_url, base.image_url], "")).trim(),
  };
  const coreError = validateCoreSpaceFields(fields, body, existingSpace);
  if (coreError) return { error: coreError };
  const hoursOutcome = resolveSpaceHoursJson(body.hours, existingSpace);
  if (hoursOutcome.error) return { error: hoursOutcome.error };
  const amenitiesOutcome = resolveSpaceAmenities(body.amenities, existingSpace);
  if (amenitiesOutcome.error) return { error: amenitiesOutcome.error };
  return {
    spaceInput: {
      ...fields,
      hoursJson: hoursOutcome.hoursJson,
      amenities: amenitiesOutcome.amenities,
      amenitiesJson: amenitiesOutcome.amenitiesJson,
      shouldSyncAmenities: amenitiesOutcome.shouldSyncAmenities,
    },
  };
}

function resolveManagedUploadPath(rawUrl, uploadsDir) {
  if (!rawUrl || !uploadsDir) return null;
  const cleanPath = String(rawUrl).split("?")[0];
  const baseName = path.basename(cleanPath);
  if (!/^(slip|payout)_[A-Za-z0-9._-]+$/i.test(baseName)) return null;
  return path.join(uploadsDir, baseName);
}

async function collectSpaceUploadPaths(connection, spaceId, uploadsDir) {
  const [bookingRows] = await connection.query(
    "SELECT booking_id, slip_image_url, payout_slip_url FROM bookings WHERE space_id = ?",
    [spaceId]
  );
  const bookingIds = bookingRows.map((entry) => entry.booking_id);
  const urlCandidates = bookingRows.flatMap((entry) => [
    entry.slip_image_url,
    entry.payout_slip_url,
  ]);
  if (bookingIds.length > 0) {
    const [paymentRows] = await connection.query(
      "SELECT slip_image_url FROM payments WHERE booking_id IN (?)",
      [bookingIds]
    );
    for (const paymentRow of paymentRows) {
      urlCandidates.push(paymentRow.slip_image_url);
    }
  }
  const filePaths = new Set();
  for (const candidate of urlCandidates) {
    const resolvedPath = resolveManagedUploadPath(candidate, uploadsDir);
    if (resolvedPath) filePaths.add(resolvedPath);
  }
  return { bookingIds, uploadPaths: [...filePaths] };
}

async function deleteBookingDependents(connection, bookingIds) {
  if (bookingIds.length === 0) return;
  await connection.query("DELETE FROM reviews WHERE booking_id IN (?)", [bookingIds]);
  await connection.query("DELETE FROM payments WHERE booking_id IN (?)", [bookingIds]);
  await connection.query(
    "DELETE FROM admin_logs WHERE target_type = 'booking' AND target_id IN (?)",
    [bookingIds]
  );
  await connection.query("DELETE FROM bookings WHERE booking_id IN (?)", [bookingIds]);
}

async function executeSpaceDelete(connection, spaceId, uploadsDir) {
  const { bookingIds, uploadPaths } = await collectSpaceUploadPaths(connection, spaceId, uploadsDir);
  await deleteBookingDependents(connection, bookingIds);
  await connection.query("DELETE FROM room_blocks WHERE space_id = ?", [spaceId]);
  await connection.query("DELETE FROM space_amenities WHERE space_id = ?", [spaceId]);
  await connection.query("DELETE FROM user_favorites WHERE space_id = ?", [spaceId]);
  await connection.query(
    "DELETE FROM admin_logs WHERE target_type = 'space' AND target_id = ?",
    [spaceId]
  );
  const [spaceOutcome] = await connection.query("DELETE FROM spaces WHERE space_id = ?", [spaceId]);
  if (!spaceOutcome || spaceOutcome.affectedRows === 0) {
    return { status: 404, body: { error: "ไม่พบพื้นที่" }, committed: false, uploadPaths: [] };
  }
  await connection.commit();
  return { status: 200, body: { ok: true }, committed: true, uploadPaths };
}

async function deleteSpaceTransactional(db, spaceId, uploadsDir, fileOps = fs) {
  const outcome = await withTransaction(
    db,
    "Space delete",
    (connection) => executeSpaceDelete(connection, spaceId, uploadsDir),
    {
      onCommit: (txOutcome) => {
        for (const uploadPath of txOutcome.uploadPaths) {
          removeUploadedFileSafe(uploadPath, fileOps);
        }
      },
    }
  );
  return { status: outcome.status, body: outcome.body };
}

module.exports = {
  withTransaction,
  createBookingTransactional,
  computeBookingEndsAt,
  evaluateBookingLifecycleTransition,
  sweepExpiredBookings,
  submitPaymentSlipTransactional,
  applyGuardedBookingUpdate,
  reviewPaymentSlipTransactional,
  toggleSpaceFavorite,
  deleteSpaceTransactional,
  isSafeImageInput,
  isValidHoursList,
  resolveSpaceMutationInput,
  formatClockTimestamp,
  hasBookingPermission,
  guardSpaceAccess,
  guardBookingAccess,
  guardSlipUploadAccess,
};
