const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const express = require("express");
const cors = require("cors");
const multer = require("multer");
const con = require("./db_config");
const {
  hashPassword,
  verifyPassword,
  recordSession,
  revokeSession,
  revokeOtherUserSessions,
  isValidEmail,
  isValidPhone,
  buildUniqueUsername,
  normalizeRoleForApp,
  normalizeRoleForDb,
  signToken,
  verifyToken,
  createAuthRateLimiter,
} = require("./auth_security");
const { DEFAULT_WEEK_HOURS, ensureSchema } = require("./schema_bootstrap");
const { toIsoDate, buildSnapshot } = require("./snapshot_builder");
const {
  withTransaction,
  createBookingTransactional,
  computeBookingEndsAt,
  sweepExpiredBookings,
  submitPaymentSlipTransactional,
  applyGuardedBookingUpdate,
  reviewPaymentSlipTransactional,
  isValidHoursList,
  resolveSpaceMutationInput,
  toggleSpaceFavorite,
  deleteSpaceTransactional,
  guardSpaceAccess,
  guardBookingAccess,
  guardSlipUploadAccess,
} = require("./booking_guards");

const app = express();
const db = con.promise();
const uploadsDir = path.join(__dirname, "uploads");

if (!fs.existsSync(uploadsDir)) {
  fs.mkdirSync(uploadsDir, { recursive: true });
}

const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 5 * 1024 * 1024 },
});

const corsOptions = process.env.CORS_ORIGIN
  ? { origin: process.env.CORS_ORIGIN.split(",").map((origin) => origin.trim()).filter(Boolean) }
  : undefined;
const authRateLimiter = createAuthRateLimiter();

app.use(cors(corsOptions));
app.use(express.json({ limit: "15mb" }));
app.use("/uploads", guardSlipUploadAccess(db, verifyToken()), express.static(uploadsDir));
app.get("/test-slip.png", (_req, res) =>
  res.sendFile(path.join(uploadsDir, "test-slip.png"))
);

let schemaReadyPromise = null;
function initDatabaseOnce() {
  if (!schemaReadyPromise) {
    schemaReadyPromise = ensureSchema(db).catch((err) => {
      schemaReadyPromise = null;
      throw err;
    });
  }
  return schemaReadyPromise;
}

app.use(async (_req, _res, next) => {
  try {
    await initDatabaseOnce();
  } catch (err) {
    console.warn("Schema auto-check warning:", err.message || err.code || String(err));
  }
  next();
});

function safeErrorMessage(err) {
  console.error("Unhandled route error:", err && (err.message || err.code || String(err)));
  return "เกิดข้อผิดพลาดภายในเซิร์ฟเวอร์";
}

const wrapRoute = (handler) => (req, res, next) =>
  Promise.resolve(handler(req, res, next)).catch((err) =>
    res.status(500).json({ error: safeErrorMessage(err) })
  );

async function recordAdminLog(actorId, actorName, action, targetType, targetId, details) {
  await db.query(
    `INSERT INTO admin_logs (admin_id, admin_name, action, target_type, target_id, details)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [Number(actorId) || 1003, actorName || "ผู้ดูแลระบบ", action, targetType, Number(targetId) || 0, details]
  );
}

//=================== 1. Health & State Routes =================================

app.get("/api/health", wrapRoute(async (_req, res) => {
  const [rows] = await db.query("SELECT DATABASE() AS database_name");
  return res.json({ ok: true, database: rows[0].database_name });
}));

app.get("/api/state", verifyToken(), wrapRoute(async (req, res) => {
  const [users] = await db.query("SELECT * FROM users WHERE user_id = ?", [req.user.id]);
  if (users.length === 0 || users[0].status === "suspended" || users[0].role === "disabled") {
    return res.status(401).json({ error: "บัญชีถูกระงับหรือไม่พบบัญชี" });
  }
  await sweepExpiredBookings(db);
  return res.json(await buildSnapshot(db, req.user.id));
}));

//=================== 2. Auth Routes (Week 11 Lab + Flutter + rent-space-db) ===

const handleLogin = wrapRoute(async (req, res) => {
  const identifier = String(req.body.login || req.body.email || req.body.username || "").trim();
  const password = String(req.body.password || "");
  if (!identifier || !password) {
    return res.status(400).json({ error: "กรุณากรอกอีเมล/ชื่อผู้ใช้และรหัสผ่าน" });
  }
  const [rows] = await db.query(
    "SELECT * FROM users WHERE email = ? OR username = ? LIMIT 1",
    [identifier, identifier]
  );
  if (rows.length === 0) {
    return res.status(401).json({ error: "อีเมลหรือรหัสผ่านไม่ถูกต้อง" });
  }
  const account = rows[0];
  if (account.status === "suspended" || account.role === "disabled") {
    return res.status(401).json({ error: "บัญชีนี้ถูกระงับการใช้งาน" });
  }
  if (!verifyPassword(account.password_hash, password)) {
    return res.status(401).json({ error: "อีเมลหรือรหัสผ่านไม่ถูกต้อง" });
  }
  const token = signToken(account);
  await recordSession(db, account.user_id, token);
  const appRole = normalizeRoleForApp(account.role);
  return res.json({
    token,
    id: String(account.user_id),
    username: account.username,
    name: account.name,
    email: account.email,
    role: appRole,
    user: {
      user_id: account.user_id,
      id: String(account.user_id),
      name: account.name,
      username: account.username,
      email: account.email,
      role: appRole,
    },
  });
});

app.post("/api/login", authRateLimiter, handleLogin);
app.post("/api/auth/login", authRateLimiter, handleLogin);

const handleRegister = wrapRoute(async (req, res) => {
  const name = String(req.body.name || req.body.username || "").trim();
  const email = String(req.body.email || "").trim();
  const password = String(req.body.password || "");
  const phone = String(req.body.phone || "").trim();
  const dbRole = normalizeRoleForDb(req.body.role);

  if (!name || !isValidEmail(email) || password.length < 8) {
    return res.status(400).json({ error: "กรุณากรอกชื่อ อีเมลที่ถูกต้อง และรหัสผ่านอย่างน้อย 8 ตัวอักษร" });
  }
  if (phone && !isValidPhone(phone)) {
    return res.status(400).json({ error: "หมายเลขโทรศัพท์ไม่ถูกต้อง" });
  }
  if (dbRole === "admin") {
    return res.status(403).json({ error: "ไม่สามารถสมัครบัญชี Admin" });
  }
  const [dup] = await db.query("SELECT user_id FROM users WHERE email = ? LIMIT 1", [email]);
  if (dup.length > 0) {
    return res.status(409).json({ error: "อีเมลนี้ถูกใช้งานแล้ว" });
  }
  const uniqueUsername = buildUniqueUsername(req.body.username, email);
  const hashed = hashPassword(password);
  const [ins] = await db.query(
    `INSERT INTO users (name, username, email, phone, password_hash, role, status)
     VALUES (?, ?, ?, ?, ?, ?, 'active')`,
    [name, uniqueUsername, email, phone, hashed, dbRole]
  );
  const [createdRows] = await db.query("SELECT * FROM users WHERE user_id = ?", [ins.insertId]);
  const token = signToken(createdRows[0]);
  await recordSession(db, ins.insertId, token);
  return res.status(201).json({
    token,
    id: String(ins.insertId),
    user: {
      user_id: ins.insertId,
      name,
      username: uniqueUsername,
      email,
      role: normalizeRoleForApp(dbRole),
    },
  });
});

app.post("/api/register", authRateLimiter, handleRegister);
app.post("/api/auth/register", authRateLimiter, handleRegister);

app.get("/api/auth/me", verifyToken(), wrapRoute(async (req, res) => {
  const [rows] = await db.query("SELECT * FROM users WHERE user_id = ?", [req.user.id]);
  if (rows.length === 0) return res.status(404).json({ error: "ไม่พบผู้ใช้" });
  const u = rows[0];
  return res.json({
    user_id: u.user_id,
    id: String(u.user_id),
    name: u.name,
    username: u.username,
    email: u.email,
    phone: u.phone || "",
    role: normalizeRoleForApp(u.role),
  });
}));

app.post("/api/auth/logout", verifyToken(), wrapRoute(async (req, res) => {
  await revokeSession(db, req.rawToken);
  return res.json({ ok: true });
}));

app.put("/api/auth/profile", verifyToken(), wrapRoute(async (req, res) => {
  const name = String(req.body.name || "").trim();
  const email = String(req.body.email || "").trim();
  const phone = String(req.body.phone || "").trim();
  const bankInfo = req.body.bankInfo != null ? String(req.body.bankInfo).trim() : "";
  if (!name || !isValidEmail(email)) {
    return res.status(400).json({ error: "กรุณาระบุชื่อและอีเมลที่ถูกต้อง" });
  }
  if (phone && !isValidPhone(phone)) {
    return res.status(400).json({ error: "หมายเลขโทรศัพท์ไม่ถูกต้อง" });
  }
  const [dup] = await db.query(
    "SELECT user_id FROM users WHERE email = ? AND user_id <> ? LIMIT 1",
    [email, req.user.id]
  );
  if (dup.length > 0) {
    return res.status(409).json({ error: "อีเมลนี้ถูกใช้งานแล้ว" });
  }
  await db.query(
    "UPDATE users SET name = ?, email = ?, phone = ?, bank_info = ? WHERE user_id = ?",
    [name, email, phone, bankInfo, req.user.id]
  );
  return res.json({ ok: true });
}));

app.put("/api/auth/password", verifyToken(), wrapRoute(async (req, res) => {
  const currentPassword = typeof req.body?.currentPassword === "string" ? req.body.currentPassword : "";
  const newPassword = typeof req.body?.newPassword === "string" ? req.body.newPassword : "";
  if (newPassword.length < 8) {
    return res.status(400).json({ error: "รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร" });
  }
  const [rows] = await db.query("SELECT * FROM users WHERE user_id = ?", [req.user.id]);
  if (rows.length === 0 || !verifyPassword(rows[0].password_hash, currentPassword)) {
    return res.status(400).json({ error: "รหัสผ่านปัจจุบันไม่ถูกต้อง" });
  }
  await db.query("UPDATE users SET password_hash = ? WHERE user_id = ?", [
    hashPassword(newPassword),
    req.user.id,
  ]);
  await revokeOtherUserSessions(db, req.user.id, req.rawToken);
  return res.json({ ok: true });
}));

//=================== 3. Spaces & Availability Routes ==========================

app.get("/api/spaces", wrapRoute(async (_req, res) => {
  const [rows] = await db.query(
    `SELECT s.space_id, s.owner_id, s.title, s.description, s.location, s.price_per_day, s.category, s.capacity,
            s.image_url, s.rating, s.rating_count, s.status
     FROM spaces s
     JOIN users u ON u.user_id = s.owner_id
     WHERE s.status = 'approved'
       AND COALESCE(u.status, 'active') NOT IN ('suspended', 'disabled')
       AND u.role <> 'disabled'
     ORDER BY s.space_id DESC`
  );
  return res.json(rows);
}));

async function syncSpaceAmenities(spaceId, amenityNames) {
  if (!Array.isArray(amenityNames)) return;
  await db.query("DELETE FROM space_amenities WHERE space_id = ?", [spaceId]);
  for (const rawName of amenityNames) {
    const clean = String(rawName || "").trim();
    if (!clean) continue;
    await db.query("INSERT IGNORE INTO amenities (name) VALUES (?)", [clean]);
    const [amRows] = await db.query("SELECT amenity_id FROM amenities WHERE name = ? LIMIT 1", [clean]);
    if (amRows.length > 0) {
      await db.query("INSERT IGNORE INTO space_amenities (space_id, amenity_id) VALUES (?, ?)", [
        spaceId,
        amRows[0].amenity_id,
      ]);
    }
  }
}

app.post("/api/spaces", verifyToken(["owner", "admin"]), wrapRoute(async (req, res) => {
  const resolved = resolveSpaceMutationInput(req.body, null);
  if (resolved.error) return res.status(400).json({ error: resolved.error });
  const spaceInput = resolved.spaceInput;
  const [ins] = await db.query(
    `INSERT INTO spaces (owner_id, title, description, location, price_per_day, category, capacity, image_url, hours_json, amenities_json, status)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
    [
      req.user.id,
      spaceInput.title,
      spaceInput.description,
      spaceInput.location,
      spaceInput.price,
      spaceInput.category,
      spaceInput.capacity,
      spaceInput.imageUrl,
      spaceInput.hoursJson,
      spaceInput.amenitiesJson,
    ]
  );
  await syncSpaceAmenities(ins.insertId, spaceInput.amenities);
  return res.status(201).json({ id: String(ins.insertId), space_id: ins.insertId, status: "pending" });
}));

function parseAvailabilityBlocks(rawBlocks) {
  if (!Array.isArray(rawBlocks)) return [];
  return rawBlocks.map((block) => {
    const startDt = new Date(block.start);
    const endDt = new Date(block.end);
    if (Number.isNaN(startDt.getTime()) || Number.isNaN(endDt.getTime()) || endDt <= startDt) {
      return null;
    }
    return {
      startDt,
      endDt,
      startDateStr: toIsoDate(startDt),
      endDateStr: toIsoDate(new Date(endDt.getTime() + 86400000)),
      reason: block.reason || "ปิดห้อง",
    };
  });
}

app.put("/api/spaces/:id", verifyToken(["owner", "admin"]), guardSpaceAccess(db), wrapRoute(async (req, res) => {
  const spaceId = req.params.id;
  const resolved = resolveSpaceMutationInput(req.body, req.spaceRecord || {});
  if (resolved.error) return res.status(400).json({ error: resolved.error });
  const spaceInput = resolved.spaceInput;
  const requireModeration = req.user.role !== "admin";
  await db.query(
    `UPDATE spaces
     SET title = ?, category = ?, location = ?, price_per_day = ?, capacity = ?, description = ?, image_url = ?, hours_json = ?, amenities_json = ?${requireModeration ? ", status = 'pending', review_reason = ''" : ""}
     WHERE space_id = ?`,
    [
      spaceInput.title,
      spaceInput.category,
      spaceInput.location,
      spaceInput.price,
      spaceInput.capacity,
      spaceInput.description,
      spaceInput.imageUrl,
      spaceInput.hoursJson,
      spaceInput.amenitiesJson,
      spaceId,
    ]
  );
  if (spaceInput.shouldSyncAmenities) {
    await syncSpaceAmenities(spaceId, spaceInput.amenities);
  }
  return res.json({ id: String(spaceId), ok: true });
}));

app.delete("/api/spaces/:id", verifyToken(["owner", "admin"]), guardSpaceAccess(db), wrapRoute(async (req, res) => {
  const outcome = await deleteSpaceTransactional(db, req.params.id, uploadsDir);
  return res.status(outcome.status).json(outcome.body);
}));

app.put(
  "/api/spaces/:id/availability",
  verifyToken(["owner", "admin"]),
  guardSpaceAccess(db),
  wrapRoute(async (req, res) => {
    const spaceId = req.params.id;
    const days = req.body.days !== undefined ? req.body.days : JSON.parse(DEFAULT_WEEK_HOURS);
    if (!isValidHoursList(days)) {
      return res.status(400).json({ error: "เวลาเปิดปิดของแต่ละวันไม่ถูกต้อง" });
    }
    const parsedBlocks = parseAvailabilityBlocks(req.body.blocks);
    if (parsedBlocks.includes(null)) {
      return res.status(400).json({ error: "ช่วงเวลาปิดห้องไม่ถูกต้อง" });
    }
    await withTransaction(db, "Availability", async (connection) => {
      await connection.query("UPDATE spaces SET hours_json = ? WHERE space_id = ?", [JSON.stringify(days), spaceId]);
      await connection.query("DELETE FROM room_blocks WHERE space_id = ?", [spaceId]);
      for (const parsedBlock of parsedBlocks) {
        await connection.query(
          `INSERT INTO room_blocks (space_id, created_by, start_date, end_date, start_at, end_at, reason)
           VALUES (?, ?, ?, ?, ?, ?, ?)`,
          [
            spaceId,
            req.user.id,
            parsedBlock.startDateStr,
            parsedBlock.endDateStr,
            parsedBlock.startDt,
            parsedBlock.endDt,
            parsedBlock.reason,
          ]
        );
      }
      await connection.commit();
      return { committed: true };
    });
    return res.json({ ok: true });
  })
);

app.post("/api/spaces/:id/favorite", verifyToken(), wrapRoute(async (req, res) => {
  const outcome = await toggleSpaceFavorite(db, req.user.id, req.params.id);
  return res.status(outcome.status).json(outcome.body);
}));

app.get("/api/spaces/:spaceId/availability", wrapRoute(async (req, res) => {
  const spaceId = req.params.spaceId;
  await sweepExpiredBookings(db);
  const [bookings] = await db.query(
    "SELECT booking_id, start_date, end_date, start_time, end_time, status FROM bookings WHERE space_id = ? AND status IN ('pending','approved','confirmed')",
    [spaceId]
  );
  const [blocks] = await db.query("SELECT * FROM room_blocks WHERE space_id = ?", [spaceId]);
  return res.json({ bookings, blocks });
}));

//=================== 4. Bookings Routes =======================================

app.get("/api/bookings", verifyToken(), wrapRoute(async (req, res) => {
  await sweepExpiredBookings(db);
  if (req.user.role === "admin") {
    const [rows] = await db.query("SELECT * FROM bookings ORDER BY booking_id DESC");
    return res.json(rows);
  }
  if (req.user.role === "owner") {
    const [rows] = await db.query(
      "SELECT b.* FROM bookings b JOIN spaces s ON s.space_id = b.space_id WHERE s.owner_id = ? ORDER BY b.booking_id DESC",
      [req.user.id]
    );
    return res.json(rows);
  }
  const [rows] = await db.query("SELECT * FROM bookings WHERE customer_id = ? ORDER BY booking_id DESC", [
    req.user.id,
  ]);
  return res.json(rows);
}));

app.post("/api/bookings", verifyToken("renter"), wrapRoute(async (req, res) => {
  const bookingOutcome = await createBookingTransactional(db, req.user.id, req.body);
  return res.status(bookingOutcome.status).json(bookingOutcome.body);
}));

app.post(
  "/api/bookings/:id/approve",
  verifyToken(["owner", "admin"]),
  guardBookingAccess(db, { access: "ownerOrAdmin", allowedStatuses: ["ownerReview"] }),
  wrapRoute(async (req, res) => {
    const outcome = await applyGuardedBookingUpdate(
      db,
      `UPDATE bookings
       SET status = 'approved', app_status = 'paymentDue', approved_at = NOW(), reason = ?, reason_kind = 'none'
       WHERE booking_id = ? AND COALESCE(NULLIF(app_status, ''), status) IN ('ownerReview', 'pending')`,
      [String((req.body && req.body.reason) || "").trim(), req.params.id]
    );
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/bookings/:id/reject",
  verifyToken(["owner", "admin"]),
  guardBookingAccess(db, { access: "ownerOrAdmin", allowedStatuses: ["ownerReview"] }),
  wrapRoute(async (req, res) => {
    const reason = String((req.body && req.body.reason) || "").trim();
    if (!reason) return res.status(400).json({ error: "กรุณาระบุเหตุผลที่ปฏิเสธคำขอ" });
    const outcome = await applyGuardedBookingUpdate(
      db,
      `UPDATE bookings
       SET status = 'rejected', app_status = 'ownerRejected', reason = ?, reason_kind = 'ownerRejected'
       WHERE booking_id = ? AND COALESCE(NULLIF(app_status, ''), status) IN ('ownerReview', 'pending')`,
      [reason, req.params.id]
    );
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/bookings/:id/cancel",
  verifyToken(),
  guardBookingAccess(db, {
    access: "participantOrAdmin",
    allowedStatuses: ["ownerReview", "paymentDue", "slipRejected"],
    adminStatuses: ["ownerReview", "paymentDue", "slipReview", "slipRejected", "confirmed"],
  }),
  wrapRoute(async (req, res) => {
    const reason = String((req.body && req.body.reason) || "").trim();
    if (!reason) return res.status(400).json({ error: "กรุณาระบุเหตุผลการยกเลิก" });
    const allowedStatusList =
      req.user.role === "admin"
        ? "('ownerReview', 'pending', 'paymentDue', 'approved', 'slipReview', 'slipRejected', 'confirmed')"
        : "('ownerReview', 'pending', 'paymentDue', 'approved', 'slipRejected')";
    const outcome = await applyGuardedBookingUpdate(
      db,
      `UPDATE bookings
       SET status = 'cancelled', app_status = 'canceled', reason = ?, reason_kind = 'canceledByUser'
       WHERE booking_id = ? AND COALESCE(NULLIF(app_status, ''), status) IN ${allowedStatusList}`,
      [reason, req.params.id]
    );
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/bookings/:id/complete",
  verifyToken(["owner", "admin"]),
  guardBookingAccess(db, { access: "ownerOrAdmin", allowedStatuses: ["confirmed"] }),
  wrapRoute(async (req, res) => {
    const endsAt = computeBookingEndsAt(req.bookingRecord);
    if (Date.now() < endsAt.getTime()) {
      return res.status(409).json({ error: "ยังไม่ถึงเวลาสิ้นสุดการจอง" });
    }
    const outcome = await applyGuardedBookingUpdate(
      db,
      `UPDATE bookings
       SET status = 'completed', app_status = 'completed', completed_at = NOW()
       WHERE booking_id = ? AND COALESCE(NULLIF(app_status, ''), status) = 'confirmed'`,
      [req.params.id]
    );
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/bookings/:id/review",
  verifyToken("renter"),
  guardBookingAccess(db, { access: "renter", allowedStatuses: ["completed"] }),
  wrapRoute(async (req, res) => {
    const bookingId = req.params.id;
    const rawRating = req.body.rating == null ? 5 : Number(req.body.rating);
    if (!Number.isFinite(rawRating) || rawRating < 1 || rawRating > 5) {
      return res.status(400).json({ error: "คะแนนรีวิวต้องอยู่ระหว่าง 1–5 ดาว" });
    }
    const rating = Math.round(rawRating);
    const comment = String(req.body.comment || req.body.review_comment || "").trim();
    if (!comment) return res.status(400).json({ error: "กรุณากรอกความคิดเห็นรีวิว" });

    await db.query("UPDATE bookings SET rating = ?, review_comment = ? WHERE booking_id = ?", [
      rating,
      comment,
      bookingId,
    ]);
    await db.query(
      `INSERT INTO reviews (booking_id, rating, review_comment)
       VALUES (?, ?, ?)
       ON DUPLICATE KEY UPDATE rating = VALUES(rating), review_comment = VALUES(review_comment)`,
      [bookingId, rating, comment]
    );
    if (req.bookingRecord && req.bookingRecord.space_id) {
      const spaceId = req.bookingRecord.space_id;
      await db.query(
        `UPDATE spaces s
         JOIN (
           SELECT b.space_id, ROUND(AVG(r.rating), 2) AS avg_r, COUNT(*) AS cnt_r
           FROM reviews r
           JOIN bookings b ON b.booking_id = r.booking_id
           WHERE b.space_id = ?
           GROUP BY b.space_id
         ) stats ON stats.space_id = s.space_id
         SET s.rating = stats.avg_r, s.rating_count = stats.cnt_r
         WHERE s.space_id = ?`,
        [spaceId, spaceId]
      );
    }
    return res.status(201).json({ ok: true });
  })
);

//=================== 5. Payments Routes =======================================

function resolveValidatedSlipExtension(uploadedFile) {
  const buf = uploadedFile.buffer;
  const rawExt = path.extname(uploadedFile.originalname || "").toLowerCase();
  const isPng =
    buf && buf.length >= 8 && buf[0] === 137 && buf[1] === 80 && buf[2] === 78 && buf[3] === 71;
  const isJpg = buf && buf.length >= 3 && buf[0] === 255 && buf[1] === 216 && buf[2] === 255;
  if (rawExt === ".png" && isPng) return ".png";
  if ((rawExt === ".jpg" || rawExt === ".jpeg") && isJpg) return rawExt;
  return null;
}

function prepareUploadedSlip(uploadedFile, prefix, bookingId) {
  const ext = resolveValidatedSlipExtension(uploadedFile);
  if (!ext) return null;
  const storedName = `${prefix}_${bookingId}_${Date.now()}${ext}`;
  return {
    storedFilePath: path.join(uploadsDir, storedName),
    imageUrl: `/uploads/${storedName}`,
    originalFileName: path.basename(uploadedFile.originalname || storedName),
    base64Content: uploadedFile.buffer.toString("base64"),
  };
}

app.post(
  "/api/payments/:id/slip",
  verifyToken("renter"),
  guardBookingAccess(db, { access: "renter", allowedStatuses: ["paymentDue", "slipRejected"] }),
  upload.single("file"),
  wrapRoute(async (req, res) => {
    const bookingId = req.params.id;
    const note = String((req.body && req.body.note) || "").trim();
    if (!req.file) return res.status(400).json({ error: "กรุณาแนบไฟล์สลิป" });
    const prepared = prepareUploadedSlip(req.file, "slip", bookingId);
    if (!prepared) return res.status(400).json({ error: "รองรับภาพ JPG และ PNG เท่านั้น" });
    const outcome = await submitPaymentSlipTransactional(db, {
      bookingId,
      note,
      ...prepared,
      fileBuffer: req.file.buffer,
      amount: req.bookingRecord?.total_price ? req.bookingRecord.total_price : 500,
    });
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/payments/:id/review",
  verifyToken("admin"),
  guardBookingAccess(db, { access: "admin", allowedStatuses: ["slipReview"] }),
  wrapRoute(async (req, res) => {
    const bookingId = req.params.id;
    const approve = Boolean(req.body && req.body.approve);
    const reason = String((req.body && req.body.reason) || "").trim();
    const outcome = await reviewPaymentSlipTransactional(db, { bookingId, approve, reason });
    if (outcome.status !== 200) return res.status(outcome.status).json(outcome.body);
    await recordAdminLog(
      req.user.id,
      req.user.username,
      "REVIEW_PAYMENT",
      "booking",
      bookingId,
      approve ? "อนุมัติสลิป" : `ปฏิเสธสลิป: ${reason}`
    );
    return res.status(outcome.status).json(outcome.body);
  })
);

app.post(
  "/api/payments/:id/payout",
  verifyToken("admin"),
  guardBookingAccess(db, { access: "admin", allowedStatuses: ["completed"] }),
  upload.single("file"),
  wrapRoute(async (req, res) => {
    let storedFilePath = null;
    try {
      const bookingId = req.params.id;
      if (req.bookingRecord.paid_out_at != null) {
        return res.status(409).json({ error: "รายการนี้บันทึกจ่ายเงินให้เจ้าของแล้ว" });
      }
      const payoutNote = String((req.body && req.body.note) || "").trim();
      let payoutSlipName = null;
      let payoutSlipUrl = null;
      let payoutSlipData = null;

      if (req.file) {
        const prepared = prepareUploadedSlip(req.file, "payout", bookingId);
        if (!prepared) return res.status(400).json({ error: "รองรับภาพ JPG และ PNG เท่านั้น" });
        storedFilePath = prepared.storedFilePath;
        fs.writeFileSync(storedFilePath, req.file.buffer);
        payoutSlipUrl = prepared.imageUrl;
        payoutSlipName = prepared.originalFileName;
        payoutSlipData = prepared.base64Content;
      }

      const [updateResult] = await db.query(
        `UPDATE bookings
         SET paid_out_at = NOW(),
             payout_slip_name = COALESCE(?, payout_slip_name),
             payout_slip_url = COALESCE(?, payout_slip_url),
             payout_slip_data = COALESCE(?, payout_slip_data),
             payout_note = ?
         WHERE booking_id = ? AND paid_out_at IS NULL`,
        [payoutSlipName, payoutSlipUrl, payoutSlipData, payoutNote, bookingId]
      );
      if (!updateResult || updateResult.affectedRows === 0) {
        if (storedFilePath && fs.existsSync(storedFilePath)) fs.unlinkSync(storedFilePath);
        return res.status(409).json({ error: "รายการนี้บันทึกจ่ายเงินให้เจ้าของแล้ว" });
      }
      const logDetail = payoutSlipName
        ? `โอนเงินให้เจ้าของพื้นที่ (สลิป ${payoutSlipName}${payoutNote ? `: ${payoutNote}` : ""})`
        : `โอนเงินให้เจ้าของพื้นที่${payoutNote ? `: ${payoutNote}` : ""}`;
      await recordAdminLog(req.user.id, req.user.username, "PAYOUT_OWNER", "booking", bookingId, logDetail);
      return res.json({ ok: true, payout_slip_url: payoutSlipUrl || "" });
    } catch (err) {
      if (storedFilePath && fs.existsSync(storedFilePath)) {
        try {
          fs.unlinkSync(storedFilePath);
        } catch (unlinkErr) {
          console.warn("Payout slip cleanup warning:", unlinkErr.message);
        }
      }
      throw err;
    }
  })
);

//=================== 6. Admin & Issues Routes (Week 11 Lab + Flutter) =========

app.get("/api/admin/user", verifyToken("admin"), wrapRoute(async (_req, res) => {
  const [rows] = await db.query("SELECT user_id AS id, username, role, status FROM users WHERE role <> 'admin'");
  return res.json(rows);
}));

async function applyUserStatusChange(req, res, resolveNextStatus, sendOutcome) {
  const userId = req.params.id;
  const [rows] = await db.query("SELECT role, status FROM users WHERE user_id = ?", [userId]);
  if (rows.length === 0) return res.status(404).json({ error: "ไม่พบผู้ใช้" });
  if (rows[0].role === "admin" || Number(userId) === Number(req.user.id)) {
    return res.status(403).json({ error: "ไม่สามารถระงับบัญชีผู้ดูแลระบบได้" });
  }
  const nextStatus = resolveNextStatus(rows[0], req);
  await db.query("UPDATE users SET status = ? WHERE user_id = ?", [nextStatus, userId]);
  await recordAdminLog(req.user.id, req.user.username, "TOGGLE_USER", "user", userId, `status -> ${nextStatus}`);
  return sendOutcome(res, nextStatus);
}

app.patch("/api/admin/role/:id", verifyToken("admin"), wrapRoute((req, res) =>
  applyUserStatusChange(
    req,
    res,
    (_account, request) => (request.body.role === "disabled" ? "suspended" : "active"),
    (response) => response.status(200).send("Role updated")
  )
));

app.put("/api/admin/users/:id/toggle", verifyToken("admin"), wrapRoute((req, res) =>
  applyUserStatusChange(
    req,
    res,
    (account) => (account.status === "suspended" ? "active" : "suspended"),
    (response, status) => response.json({ ok: true, status })
  )
));

async function applyAdminSpaceModeration(req, res, moderationSpec) {
  const [updateOutcome] = await db.query(moderationSpec.sql, moderationSpec.params);
  if (!updateOutcome || updateOutcome.affectedRows === 0) {
    return res.status(404).json({ error: "ไม่พบพื้นที่" });
  }
  await recordAdminLog(
    req.user.id,
    req.user.username,
    moderationSpec.action,
    "space",
    req.params.id,
    moderationSpec.details
  );
  return res.json({ ok: true });
}

app.put("/api/admin/spaces/:id/approve", verifyToken("admin"), wrapRoute((req, res) =>
  applyAdminSpaceModeration(req, res, {
    sql: "UPDATE spaces SET status = 'approved', review_reason = '' WHERE space_id = ?",
    params: [req.params.id],
    action: "APPROVE_SPACE",
    details: "อนุมัติพื้นที่",
  })
));

app.put("/api/admin/spaces/:id/reject", verifyToken("admin"), wrapRoute((req, res) => {
  const reason = String((req.body && req.body.reason) || "").trim();
  if (!reason) return res.status(400).json({ error: "กรุณาระบุเหตุผล" });
  return applyAdminSpaceModeration(req, res, {
    sql: "UPDATE spaces SET status = 'rejected', review_reason = ? WHERE space_id = ?",
    params: [reason, req.params.id],
    action: "REJECT_SPACE",
    details: reason,
  });
}));

app.put("/api/admin/spaces/:id/activate", verifyToken("admin"), wrapRoute((req, res) =>
  applyAdminSpaceModeration(req, res, {
    sql: "UPDATE spaces SET status = 'approved', review_reason = '' WHERE space_id = ?",
    params: [req.params.id],
    action: "ACTIVATE_SPACE",
    details: "เปิดใช้งานพื้นที่อีกครั้ง",
  })
));

app.post("/api/admin/issues", verifyToken(), wrapRoute(async (req, res) => {
  const issueId = `iss_${Date.now()}_${crypto.randomBytes(3).toString("hex")}`;
  const subject = String(req.body.subject || "แจ้งปัญหา").trim() || "แจ้งปัญหา";
  const detail = String(req.body.detail || "").trim();
  if (!detail) return res.status(400).json({ error: "กรุณาระบุรายละเอียด" });
  await db.query("INSERT INTO issues (id, reporter_id, subject, detail) VALUES (?, ?, ?, ?)", [
    issueId,
    req.user.id,
    subject,
    detail,
  ]);
  return res.status(201).json({ id: issueId, ok: true });
}));

app.put("/api/admin/issues/:id/close", verifyToken("admin"), wrapRoute(async (req, res) => {
  const resolution = String((req.body && req.body.resolution) || "").trim();
  if (!resolution) return res.status(400).json({ error: "กรุณาระบุผลการแก้ไข" });
  const [updateOutcome] = await db.query("UPDATE issues SET closed = 1, resolution = ? WHERE id = ?", [
    resolution,
    req.params.id,
  ]);
  if (!updateOutcome || updateOutcome.affectedRows === 0) {
    return res.status(404).json({ error: "ไม่พบรายการแจ้งปัญหา" });
  }
  await recordAdminLog(
    req.user.id,
    req.user.username,
    "CLOSE_ISSUE",
    "issue",
    req.params.id,
    `[${req.params.id}] ${resolution}`
  );
  return res.json({ ok: true });
}));

app.delete("/api/admin/issues/:id", verifyToken("admin"), wrapRoute(async (req, res) => {
  const [deleteOutcome] = await db.query("DELETE FROM issues WHERE id = ?", [req.params.id]);
  if (!deleteOutcome || deleteOutcome.affectedRows === 0) {
    return res.status(404).json({ error: "ไม่พบรายการแจ้งปัญหา" });
  }
  await db.query("DELETE FROM admin_logs WHERE target_type = 'issue' AND details LIKE ?", [
    `[${req.params.id}]%`,
  ]);
  return res.json({ ok: true });
}));

app.get("/api/admin/logs", verifyToken("admin"), wrapRoute(async (_req, res) => {
  const [rows] = await db.query("SELECT * FROM admin_logs ORDER BY log_id DESC LIMIT 200");
  return res.json(rows);
}));

const port = Number(process.env.PORT || 3001);
if (require.main === module) {
  app.listen(port, "0.0.0.0", () => {
    console.log("Server is running at " + port);
  });
}

module.exports = app;
