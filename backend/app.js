const fs = require("node:fs");
const path = require("node:path");
const express = require("express");
const cors = require("cors");
const multer = require("multer");
const con = require("./db_config");
const {
  hashPassword,
  verifyPassword,
  normalizeRoleForApp,
  normalizeRoleForDb,
  signToken,
  verifyToken,
} = require("./auth_security");
const { DEFAULT_WEEK_HOURS, ensureSchema } = require("./schema_bootstrap");
const { toIsoDate, buildSnapshot } = require("./snapshot_builder");

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

app.use(cors());
app.use(express.json({ limit: "15mb" }));
app.use("/uploads", express.static(uploadsDir));
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
    console.warn("Schema auto-check warning:", err.message);
  }
  next();
});

async function recordAdminLog(actorId, actorName, action, targetType, targetId, details) {
  await db.query(
    `INSERT INTO admin_logs (admin_id, admin_name, action, target_type, target_id, details)
     VALUES (?, ?, ?, ?, ?, ?)`,
    [Number(actorId) || 1003, actorName || "ผู้ดูแลระบบ", action, targetType, Number(targetId) || 0, details]
  );
}

//=================== 1. Health, Password & State Routes =======================

app.get("/api/health", async (_req, res) => {
  try {
    const [rows] = await db.query("SELECT DATABASE() AS database_name");
    return res.json({ ok: true, database: rows[0].database_name });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.get("/api/password/:raw", (req, res) => {
  return res.send(hashPassword(req.params.raw));
});

app.get("/api/state", verifyToken(), async (req, res) => {
  try {
    const [users] = await db.query("SELECT * FROM users WHERE user_id = ?", [req.user.id]);
    if (users.length === 0 || users[0].status === "suspended" || users[0].role === "disabled") {
      return res.status(401).json({ error: "บัญชีถูกระงับหรือไม่พบบัญชี" });
    }
    const snapshot = await buildSnapshot(db, req.user.id);
    return res.json(snapshot);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

//=================== 2. Auth Routes (Week 11 Lab + Flutter + rent-space-db) ===

async function handleLogin(req, res) {
  try {
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
    return res.json({
      token,
      id: String(account.user_id),
      username: account.username,
      name: account.name,
      email: account.email,
      role: normalizeRoleForApp(account.role),
      user: {
        user_id: account.user_id,
        id: String(account.user_id),
        name: account.name,
        username: account.username,
        email: account.email,
        role: normalizeRoleForApp(account.role),
      },
    });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

app.post("/api/login", handleLogin);
app.post("/api/auth/login", handleLogin);

async function handleRegister(req, res) {
  try {
    const name = String(req.body.name || req.body.username || "").trim();
    const email = String(req.body.email || "").trim();
    const rawUsername = String(req.body.username || email.split("@")[0] || "").trim();
    const password = String(req.body.password || "");
    const phone = String(req.body.phone || "").trim();
    const dbRole = normalizeRoleForDb(req.body.role);

    if (!name || !email || password.length < 8) {
      return res.status(400).json({ error: "กรุณากรอกชื่อ อีเมล และรหัสผ่านอย่างน้อย 8 ตัวอักษร" });
    }
    if (dbRole === "admin") {
      return res.status(403).json({ error: "ไม่สามารถสมัครบัญชี Admin" });
    }
    const [dup] = await db.query("SELECT user_id FROM users WHERE email = ? LIMIT 1", [email]);
    if (dup.length > 0) {
      return res.status(409).json({ error: "อีเมลนี้ถูกใช้งานแล้ว" });
    }
    const uniqueUsername = `${rawUsername}_${Date.now().toString().slice(-4)}`.slice(0, 50);
    const hashed = hashPassword(password);
    const [ins] = await db.query(
      `INSERT INTO users (name, username, email, phone, password_hash, role, status)
       VALUES (?, ?, ?, ?, ?, ?, 'active')`,
      [name, uniqueUsername, email, phone, hashed, dbRole]
    );
    const [createdRows] = await db.query("SELECT * FROM users WHERE user_id = ?", [ins.insertId]);
    const token = signToken(createdRows[0]);
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
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
}

app.post("/api/register", handleRegister);
app.post("/api/auth/register", handleRegister);

app.get("/api/auth/me", verifyToken(), async (req, res) => {
  try {
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
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/auth/logout", verifyToken(), (_req, res) => {
  return res.json({ ok: true });
});

app.put("/api/auth/profile", verifyToken(), async (req, res) => {
  try {
    const name = String(req.body.name || "").trim();
    const email = String(req.body.email || "").trim();
    const phone = String(req.body.phone || "").trim();
    const bankInfo = req.body.bankInfo != null ? String(req.body.bankInfo).trim() : "";
    if (!name || !email) {
      return res.status(400).json({ error: "กรุณาระบุชื่อและอีเมล" });
    }
    await db.query(
      "UPDATE users SET name = ?, email = ?, phone = ?, bank_info = ? WHERE user_id = ?",
      [name, email, phone, bankInfo, req.user.id]
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/auth/password", verifyToken(), async (req, res) => {
  try {
    const { currentPassword, newPassword } = req.body;
    const [rows] = await db.query("SELECT * FROM users WHERE user_id = ?", [req.user.id]);
    if (rows.length === 0 || !verifyPassword(rows[0].password_hash, currentPassword)) {
      return res.status(400).json({ error: "รหัสผ่านปัจจุบันไม่ถูกต้อง" });
    }
    await db.query("UPDATE users SET password_hash = ? WHERE user_id = ?", [
      hashPassword(newPassword),
      req.user.id,
    ]);
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

//=================== 3. Spaces & Availability Routes ==========================

app.get("/api/spaces", async (_req, res) => {
  try {
    const [rows] = await db.query("SELECT * FROM spaces ORDER BY space_id DESC");
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

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

app.post("/api/spaces", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    const title = String(req.body.name || req.body.title || "").trim();
    const category = String(req.body.category || "ห้องประชุม").trim();
    const location = String(req.body.location || "").trim();
    const price = Number(req.body.price || req.body.price_per_day || 0);
    const capacity = Number(req.body.capacity || 10);
    const description = String(req.body.description || "").trim();
    const imageUrl = String(req.body.image || req.body.image_url || "").trim();
    const amenities = Array.isArray(req.body.amenities) ? req.body.amenities : [];
    const hoursJson = req.body.hours ? JSON.stringify(req.body.hours) : DEFAULT_WEEK_HOURS;

    if (!title || !location || price <= 0) {
      return res.status(400).json({ error: "กรอกข้อมูลพื้นที่และราคาให้ครบถ้วน" });
    }
    const [ins] = await db.query(
      `INSERT INTO spaces (owner_id, title, description, location, price_per_day, category, capacity, image_url, hours_json, amenities_json, status)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending')`,
      [
        req.user.id,
        title,
        description,
        location,
        price,
        category,
        capacity,
        imageUrl,
        hoursJson,
        JSON.stringify(amenities),
      ]
    );
    await syncSpaceAmenities(ins.insertId, amenities);
    return res.status(201).json({ id: String(ins.insertId), space_id: ins.insertId, status: "pending" });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/spaces/:id", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    const spaceId = req.params.id;
    const title = String(req.body.name || req.body.title || "").trim();
    const category = String(req.body.category || "ห้องประชุม").trim();
    const location = String(req.body.location || "").trim();
    const price = Number(req.body.price || req.body.price_per_day || 0);
    const capacity = Number(req.body.capacity || 10);
    const description = String(req.body.description || "").trim();
    const imageUrl = String(req.body.image || req.body.image_url || "").trim();
    const amenities = Array.isArray(req.body.amenities) ? req.body.amenities : [];
    const hoursJson = req.body.hours ? JSON.stringify(req.body.hours) : DEFAULT_WEEK_HOURS;

    const requireModeration = req.user.role !== "admin";
    await db.query(
      `UPDATE spaces
       SET title = ?, category = ?, location = ?, price_per_day = ?, capacity = ?, description = ?, image_url = ?, hours_json = ?, amenities_json = ?${requireModeration ? ", status = 'pending', review_reason = ''" : ""}
       WHERE space_id = ?`,
      [title, category, location, price, capacity, description, imageUrl, hoursJson, JSON.stringify(amenities), spaceId]
    );
    await syncSpaceAmenities(spaceId, amenities);
    return res.json({ id: String(spaceId), ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/spaces/:id/availability", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    const spaceId = req.params.id;
    const days = Array.isArray(req.body.days) ? req.body.days : JSON.parse(DEFAULT_WEEK_HOURS);
    const blocks = Array.isArray(req.body.blocks) ? req.body.blocks : [];

    await db.query("UPDATE spaces SET hours_json = ? WHERE space_id = ?", [JSON.stringify(days), spaceId]);
    await db.query("DELETE FROM room_blocks WHERE space_id = ?", [spaceId]);

    for (const block of blocks) {
      const startDt = new Date(block.start);
      const endDt = new Date(block.end);
      const startDateStr = toIsoDate(startDt);
      const endDateObj = new Date(endDt.getTime() + 86400000);
      const endDateStr = toIsoDate(endDateObj);
      await db.query(
        `INSERT INTO room_blocks (space_id, created_by, start_date, end_date, start_at, end_at, reason)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [spaceId, req.user.id, startDateStr, endDateStr, startDt, endDt, block.reason || "ปิดห้อง"]
      );
    }
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/spaces/:id/favorite", verifyToken(), async (req, res) => {
  try {
    const spaceId = req.params.id;
    const [existing] = await db.query(
      "SELECT 1 FROM user_favorites WHERE user_id = ? AND space_id = ?",
      [req.user.id, spaceId]
    );
    if (existing.length > 0) {
      await db.query("DELETE FROM user_favorites WHERE user_id = ? AND space_id = ?", [req.user.id, spaceId]);
    } else {
      await db.query("INSERT INTO user_favorites (user_id, space_id) VALUES (?, ?)", [req.user.id, spaceId]);
    }
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.get("/api/spaces/:spaceId/availability", async (req, res) => {
  try {
    const spaceId = req.params.spaceId;
    const [bookings] = await db.query(
      "SELECT booking_id, start_date, end_date, start_time, end_time, status FROM bookings WHERE space_id = ? AND status IN ('pending','approved','confirmed')",
      [spaceId]
    );
    const [blocks] = await db.query("SELECT * FROM room_blocks WHERE space_id = ?", [spaceId]);
    return res.json({ bookings, blocks });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

//=================== 4. Bookings Routes =======================================

app.get("/api/bookings", verifyToken(), async (req, res) => {
  try {
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
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings", verifyToken(), async (req, res) => {
  try {
    const spaceId = req.body.spaceId || req.body.space_id;
    const startDate = String(req.body.date || req.body.start_date || "").substring(0, 10);
    const days = Math.max(1, Number(req.body.days || 1));
    const startMinutes = req.body.startMinutes != null ? Number(req.body.startMinutes) : 540;
    const endMinutes = req.body.endMinutes != null ? Number(req.body.endMinutes) : 660;
    const attendees = Math.max(1, Number(req.body.attendees || 1));
    const zone = String(req.body.zone || "โซนหลัก (พื้นที่มาตรฐาน)").trim();
    const renterNote = String(req.body.renterNote || "").trim();

    const [spaceRows] = await db.query("SELECT * FROM spaces WHERE space_id = ?", [spaceId]);
    if (spaceRows.length === 0) {
      return res.status(404).json({ error: "ไม่พบพื้นที่" });
    }
    const space = spaceRows[0];
    const hours = Math.max(1, Math.ceil((endMinutes - startMinutes) / 60));
    const totalPrice = Math.round(Number(space.price_per_day || 350)) * hours * days;
    const platformFee = Math.round(totalPrice * 0.05);

    const endDateObj = new Date(`${startDate}T00:00:00`);
    endDateObj.setDate(endDateObj.getDate() + (days - 1));
    const endDate = req.body.end_date || toIsoDate(endDateObj);

    const startTimeStr = `${startDate} ${String(Math.floor(startMinutes / 60)).padStart(2, "0")}:${String(
      startMinutes % 60
    ).padStart(2, "0")}:00`;
    const endTimeStr = `${endDate} ${String(Math.floor(endMinutes / 60)).padStart(2, "0")}:${String(
      endMinutes % 60
    ).padStart(2, "0")}:00`;

    const [ins] = await db.query(
      `INSERT INTO bookings (space_id, customer_id, start_date, end_date, start_time, end_time, total_price, status, is_paid, start_minutes, end_minutes, days_count, attendees, zone, renter_note, platform_fee, app_status)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?, ?, ?, 'ownerReview')`,
      [
        spaceId,
        req.user.id,
        startDate,
        endDate,
        startTimeStr,
        endTimeStr,
        totalPrice,
        startMinutes,
        endMinutes,
        days,
        attendees,
        zone,
        renterNote,
        platformFee,
      ]
    );
    return res.status(201).json({ id: String(ins.insertId), booking_id: ins.insertId });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings/:id/approve", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    await db.query(
      "UPDATE bookings SET status = 'approved', app_status = 'paymentDue', approved_at = NOW(), reason = ?, reason_kind = 'none' WHERE booking_id = ?",
      [String(req.body.reason || "").trim(), req.params.id]
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings/:id/reject", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    const reason = String(req.body.reason || "").trim();
    await db.query(
      "UPDATE bookings SET status = 'rejected', app_status = 'ownerRejected', reason = ?, reason_kind = 'ownerRejected' WHERE booking_id = ?",
      [reason, req.params.id]
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings/:id/cancel", verifyToken(), async (req, res) => {
  try {
    const reason = String(req.body.reason || "").trim();
    await db.query(
      "UPDATE bookings SET status = 'cancelled', app_status = 'canceled', reason = ?, reason_kind = 'canceledByUser' WHERE booking_id = ?",
      [reason, req.params.id]
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings/:id/complete", verifyToken(), async (req, res) => {
  try {
    await db.query(
      "UPDATE bookings SET status = 'completed', app_status = 'completed', completed_at = NOW() WHERE booking_id = ?",
      [req.params.id]
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/bookings/:id/review", verifyToken(), async (req, res) => {
  try {
    const bookingId = req.params.id;
    const rating = Math.min(5, Math.max(1, Number(req.body.rating || 5)));
    const comment = String(req.body.comment || req.body.review_comment || "").trim();

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
    return res.status(201).json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

//=================== 5. Payments Routes =======================================

app.post("/api/payments/:id/slip", verifyToken(), upload.single("file"), async (req, res) => {
  try {
    const bookingId = req.params.id;
    const note = String(req.body.note || "").trim();
    const file = req.file;
    if (!file) {
      return res.status(400).json({ error: "กรุณาแนบไฟล์สลิป" });
    }
    const ext = path.extname(file.originalname || ".jpg") || ".jpg";
    const storedName = `slip_${bookingId}_${Date.now()}${ext}`;
    fs.writeFileSync(path.join(uploadsDir, storedName), file.buffer);

    const imageUrl = `/uploads/${storedName}`;
    const base64Data = file.buffer.toString("base64");
    const [bRows] = await db.query("SELECT total_price FROM bookings WHERE booking_id = ?", [bookingId]);
    const amount = bRows.length > 0 && bRows[0].total_price ? bRows[0].total_price : 500;

    await db.query(
      `INSERT INTO payments (booking_id, amount, payment_method, status, transaction_ref, slip_image_url, paid_at, file_name, note, image_data)
       VALUES (?, ?, 'bank_transfer', 'submitted', ?, ?, NOW(), ?, ?, ?)`,
      [bookingId, amount, `SLIP-${bookingId}`, imageUrl, file.originalname || storedName, note, base64Data]
    );
    await db.query("UPDATE bookings SET app_status = 'slipReview', slip_image_url = ? WHERE booking_id = ?", [
      imageUrl,
      bookingId,
    ]);
    return res.status(201).json({ ok: true, image_url: imageUrl });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/payments/:id/review", verifyToken(["owner", "admin"]), async (req, res) => {
  try {
    const bookingId = req.params.id;
    const approve = Boolean(req.body.approve);
    const reason = String(req.body.reason || "").trim();

    if (approve) {
      await db.query(
        "UPDATE bookings SET status = 'confirmed', app_status = 'confirmed', is_paid = 1, confirmed_at = NOW(), reason = '', reason_kind = 'none' WHERE booking_id = ?",
        [bookingId]
      );
      await db.query("UPDATE payments SET status = 'verified' WHERE booking_id = ?", [bookingId]);
    } else {
      await db.query(
        "UPDATE bookings SET app_status = 'slipRejected', slip_rejected_at = NOW(), reason = ?, reason_kind = 'slipRejected' WHERE booking_id = ?",
        [reason, bookingId]
      );
      await db.query("UPDATE payments SET status = 'rejected', rejection_reason = ? WHERE booking_id = ?", [
        reason,
        bookingId,
      ]);
    }
    await recordAdminLog(
      req.user.id,
      req.user.username,
      "REVIEW_PAYMENT",
      "booking",
      bookingId,
      approve ? "อนุมัติสลิป" : `ปฏิเสธสลิป: ${reason}`
    );
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

function resolveValidatedSlipExtension(uploadedFile) {
  const buf = uploadedFile.buffer;
  const rawExt = path.extname(uploadedFile.originalname || "").toLowerCase();
  const isPng =
    buf &&
    buf.length >= 8 &&
    buf[0] === 137 &&
    buf[1] === 80 &&
    buf[2] === 78 &&
    buf[3] === 71;
  const isJpg =
    buf &&
    buf.length >= 3 &&
    buf[0] === 255 &&
    buf[1] === 216 &&
    buf[2] === 255;
  if (rawExt === ".png" && isPng) return ".png";
  if ((rawExt === ".jpg" || rawExt === ".jpeg") && isJpg) return rawExt;
  return null;
}

app.post(
  "/api/payments/:id/payout",
  verifyToken(["admin", "owner"]),
  upload.single("file"),
  async (req, res) => {
    try {
      const bookingId = req.params.id;
      const payoutNote = String((req.body && req.body.note) || "").trim();
      const uploadedFile = req.file || null;
      let payoutSlipName = null;
      let payoutSlipUrl = null;
      let payoutSlipData = null;

      if (uploadedFile) {
        const ext = resolveValidatedSlipExtension(uploadedFile);
        if (!ext) {
          return res.status(400).json({ error: "รองรับภาพ JPG และ PNG เท่านั้น" });
        }
        const storedName = `payout_${bookingId}_${Date.now()}${ext}`;
        fs.writeFileSync(path.join(uploadsDir, storedName), uploadedFile.buffer);
        payoutSlipUrl = `/uploads/${storedName}`;
        payoutSlipName = path.basename(uploadedFile.originalname || storedName);
        payoutSlipData = uploadedFile.buffer.toString("base64");
      }

      await db.query(
        `UPDATE bookings
         SET paid_out_at = NOW(),
             payout_slip_name = COALESCE(?, payout_slip_name),
             payout_slip_url = COALESCE(?, payout_slip_url),
             payout_slip_data = COALESCE(?, payout_slip_data),
             payout_note = ?
         WHERE booking_id = ?`,
        [payoutSlipName, payoutSlipUrl, payoutSlipData, payoutNote, bookingId]
      );
      const logDetail = payoutSlipName
        ? `โอนเงินให้เจ้าของพื้นที่ (สลิป ${payoutSlipName}${payoutNote ? `: ${payoutNote}` : ""})`
        : `โอนเงินให้เจ้าของพื้นที่${payoutNote ? `: ${payoutNote}` : ""}`;
      await recordAdminLog(req.user.id, req.user.username, "PAYOUT_OWNER", "booking", bookingId, logDetail);
      return res.json({ ok: true, payout_slip_url: payoutSlipUrl || "" });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }
);

//=================== 6. Admin & Issues Routes (Week 11 Lab + Flutter) =========

app.get("/api/admin/user", verifyToken("admin"), async (_req, res) => {
  try {
    const [rows] = await db.query("SELECT user_id AS id, username, role, status FROM users WHERE role <> 'admin'");
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.patch("/api/admin/role/:id", verifyToken("admin"), async (req, res) => {
  try {
    const newStatus = req.body.role === "disabled" ? "suspended" : "active";
    await db.query("UPDATE users SET status = ? WHERE user_id = ?", [newStatus, req.params.id]);
    return res.status(200).send("Role updated");
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/admin/users/:id/toggle", verifyToken("admin"), async (req, res) => {
  try {
    const userId = req.params.id;
    const [rows] = await db.query("SELECT status FROM users WHERE user_id = ?", [userId]);
    if (rows.length === 0) return res.status(404).json({ error: "ไม่พบผู้ใช้" });
    const nextStatus = rows[0].status === "suspended" ? "active" : "suspended";
    await db.query("UPDATE users SET status = ? WHERE user_id = ?", [nextStatus, userId]);
    await recordAdminLog(req.user.id, req.user.username, "TOGGLE_USER", "user", userId, `status -> ${nextStatus}`);
    return res.json({ ok: true, status: nextStatus });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/admin/spaces/:id/approve", verifyToken("admin"), async (req, res) => {
  try {
    await db.query("UPDATE spaces SET status = 'approved', review_reason = '' WHERE space_id = ?", [req.params.id]);
    await recordAdminLog(req.user.id, req.user.username, "APPROVE_SPACE", "space", req.params.id, "อนุมัติพื้นที่");
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/admin/spaces/:id/reject", verifyToken("admin"), async (req, res) => {
  try {
    const reason = String(req.body.reason || "").trim();
    await db.query("UPDATE spaces SET status = 'rejected', review_reason = ? WHERE space_id = ?", [
      reason,
      req.params.id,
    ]);
    await recordAdminLog(req.user.id, req.user.username, "REJECT_SPACE", "space", req.params.id, reason);
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/admin/spaces/:id/activate", verifyToken("admin"), async (req, res) => {
  try {
    await db.query("UPDATE spaces SET status = 'approved', review_reason = '' WHERE space_id = ?", [req.params.id]);
    await recordAdminLog(req.user.id, req.user.username, "ACTIVATE_SPACE", "space", req.params.id, "เปิดใช้งานพื้นที่อีกครั้ง");
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.post("/api/admin/issues", verifyToken(), async (req, res) => {
  try {
    const issueId = `iss_${Date.now()}`;
    const subject = String(req.body.subject || "แจ้งปัญหา").trim();
    const detail = String(req.body.detail || "").trim();
    await db.query("INSERT INTO issues (id, reporter_id, subject, detail) VALUES (?, ?, ?, ?)", [
      issueId,
      req.user.id,
      subject,
      detail,
    ]);
    return res.status(201).json({ id: issueId, ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.put("/api/admin/issues/:id/close", verifyToken("admin"), async (req, res) => {
  try {
    const resolution = String(req.body.resolution || "").trim();
    await db.query("UPDATE issues SET closed = 1, resolution = ? WHERE id = ?", [resolution, req.params.id]);
    await recordAdminLog(req.user.id, req.user.username, "CLOSE_ISSUE", "issue", 0, resolution);
    return res.json({ ok: true });
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

app.get("/api/admin/logs", verifyToken("admin"), async (_req, res) => {
  try {
    const [rows] = await db.query("SELECT * FROM admin_logs ORDER BY log_id DESC LIMIT 200");
    return res.json(rows);
  } catch (err) {
    return res.status(500).json({ error: err.message });
  }
});

const port = Number(process.env.PORT || 3001);
if (require.main === module) {
  app.listen(port, "0.0.0.0", () => {
    console.log("Server is running at " + port);
  });
}

module.exports = app;
