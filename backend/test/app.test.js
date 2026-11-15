const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const jwt = require("jsonwebtoken");
const {
  JWT_SECRET,
  hashPassword,
  verifyPassword,
  normalizeRoleForApp,
  normalizeRoleForDb,
  signToken,
} = require("../auth_security");

test("1. Password hashing and verification works with Argon2 and SHA-256 legacy hashes", () => {
  const hashed = hashPassword("secret1234");
  assert.equal(verifyPassword(hashed, "secret1234"), true);
  assert.equal(verifyPassword(hashed, "wrongpass"), false);

  const legacySha256 = "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8";
  assert.equal(verifyPassword(legacySha256, "password"), true);
  assert.equal(verifyPassword(legacySha256, "123456"), false);
});

test("2. Role normalization maps rent-space-db customer <-> Flutter renter", () => {
  assert.equal(normalizeRoleForApp("customer"), "renter");
  assert.equal(normalizeRoleForApp("owner"), "owner");
  assert.equal(normalizeRoleForApp("admin"), "admin");

  assert.equal(normalizeRoleForDb("renter"), "customer");
  assert.equal(normalizeRoleForDb("owner"), "owner");
});

test("3. JWT token signing contains user_id, username, and mapped role", () => {
  const token = signToken({
    user_id: 1002,
    username: "renter01",
    email: "renter01@rentspace.test",
    role: "customer",
  });
  const decoded = jwt.verify(token, JWT_SECRET);
  assert.equal(decoded.id, 1002);
  assert.equal(decoded.username, "renter01");
  assert.equal(decoded.role, "renter");
  assert.equal(decoded.dbRole, "customer");
});

test("4. Live HTTP + MySQL integration: Login -> /api/state -> /api/spaces", async (t) => {
  const app = require("../app");
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });
  t.after(() => {
    server.close();
  });

  const baseUrl = `http://127.0.0.1:${server.address().port}/api`;

  const healthRes = await fetch(`${baseUrl}/health`);
  assert.equal(healthRes.status, 200);
  const healthJson = await healthRes.json();
  assert.equal(healthJson.database, "rent_space");

  const loginRes = await fetch(`${baseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "owner01@rentspace.test", password: "password" }),
  });
  assert.equal(loginRes.status, 200);
  const loginJson = await loginRes.json();
  assert.ok(loginJson.token);
  assert.equal(loginJson.role, "owner");

  const stateRes = await fetch(`${baseUrl}/state`, {
    headers: { Authorization: `Bearer ${loginJson.token}` },
  });
  assert.equal(stateRes.status, 200);
  const stateJson = await stateRes.json();
  assert.ok(Array.isArray(stateJson.users));
  assert.ok(Array.isArray(stateJson.spaces));
  assert.ok(Array.isArray(stateJson.bookings));
  assert.equal(stateJson.userId, "1001");
});

test("5. Live HTTP + MySQL integration: Admin multipart payout slip upload & /api/state hydration", async (t) => {
  const app = require("../app");
  const con = require("../db_config");
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });

  let originalBooking = null;
  let uploadedFilePath = null;

  t.after(async () => {
    if (originalBooking) {
      await con
        .promise()
        .query(
          `UPDATE bookings
           SET paid_out_at = ?, payout_slip_name = ?, payout_slip_url = ?, payout_slip_data = ?, payout_note = ?
           WHERE booking_id = ?`,
          [
            originalBooking.paid_out_at,
            originalBooking.payout_slip_name,
            originalBooking.payout_slip_url,
            originalBooking.payout_slip_data,
            originalBooking.payout_note,
            originalBooking.booking_id,
          ]
        );
      await con
        .promise()
        .query(
          "DELETE FROM admin_logs WHERE action = 'PAYOUT_OWNER' AND target_id = ? AND details LIKE '%admin_payout_test.png%'",
          [String(originalBooking.booking_id)]
        );
    }
    if (uploadedFilePath && fs.existsSync(uploadedFilePath)) {
      fs.unlinkSync(uploadedFilePath);
    }
    server.close();
  });

  const hostUrl = `http://127.0.0.1:${server.address().port}`;
  const baseUrl = `${hostUrl}/api`;

  const [bookingRows] = await con
    .promise()
    .query(
      "SELECT booking_id, paid_out_at, payout_slip_name, payout_slip_url, payout_slip_data, payout_note FROM bookings LIMIT 1"
    );
  assert.ok(bookingRows.length > 0, "Expected at least one booking in rent_space");
  originalBooking = bookingRows[0];
  const bookingId = String(originalBooking.booking_id);

  const adminLoginRes = await fetch(`${baseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "admin01@rentspace.test", password: "password" }),
  });
  assert.equal(adminLoginRes.status, 200);
  const adminLoginJson = await adminLoginRes.json();
  assert.equal(adminLoginJson.role, "admin");

  const badForm = new FormData();
  badForm.append("file", new Blob([Buffer.from("not-an-image")], { type: "image/png" }), "bad.png");
  const badRes = await fetch(`${baseUrl}/payments/${bookingId}/payout`, {
    method: "POST",
    headers: { Authorization: `Bearer ${adminLoginJson.token}` },
    body: badForm,
  });
  assert.equal(badRes.status, 400);

  const pngBuffer = Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=",
    "base64"
  );
  const validForm = new FormData();
  validForm.append("note", "REF-TEST-991");
  validForm.append("file", new Blob([pngBuffer], { type: "image/png" }), "admin_payout_test.png");

  const payoutRes = await fetch(`${baseUrl}/payments/${bookingId}/payout`, {
    method: "POST",
    headers: { Authorization: `Bearer ${adminLoginJson.token}` },
    body: validForm,
  });
  assert.equal(payoutRes.status, 200);
  const payoutJson = await payoutRes.json();
  assert.equal(payoutJson.ok, true);
  assert.ok(payoutJson.payout_slip_url.startsWith(`/uploads/payout_${bookingId}_`));

  uploadedFilePath = path.join(__dirname, "..", "uploads", path.basename(payoutJson.payout_slip_url));
  assert.equal(fs.existsSync(uploadedFilePath), true);

  const staticSlipRes = await fetch(`${hostUrl}${payoutJson.payout_slip_url}`);
  assert.equal(staticSlipRes.status, 200);

  const ownerLoginRes = await fetch(`${baseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email: "owner01@rentspace.test", password: "password" }),
  });
  const ownerLoginJson = await ownerLoginRes.json();
  const stateRes = await fetch(`${baseUrl}/state`, {
    headers: { Authorization: `Bearer ${ownerLoginJson.token}` },
  });
  assert.equal(stateRes.status, 200);
  const stateJson = await stateRes.json();
  const updatedBooking = stateJson.bookings.find((b) => String(b.id) === bookingId);
  assert.ok(updatedBooking);
  assert.ok(updatedBooking.paid_out_at);
  assert.equal(updatedBooking.payout_slip_name, "admin_payout_test.png");
  assert.equal(updatedBooking.payout_slip_url, payoutJson.payout_slip_url);
  assert.equal(updatedBooking.payout_note, "REF-TEST-991");
  assert.ok(updatedBooking.payout_slip_data.length > 10);
});

test.after(async () => {
  const con = require("../db_config");
  await con.promise().end();
});

