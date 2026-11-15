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
      `SELECT b.booking_id, b.paid_out_at, b.payout_slip_name, b.payout_slip_url, b.payout_slip_data, b.payout_note
       FROM bookings b
       JOIN spaces s ON s.space_id = b.space_id
       WHERE s.owner_id = 1001 AND (b.app_status = 'completed' OR b.status = 'completed')
       ORDER BY b.booking_id ASC
       LIMIT 1`
    );
  assert.ok(bookingRows.length > 0, "Expected at least one completed booking owned by user 1001");
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

async function loginForTest(baseUrl, email, password = "password") {
  const loginRes = await fetch(`${baseUrl}/auth/login`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  assert.equal(loginRes.status, 200);
  return loginRes.json();
}

test("6. Security guards block password oracle, weak passwords, IDOR mutations, invalid slips, and PII leaks", async (t) => {
  const app = require("../app");
  const con = require("../db_config");
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });

  let createdBookingId = null;
  let createdUserId = null;
  let firstSpaceId = null;

  t.after(async () => {
    const db = con.promise();
    if (createdBookingId) {
      await db.query("DELETE FROM payments WHERE booking_id = ?", [createdBookingId]);
      await db.query("DELETE FROM bookings WHERE booking_id = ?", [createdBookingId]);
    }
    if (createdUserId) {
      await db.query("DELETE FROM users WHERE user_id = ?", [createdUserId]);
    }
    server.close();
  });

  const baseUrl = `http://127.0.0.1:${server.address().port}/api`;
  const [spaceRows] = await con
    .promise()
    .query("SELECT space_id FROM spaces WHERE owner_id = 1001 AND status = 'approved' ORDER BY space_id ASC LIMIT 1");
  assert.ok(spaceRows.length > 0);
  firstSpaceId = String(spaceRows[0].space_id);

  const oracleRes = await fetch(`${baseUrl}/password/test1234`);
  assert.equal(oracleRes.status, 404);

  const ownerAuth = await loginForTest(baseUrl, "owner01@rentspace.test");
  const renterAuth = await loginForTest(baseUrl, "renter01@rentspace.test");
  const adminAuth = await loginForTest(baseUrl, "admin01@rentspace.test");

  const tempEmail = `sec_${Date.now()}@rentspace.test`;
  const registerRes = await fetch(`${baseUrl}/auth/register`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      name: "Security Verifier",
      email: tempEmail,
      password: "password123",
      role: "renter",
    }),
  });
  assert.equal(registerRes.status, 201);
  const strangerAuth = await registerRes.json();
  createdUserId = strangerAuth.id;

  const weakPwRes = await fetch(`${baseUrl}/auth/password`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${strangerAuth.token}`,
    },
    body: JSON.stringify({ currentPassword: "password123", newPassword: "123" }),
  });
  assert.equal(weakPwRes.status, 400);

  const spaceIdorRes = await fetch(`${baseUrl}/spaces/${firstSpaceId}`, {
    method: "PUT",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${strangerAuth.token}`,
    },
    body: JSON.stringify({ name: "Hijacked Space" }),
  });
  assert.equal(spaceIdorRes.status, 403);

  const createRes = await fetch(`${baseUrl}/bookings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${renterAuth.token}`,
    },
    body: JSON.stringify({
      spaceId: firstSpaceId,
      date: "2031-07-07",
      startMinutes: 540,
      endMinutes: 660,
      days: 1,
      attendees: 2,
    }),
  });
  assert.equal(createRes.status, 201);
  createdBookingId = (await createRes.json()).id;

  const selfApproveRes = await fetch(`${baseUrl}/bookings/${createdBookingId}/approve`, {
    method: "POST",
    headers: { Authorization: `Bearer ${renterAuth.token}` },
  });
  assert.equal(selfApproveRes.status, 403);

  const prematurePayoutRes = await fetch(`${baseUrl}/payments/${createdBookingId}/payout`, {
    method: "POST",
    headers: { Authorization: `Bearer ${adminAuth.token}` },
  });
  assert.equal(prematurePayoutRes.status, 409);

  const nonAdminPayoutRes = await fetch(`${baseUrl}/payments/${createdBookingId}/payout`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ownerAuth.token}` },
  });
  assert.equal(nonAdminPayoutRes.status, 403);

  const approveRes = await fetch(`${baseUrl}/bookings/${createdBookingId}/approve`, {
    method: "POST",
    headers: { Authorization: `Bearer ${ownerAuth.token}` },
  });
  assert.equal(approveRes.status, 200);

  const svgSlipForm = new FormData();
  svgSlipForm.append("file", new Blob([Buffer.from("<svg></svg>")], { type: "image/png" }), "evil.png");
  const badSlipRes = await fetch(`${baseUrl}/payments/${createdBookingId}/slip`, {
    method: "POST",
    headers: { Authorization: `Bearer ${renterAuth.token}` },
    body: svgSlipForm,
  });
  assert.equal(badSlipRes.status, 400);

  const strangerStateRes = await fetch(`${baseUrl}/state`, {
    headers: { Authorization: `Bearer ${strangerAuth.token}` },
  });
  assert.equal(strangerStateRes.status, 200);
  const strangerState = await strangerStateRes.json();
  const leakedRenter = strangerState.users.find((u) => u.id === "1002");
  assert.equal(leakedRenter.email, "");
  assert.equal(leakedRenter.phone, "");
  assert.equal(leakedRenter.bank_info, "");
  assert.equal(strangerState.bookings.some((b) => String(b.id) === String(createdBookingId)), false);
  assert.deepEqual(strangerState.logs, []);
  assert.equal(
    strangerState.busy.some((slot) => String(slot.space_id) === firstSpaceId && slot.booking_date === "2031-07-07"),
    true
  );
});

test("7. Transactional booking rejects overlaps, out-of-hours, excess capacity, and client end_date tampering", async (t) => {
  const app = require("../app");
  const con = require("../db_config");
  const { toIsoDate } = require("../snapshot_builder");
  const server = await new Promise((resolve) => {
    const s = app.listen(0, () => resolve(s));
  });

  let createdBookingId = null;

  t.after(async () => {
    if (createdBookingId) {
      await con.promise().query("DELETE FROM bookings WHERE booking_id = ?", [createdBookingId]);
    }
    server.close();
  });

  const baseUrl = `http://127.0.0.1:${server.address().port}/api`;
  const renterAuth = await loginForTest(baseUrl, "renter01@rentspace.test");
  const [spaceRows] = await con
    .promise()
    .query("SELECT space_id, capacity, price_per_day FROM spaces WHERE status = 'approved' ORDER BY space_id ASC LIMIT 1");
  assert.ok(spaceRows.length > 0);
  const targetSpace = spaceRows[0];

  const tamperedRes = await fetch(`${baseUrl}/bookings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${renterAuth.token}`,
    },
    body: JSON.stringify({
      spaceId: targetSpace.space_id,
      date: "2031-07-14",
      end_date: "2031-07-20",
      startMinutes: 540,
      endMinutes: 660,
      days: 1,
      attendees: 1,
    }),
  });
  assert.equal(tamperedRes.status, 201);
  createdBookingId = (await tamperedRes.json()).id;

  const [savedRows] = await con
    .promise()
    .query("SELECT end_date, total_price FROM bookings WHERE booking_id = ?", [createdBookingId]);
  assert.equal(toIsoDate(savedRows[0].end_date), "2031-07-14");
  assert.equal(Math.round(Number(savedRows[0].total_price)), Math.round(Number(targetSpace.price_per_day)) * 2);

  const overlapRes = await fetch(`${baseUrl}/bookings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${renterAuth.token}`,
    },
    body: JSON.stringify({
      spaceId: targetSpace.space_id,
      date: "2031-07-14",
      startMinutes: 600,
      endMinutes: 720,
      days: 1,
      attendees: 1,
    }),
  });
  assert.equal(overlapRes.status, 409);

  const offHoursRes = await fetch(`${baseUrl}/bookings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${renterAuth.token}`,
    },
    body: JSON.stringify({
      spaceId: targetSpace.space_id,
      date: "2031-07-15",
      startMinutes: 60,
      endMinutes: 120,
      days: 1,
      attendees: 1,
    }),
  });
  assert.equal(offHoursRes.status, 409);

  const overCapRes = await fetch(`${baseUrl}/bookings`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${renterAuth.token}`,
    },
    body: JSON.stringify({
      spaceId: targetSpace.space_id,
      date: "2031-07-16",
      startMinutes: 540,
      endMinutes: 660,
      days: 1,
      attendees: Number(targetSpace.capacity) + 50,
    }),
  });
  assert.equal(overCapRes.status, 400);
});

test.after(async () => {
  const con = require("../db_config");
  await con.promise().end();
});

