const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");
const {
  toIsoDate,
  buildThaiDate,
  getThaiDateParts,
  normalizeSpaceCategory,
  buildSnapshot,
} = require("../snapshot_builder");
const {
  hashPassword,
  verifyPassword,
  signToken,
  revokeToken,
  isTokenRevoked,
  recordSession,
  revokeSession,
  revokeOtherUserSessions,
  isSessionActive,
  isValidEmail,
  isValidPhone,
  buildUniqueUsername,
  verifyToken,
  createAuthRateLimiter,
} = require("../auth_security");
const {
  createBookingTransactional,
  computeBookingEndsAt,
  evaluateBookingLifecycleTransition,
  sweepExpiredBookings,
  submitPaymentSlipTransactional,
  applyGuardedBookingUpdate,
  reviewPaymentSlipTransactional,
  isValidHoursList,
  resolveSpaceMutationInput,
  toggleSpaceFavorite,
  deleteSpaceTransactional,
  formatClockTimestamp,
  hasBookingPermission,
  guardBookingAccess,
  guardSlipUploadAccess,
} = require("../booking_guards");

function createFixtureDatabase() {
  const tables = {
    users: [
      {
        user_id: 1001,
        name: "Owner One",
        username: "owner01",
        email: "owner01@rentspace.test",
        role: "owner",
        phone: "081-111-1111",
        bank_info: "KBANK 111-1-11111-1",
        status: "active",
      },
      {
        user_id: 1002,
        name: "Renter One",
        username: "renter01",
        email: "renter01@rentspace.test",
        role: "customer",
        phone: "082-222-2222",
        bank_info: "SCB 222-2-22222-2",
        status: "active",
      },
      {
        user_id: 1003,
        name: "Platform Admin",
        username: "admin01",
        email: "admin01@rentspace.test",
        role: "admin",
        phone: "083-333-3333",
        bank_info: "BBL 333-3-33333-3",
        status: "active",
      },
      {
        user_id: 1004,
        name: "Unrelated Stranger",
        username: "stranger01",
        email: "stranger01@rentspace.test",
        role: "customer",
        phone: "084-444-4444",
        bank_info: "KTB 444-4-44444-4",
        status: "active",
      },
    ],
    spaces: [
      {
        space_id: 2001,
        owner_id: 1001,
        title: "Studio Alpha",
        category: "สตูดิโอ",
        location: "อารีย์",
        price_per_day: 500,
        capacity: 10,
        status: "approved",
      },
      {
        space_id: 2002,
        owner_id: 1001,
        title: "Pending Loft",
        category: "สตูดิโอ",
        location: "พญาไท",
        price_per_day: 600,
        capacity: 12,
        status: "pending",
      },
      {
        space_id: 2003,
        owner_id: 1001,
        title: "Rejected Vault",
        category: "ห้องประชุม",
        location: "ลาดพร้าว",
        price_per_day: 400,
        capacity: 8,
        status: "rejected",
        review_reason: "Private rejection note",
      },
    ],
    bookings: [
      {
        booking_id: 3001,
        space_id: 2001,
        customer_id: 1002,
        start_date: "2027-05-10",
        start_minutes: 540,
        end_minutes: 660,
        days_count: 1,
        total_price: 1000,
        app_status: "confirmed",
        payout_slip_name: "payout_secret.png",
        payout_slip_url: "/uploads/payout_3001.png",
      },
      {
        booking_id: 3002,
        space_id: 2001,
        customer_id: 1004,
        start_date: "2027-05-11",
        start_minutes: 600,
        end_minutes: 720,
        days_count: 1,
        total_price: 1000,
        app_status: "paymentDue",
        renter_note: "Secret door code 9999",
      },
    ],
    payments: [
      { payment_id: 4001, booking_id: 3001, file_name: "slip_3001.png", slip_image_url: "/uploads/slip_3001.png" },
      { payment_id: 4002, booking_id: 3002, file_name: "slip_3002.png", slip_image_url: "/uploads/slip_3002.png" },
    ],
    reviews: [
      {
        review_id: 6001,
        booking_id: 3999,
        space_id: 2005,
        rating: 5,
        review_comment: "Quiet room",
        created_at: "2027-05-11T10:00:00Z",
      },
    ],
    issues: [
      { id: "iss-1", reporter_id: 1002, subject: "Renter issue", detail: "Wi-Fi slow", closed: 0 },
      { id: "iss-2", reporter_id: 1004, subject: "Stranger private dispute", detail: "Confidential", closed: 0 },
    ],
    logs: [
      { log_id: 1, admin_name: "admin01", action: "PAYOUT_OWNER", details: "Transferred 950 THB", created_at: "2027-05-10T12:00:00Z" },
    ],
  };

  const executedQueries = [];
  const spaceOwnerById = new Map(tables.spaces.map((spaceRow) => [spaceRow.space_id, spaceRow.owner_id]));

  const isBookingOwnedOrBookedBy = (bookingRow, actorId) =>
    String(bookingRow.customer_id) === String(actorId) ||
    String(spaceOwnerById.get(bookingRow.space_id)) === String(actorId);

  return {
    executedQueries,
    async query(sqlText, queryParams = []) {
      executedQueries.push({ sqlText, queryParams });
      if (sqlText.includes("FROM users")) return [tables.users];
      if (sqlText.includes("FROM spaces")) return [tables.spaces];
      if (sqlText.includes("FROM room_blocks")) return [[]];
      if (sqlText.includes("FROM payments")) {
        if (sqlText.includes("WHERE b.customer_id = ? OR s.owner_id = ?")) {
          const allowedBookingIds = new Set(
            tables.bookings
              .filter((bookingRow) => isBookingOwnedOrBookedBy(bookingRow, queryParams[0]))
              .map((bookingRow) => bookingRow.booking_id)
          );
          return [tables.payments.filter((paymentRow) => allowedBookingIds.has(paymentRow.booking_id))];
        }
        return [tables.payments];
      }
      if (sqlText.includes("FROM reviews")) return [tables.reviews];
      if (sqlText.includes("FROM user_favorites")) return [[]];
      if (sqlText.includes("FROM issues")) {
        if (sqlText.includes("WHERE reporter_id = ?")) {
          return [tables.issues.filter((issueRow) => String(issueRow.reporter_id) === String(queryParams[0]))];
        }
        return [tables.issues];
      }
      if (sqlText.includes("FROM admin_logs")) return [tables.logs];
      if (sqlText.includes("FROM space_amenities")) return [[]];
      if (sqlText.includes("FROM bookings")) {
        if (sqlText.includes("WHERE b.customer_id = ? OR s.owner_id = ?")) {
          return [tables.bookings.filter((bookingRow) => isBookingOwnedOrBookedBy(bookingRow, queryParams[0]))];
        }
        return [tables.bookings];
      }
      throw new Error(`Unexpected SQL in fixture: ${sqlText}`);
    },
  };
}

test("1. Snapshot hides unrelated PII, restricts bookings/slips/issues/logs, yet preserves counterparty phone and busy slots", async () => {
  const fixtureDb = createFixtureDatabase();
  const snapshot = await buildSnapshot(fixtureDb, "1002");

  const selfUser = snapshot.users.find((u) => u.id === "1002");
  const pairedOwner = snapshot.users.find((u) => u.id === "1001");
  const unrelatedUser = snapshot.users.find((u) => u.id === "1004");
  const adminUser = snapshot.users.find((u) => u.id === "1003");

  assert.equal(selfUser.email, "renter01@rentspace.test");
  assert.equal(selfUser.bank_info, "SCB 222-2-22222-2");
  assert.equal(selfUser.phone, "082-222-2222");

  // Paired owner on booking 3001 keeps phone for coordination, hides email & bank_info
  assert.equal(pairedOwner.email, "");
  assert.equal(pairedOwner.bank_info, "");
  assert.equal(pairedOwner.phone, "081-111-1111");

  // Unrelated users have all private PII blanked
  assert.equal(unrelatedUser.email, "");
  assert.equal(unrelatedUser.bank_info, "");
  assert.equal(unrelatedUser.phone, "");
  assert.equal(adminUser.email, "");
  assert.equal(adminUser.phone, "");

  assert.deepEqual(snapshot.bookings.map((b) => b.id), ["3001"]);
  assert.deepEqual(snapshot.slips.map((s) => s.id), ["4001"]);
  assert.deepEqual(snapshot.issues.map((i) => i.id), ["iss-1"]);
  assert.deepEqual(snapshot.logs, []);
  assert.equal(snapshot.reviews.length, 1);
  assert.equal(snapshot.reviews[0].space_id, "2005");
  assert.deepEqual(snapshot.spaces.map((s) => s.id), ["2001"]);
  assert.equal(snapshot.spaces[0].review_reason, "");
  assert.equal(normalizeSpaceCategory("meeting_room"), "ห้องประชุม");
  assert.equal(normalizeSpaceCategory("study_room"), "Co-working");
  assert.equal(normalizeSpaceCategory("event_space"), "พื้นที่อีเวนต์");
  assert.equal(normalizeSpaceCategory("สตูดิโอ"), "สตูดิโอ");

  const ownerSnapshot = await buildSnapshot(fixtureDb, "1001");
  assert.deepEqual(ownerSnapshot.spaces.map((s) => s.id), ["2001", "2002", "2003"]);
  assert.equal(
    ownerSnapshot.spaces.find((s) => s.id === "2003").review_reason,
    "Private rejection note"
  );

  // Busy slots still include all active bookings across users to block double-booking
  assert.equal(snapshot.busy.length, 2);

  const sqlStatements = fixtureDb.executedQueries.map((entry) => entry.sqlText);
  assert.equal(
    sqlStatements.some(
      (sql) => sql.includes("FROM bookings b") && sql.includes("WHERE b.customer_id = ? OR s.owner_id = ?")
    ),
    true
  );
  assert.equal(
    sqlStatements.some(
      (sql) => sql.includes("FROM payments p") && sql.includes("WHERE b.customer_id = ? OR s.owner_id = ?")
    ),
    true
  );
  assert.equal(
    sqlStatements.some((sql) => sql.includes("FROM issues WHERE reporter_id = ?")),
    true
  );
  assert.equal(
    sqlStatements.some(
      (sql) =>
        sql.includes("FROM bookings") &&
        !sql.includes("SELECT b.*") &&
        !sql.includes("payout_slip_data")
    ),
    true
  );
  assert.equal(
    sqlStatements.some((sql) => sql.includes("FROM admin_logs")),
    false
  );
});

test("2. Admin snapshot receives full users, bookings, slips, issues, and audit logs", async () => {
  const fixtureDb = createFixtureDatabase();
  const snapshot = await buildSnapshot(fixtureDb, "1003");

  const unrelatedUser = snapshot.users.find((u) => u.id === "1004");
  assert.equal(unrelatedUser.email, "stranger01@rentspace.test");
  assert.equal(unrelatedUser.phone, "084-444-4444");
  assert.equal(unrelatedUser.bank_info, "KTB 444-4-44444-4");
  assert.equal(snapshot.bookings.length, 2);
  assert.equal(snapshot.slips.length, 2);
  assert.equal(snapshot.issues.length, 2);
  assert.equal(snapshot.logs.length, 1);
  assert.deepEqual(snapshot.spaces.map((s) => s.id), ["2001", "2002", "2003"]);
  assert.equal(
    snapshot.spaces.find((s) => s.id === "2003").review_reason,
    "Private rejection note"
  );
  assert.equal(
    fixtureDb.executedQueries.some((entry) => entry.sqlText.includes("FROM admin_logs")),
    true
  );
});

function pruneExpiredMockSessions(sessionStore, nowSeconds) {
  for (const [hashKey, entry] of sessionStore.entries()) {
    if (entry.expiresAt <= nowSeconds) {
      sessionStore.delete(hashKey);
    }
  }
  return [{ affectedRows: 0 }];
}

function upsertMockSession(sessionStore, params, allocateId) {
  const [userId, tokenHash, expiresAtEpoch] = params;
  const existing = sessionStore.get(tokenHash);
  const sessionId = existing ? existing.sessionId : allocateId();
  sessionStore.set(tokenHash, {
    sessionId,
    userId,
    tokenHash,
    expiresAt: Number(expiresAtEpoch),
  });
  return [{ insertId: sessionId }];
}

function queryActiveMockSession(sessionStore, params, nowSeconds) {
  const [userId, tokenHash] = params;
  const entry = sessionStore.get(tokenHash);
  const active = Boolean(entry && entry.userId === userId && entry.expiresAt > nowSeconds);
  return [active ? [{ session_id: entry.sessionId }] : []];
}

function deleteMockSessions(sessionStore, sql, params) {
  if (sql.includes("AND token_hash <> ?")) {
    const [userId, keepTokenHash] = params;
    for (const [hashKey, entry] of sessionStore.entries()) {
      if (entry.userId === userId && hashKey !== keepTokenHash) {
        sessionStore.delete(hashKey);
      }
    }
    return [{ affectedRows: 1 }];
  }
  if (sql.includes("WHERE user_id = ?")) {
    const [userId] = params;
    for (const [hashKey, entry] of sessionStore.entries()) {
      if (entry.userId === userId) {
        sessionStore.delete(hashKey);
      }
    }
    return [{ affectedRows: 1 }];
  }
  const [tokenHash] = params;
  sessionStore.delete(tokenHash);
  return [{ affectedRows: 1 }];
}

function createMockSessionDb() {
  const sessionStore = new Map();
  let nextSessionId = 1;
  return {
    rows: sessionStore,
    async query(sql, params = []) {
      const nowSeconds = Math.floor(Date.now() / 1000);
      if (sql.startsWith("DELETE FROM auth_sessions WHERE expires_at <=")) {
        return pruneExpiredMockSessions(sessionStore, nowSeconds);
      }
      if (sql.startsWith("INSERT INTO auth_sessions")) {
        return upsertMockSession(sessionStore, params, () => nextSessionId++);
      }
      if (sql.startsWith("SELECT session_id FROM auth_sessions")) {
        return queryActiveMockSession(sessionStore, params, nowSeconds);
      }
      if (sql.startsWith("DELETE FROM auth_sessions")) {
        return deleteMockSessions(sessionStore, sql, params);
      }
      throw new Error(`Unexpected session SQL: ${sql}`);
    },
  };
}

test("3. Auth security rejects plaintext hashes, persists auth_sessions, and revokes logged-out tokens", async () => {
  assert.equal(verifyPassword("password", "password"), false);
  const hashed = hashPassword("ValidPass123!");
  assert.equal(verifyPassword(hashed, "ValidPass123!"), true);
  assert.equal(verifyPassword(hashed, "WrongPass123!"), false);

  const token = signToken({
    user_id: 1002,
    username: "renter01",
    email: "renter01@rentspace.test",
    role: "customer",
  });
  assert.equal(isTokenRevoked(token), false);
  revokeToken(token);
  assert.equal(isTokenRevoked(token), true);

  const tokenA = signToken({
    user_id: 1002,
    username: "renter01",
    email: "renter01@rentspace.test",
    role: "customer",
  });
  const tokenB = signToken({
    user_id: 1002,
    username: "renter01",
    email: "renter01@rentspace.test",
    role: "customer",
  });
  const otherUserToken = signToken({
    user_id: 1003,
    username: "owner01",
    email: "owner01@rentspace.test",
    role: "owner",
  });
  assert.notEqual(tokenA, token);
  assert.notEqual(tokenB, tokenA);
  assert.equal(isTokenRevoked(tokenA), false);

  const sessionDb = createMockSessionDb();
  sessionDb.rows.set("expired_hash", {
    sessionId: 999,
    userId: 1002,
    tokenHash: "expired_hash",
    expiresAt: 1,
  });

  assert.equal(await isSessionActive(sessionDb, 1002, tokenA), false);
  await recordSession(sessionDb, 1002, tokenA);
  await recordSession(sessionDb, 1002, tokenB);
  await recordSession(sessionDb, 1003, otherUserToken);
  assert.equal(sessionDb.rows.has("expired_hash"), false);
  assert.equal(await isSessionActive(sessionDb, 1002, tokenA), true);
  assert.equal(await isSessionActive(sessionDb, 1002, tokenB), true);
  assert.equal(await isSessionActive(sessionDb, 1003, otherUserToken), true);

  await revokeOtherUserSessions(sessionDb, 1002, tokenA);
  assert.equal(await isSessionActive(sessionDb, 1002, tokenA), true);
  assert.equal(await isSessionActive(sessionDb, 1002, tokenB), false);
  assert.equal(await isSessionActive(sessionDb, 1003, otherUserToken), true);

  await revokeSession(sessionDb, tokenA);
  assert.equal(await isSessionActive(sessionDb, 1002, tokenA), false);
  assert.equal(isTokenRevoked(tokenA), true);

  assert.equal(isValidEmail(""), false);
  assert.equal(isValidEmail("plainaddress"), false);
  assert.equal(isValidEmail("missing@domain"), false);
  assert.equal(isValidEmail("user@rentspace.test"), true);

  assert.equal(isValidPhone("123"), false);
  assert.equal(isValidPhone("abc-12345678"), false);
  assert.equal(isValidPhone("081-234-5678"), true);
  assert.equal(isValidPhone("+66 812345678"), true);

  const longUsername = "very long user name that exceeds the fifty character limit in users table";
  const generatedA = buildUniqueUsername(longUsername, "long@rentspace.test");
  const generatedB = buildUniqueUsername(longUsername, "long@rentspace.test");
  assert.notEqual(generatedA, generatedB);
  assert.equal(generatedA.length <= 50, true);
  assert.equal(generatedB.length <= 50, true);
  assert.equal(/\s/.test(generatedA), false);
});

test("4. Booking guards enforce admin-only slip review, owner/admin complete after endsAt, and endsAt calculation", async () => {
  const sampleBooking = {
    booking_id: 3901,
    customer_id: 1002,
    space_owner_id: 1001,
    start_date: "2026-11-16",
    end_date: "2026-11-18",
    days_count: 3,
    end_minutes: 720,
    status: "confirmed",
    app_status: "confirmed",
  };
  const endsAt = computeBookingEndsAt(sampleBooking);
  const endsAtParts = getThaiDateParts(endsAt);
  assert.equal(endsAtParts.year, 2026);
  assert.equal(endsAtParts.month, 11);
  assert.equal(endsAtParts.day, 18);
  assert.equal(endsAtParts.hours, 12);
  assert.equal(endsAtParts.minutes, 0);

  const midnightBooking = {
    start_date: "2026-11-16",
    days_count: 1,
    end_minutes: 1440,
  };
  const midnightEndParts = getThaiDateParts(computeBookingEndsAt(midnightBooking));
  assert.equal(midnightEndParts.day, 17);
  assert.equal(midnightEndParts.hours, 0);

  const midnightFallbackParts = getThaiDateParts(
    computeBookingEndsAt({
      start_date: "2026-11-16",
      days_count: 1,
      end_time: "2026-11-17T00:00:00",
    })
  );
  assert.equal(midnightFallbackParts.day, 17);
  assert.equal(midnightFallbackParts.hours, 0);
  assert.equal(midnightFallbackParts.minutes, 0);

  assert.equal(toIsoDate(new Date("2026-11-15T17:30:00.000Z")), "2026-11-16");
  assert.equal(buildThaiDate(2026, 11, 18, 12, 0).toISOString(), "2026-11-18T05:00:00.000Z");

  assert.equal(formatClockTimestamp("2026-11-16", 660), "2026-11-16 11:00:00");
  assert.equal(formatClockTimestamp("2026-11-16", 1440), "2026-11-17 00:00:00");
  assert.equal(formatClockTimestamp("2026-11-30", 1440), "2026-12-01 00:00:00");

  let capturedInsertParams = null;
  const fullDayHours = JSON.stringify(
    Array.from({ length: 7 }, () => ({ open: true, start: 0, end: 1440 }))
  );
  const mockConnection = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
    async query(sqlQuery, queryParams) {
      if (sqlQuery.includes("FROM spaces s")) {
        return [[{
          space_id: 2001,
          owner_id: 1001,
          price_per_day: 350,
          capacity: 10,
          status: "approved",
          owner_status: "active",
          owner_role: "owner",
          hours_json: fullDayHours,
        }]];
      }
      if (sqlQuery.includes("FROM room_blocks")) return [[]];
      if (sqlQuery.includes("FROM bookings")) return [[]];
      if (sqlQuery.includes("INSERT INTO bookings")) {
        capturedInsertParams = queryParams;
        return [{ insertId: 3999 }];
      }
      throw new Error(`Unexpected SQL in mockConnection: ${sqlQuery}`);
    },
  };
  const mockDbPool = {
    async getConnection() {
      return mockConnection;
    },
  };
  const bookingOutcome = await createBookingTransactional(mockDbPool, 1002, {
    spaceId: 2001,
    date: "2031-07-14",
    startMinutes: 720,
    endMinutes: 1440,
    days: 1,
    attendees: 2,
  });
  assert.equal(bookingOutcome.status, 201);
  assert.ok(Array.isArray(capturedInsertParams));
  assert.equal(capturedInsertParams[4], "2031-07-14 12:00:00");
  assert.equal(capturedInsertParams[5], "2031-07-15 00:00:00");
  assert.equal(capturedInsertParams[8], 1440);

  // Role permissions
  assert.equal(hasBookingPermission({ id: 1001, role: "owner" }, sampleBooking, "admin"), false);
  assert.equal(hasBookingPermission({ id: 1003, role: "admin" }, sampleBooking, "admin"), true);
  assert.equal(hasBookingPermission({ id: 1002, role: "renter" }, sampleBooking, "ownerOrAdmin"), false);
  assert.equal(hasBookingPermission({ id: 1001, role: "owner" }, sampleBooking, "ownerOrAdmin"), true);
  assert.equal(hasBookingPermission({ id: 1003, role: "admin" }, sampleBooking, "ownerOrAdmin"), true);

  // guardBookingAccess rejects non-admin for admin-only route with 403
  const mockDb = {
    async query() {
      return [[{ ...sampleBooking, app_status: "slipReview" }]];
    },
  };
  const adminGuard = guardBookingAccess(mockDb, {
    access: "admin",
    allowedStatuses: ["slipReview"],
  });
  let statusCode = null;
  let nextCalled = false;
  await adminGuard(
    { params: { id: "3901" }, user: { id: 1001, role: "owner" } },
    {
      status(code) {
        statusCode = code;
        return { json() {} };
      },
    },
    () => {
      nextCalled = true;
    }
  );
  assert.equal(statusCode, 403);
  assert.equal(nextCalled, false);

  await adminGuard(
    { params: { id: "3901" }, user: { id: 1003, role: "admin" } },
    {
      status() {
        return { json() {} };
      },
    },
    () => {
      nextCalled = true;
    }
  );
  assert.equal(nextCalled, true);

  const slipGuard = guardSlipUploadAccess(mockDb, verifyToken());
  async function runSlipGuardCase(mockRequest) {
    let capturedStatus = null;
    let passedNext = false;
    await slipGuard(
      mockRequest,
      {
        status(code) {
          capturedStatus = code;
          return { json() {} };
        },
      },
      () => {
        passedNext = true;
      }
    );
    return { capturedStatus, passedNext };
  }

  assert.deepEqual(
    await runSlipGuardCase({ path: "/meeting.jpg", headers: {} }),
    { capturedStatus: null, passedNext: true }
  );
  assert.deepEqual(
    await runSlipGuardCase({ path: "/slip_3901_1700000.png", headers: {} }),
    { capturedStatus: 401, passedNext: false }
  );
  assert.deepEqual(
    await runSlipGuardCase({ path: "/%73lip_3901_1700000.png", headers: {} }),
    { capturedStatus: 401, passedNext: false }
  );
  assert.deepEqual(
    await runSlipGuardCase({ path: "/slip_bad.png", headers: {} }),
    { capturedStatus: 403, passedNext: false }
  );
  assert.deepEqual(
    await runSlipGuardCase({
      path: "/slip_3901_1700000.png",
      headers: {},
      user: { id: 1004, role: "renter" },
    }),
    { capturedStatus: 403, passedNext: false }
  );
  assert.deepEqual(
    await runSlipGuardCase({
      path: "/slip_3901_1700000.png",
      headers: {},
      user: { id: 1002, role: "renter" },
    }),
    { capturedStatus: null, passedNext: true }
  );
  assert.deepEqual(
    await runSlipGuardCase({
      path: "/payout_3901_1700000.png",
      headers: {},
      user: { id: 1002, role: "renter" },
    }),
    { capturedStatus: 403, passedNext: false }
  );
  assert.deepEqual(
    await runSlipGuardCase({
      path: "/payout_3901_1700000.png",
      headers: {},
      user: { id: 1001, role: "owner" },
    }),
    { capturedStatus: null, passedNext: true }
  );
  assert.deepEqual(
    await runSlipGuardCase({
      path: "/payout_3901_1700000.png",
      headers: {},
      user: { id: 1003, role: "admin" },
    }),
    { capturedStatus: null, passedNext: true }
  );

  const expiredOwnerReview = evaluateBookingLifecycleTransition(
    {
      booking_id: 5001,
      start_date: "2026-11-25",
      start_minutes: 600,
      status: "pending",
      app_status: "ownerReview",
      created_at: buildThaiDate(2026, 11, 15, 10, 0),
    },
    buildThaiDate(2026, 11, 16, 10, 1)
  );
  assert.equal(expiredOwnerReview.nextAppStatus, "canceled");
  assert.equal(expiredOwnerReview.reasonKind, "expiredBySystem");

  const startReachedPaymentDue = evaluateBookingLifecycleTransition(
    {
      booking_id: 5002,
      start_date: "2026-11-18",
      start_minutes: 600,
      status: "approved",
      app_status: "paymentDue",
      approved_at: buildThaiDate(2026, 11, 18, 8, 0),
    },
    buildThaiDate(2026, 11, 18, 10, 0)
  );
  assert.equal(startReachedPaymentDue.nextAppStatus, "canceled");
  assert.equal(startReachedPaymentDue.reasonKind, "expiredBySystem");

  const expiredSlipRejected = evaluateBookingLifecycleTransition(
    {
      booking_id: 5003,
      start_date: "2026-11-25",
      start_minutes: 600,
      status: "approved",
      app_status: "slipRejected",
      slip_rejected_at: buildThaiDate(2026, 11, 15, 9, 0),
    },
    buildThaiDate(2026, 11, 16, 9, 0)
  );
  assert.equal(expiredSlipRejected.nextAppStatus, "canceled");
  assert.equal(expiredSlipRejected.reasonKind, "expiredBySystem");

  const autoCompletedBooking = evaluateBookingLifecycleTransition(
    {
      booking_id: 5004,
      start_date: "2026-11-16",
      end_date: "2026-11-16",
      end_minutes: 720,
      days_count: 1,
      status: "confirmed",
      app_status: "confirmed",
    },
    buildThaiDate(2026, 11, 17, 12, 0)
  );
  assert.equal(autoCompletedBooking.nextAppStatus, "completed");

  assert.equal(
    evaluateBookingLifecycleTransition(
      {
        booking_id: 5005,
        start_date: "2026-11-16",
        start_minutes: 600,
        status: "approved",
        app_status: "slipReview",
        approved_at: buildThaiDate(2026, 11, 10, 9, 0),
      },
      buildThaiDate(2026, 11, 18, 12, 0)
    ),
    null
  );

  const sweepUpdates = [];
  const sweepMockDb = {
    async query(sqlText, queryParams) {
      if (sqlText.startsWith("SELECT * FROM bookings")) {
        return [[
          {
            booking_id: 5001,
            start_date: "2026-11-25",
            start_minutes: 600,
            status: "pending",
            app_status: "ownerReview",
            created_at: buildThaiDate(2026, 11, 15, 10, 0),
          },
          {
            booking_id: 5004,
            start_date: "2026-11-16",
            end_date: "2026-11-16",
            end_minutes: 720,
            days_count: 1,
            status: "confirmed",
            app_status: "confirmed",
          },
        ]];
      }
      if (sqlText.startsWith("UPDATE bookings")) {
        sweepUpdates.push({ sqlText, queryParams });
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Unexpected SQL in sweepMockDb: ${sqlText}`);
    },
  };
  const updatedTotal = await sweepExpiredBookings(
    sweepMockDb,
    buildThaiDate(2026, 11, 17, 12, 0)
  );
  assert.equal(updatedTotal, 2);
  assert.equal(sweepUpdates.length, 2);
  assert.equal(sweepUpdates[0].queryParams[1], "expiredBySystem");
  assert.equal(sweepUpdates[0].queryParams[2], 5001);
  assert.equal(sweepUpdates[1].queryParams[0], 5004);

  const expiredGuardUpdates = [];
  const expiredGuardDb = {
    async query(sqlText, queryParams) {
      if (sqlText.includes("FROM bookings b")) {
        return [[{
          booking_id: 5006,
          customer_id: 1002,
          space_owner_id: 1001,
          start_date: "2026-11-25",
          start_minutes: 600,
          status: "approved",
          app_status: "paymentDue",
          approved_at: new Date(2020, 0, 1, 9, 0),
        }]];
      }
      if (sqlText.startsWith("UPDATE bookings")) {
        expiredGuardUpdates.push(queryParams);
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Unexpected SQL in expiredGuardDb: ${sqlText}`);
    },
  };
  const slipUploadGuard = guardBookingAccess(expiredGuardDb, {
    access: "renter",
    allowedStatuses: ["paymentDue", "slipRejected"],
  });
  let expiredStatus = null;
  let expiredNextCalled = false;
  await slipUploadGuard(
    { params: { id: "5006" }, user: { id: 1002, role: "renter" } },
    {
      status(code) {
        expiredStatus = code;
        return { json() {} };
      },
    },
    () => {
      expiredNextCalled = true;
    }
  );
  assert.equal(expiredStatus, 409);
  assert.equal(expiredNextCalled, false);
  assert.equal(expiredGuardUpdates.length, 1);
  assert.equal(expiredGuardUpdates[0][1], "expiredBySystem");
  assert.equal(expiredGuardUpdates[0][2], 5006);

  const createSlipTxHarness = ({ affectedRows = 1, failUpdate = false } = {}) => {
    const mockFiles = new Map();
    const queries = [];
    const harness = {
      files: mockFiles,
      queries,
      began: false,
      committed: false,
      rolledBack: false,
      released: false,
    };
    const mockConn = {
      async beginTransaction() {
        harness.began = true;
      },
      async query(sqlText, queryParams) {
        queries.push({ sqlText, queryParams });
        if (sqlText.startsWith("INSERT INTO payments")) {
          return [{ insertId: 7001 }];
        }
        if (sqlText.startsWith("UPDATE bookings")) {
          if (failUpdate) {
            throw new Error("simulated update failure");
          }
          return [{ affectedRows }];
        }
        throw new Error(`Unexpected slip tx SQL: ${sqlText}`);
      },
      async commit() {
        harness.committed = true;
      },
      async rollback() {
        harness.rolledBack = true;
      },
      release() {
        harness.released = true;
      },
    };
    return {
      harness,
      mockDb: {
        async getConnection() {
          return mockConn;
        },
      },
      mockFileOps: {
        writeFileSync(filePath, contentBuffer) {
          mockFiles.set(filePath, contentBuffer);
        },
        existsSync(filePath) {
          return mockFiles.has(filePath);
        },
        unlinkSync(filePath) {
          mockFiles.delete(filePath);
        },
      },
    };
  };

  const buildSlipSpec = (fileName) => ({
    bookingId: "5010",
    note: "โอนเต็มจำนวน",
    storedFilePath: `/virtual/uploads/${fileName}`,
    imageUrl: `/uploads/${fileName}`,
    originalFileName: fileName,
    fileBuffer: Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    base64Content: "iVBORw0KGgo=",
    amount: 700,
  });

  const okTx = createSlipTxHarness({ affectedRows: 1 });
  const okSpec = buildSlipSpec("slip_5010_1.png");
  const okOutcome = await submitPaymentSlipTransactional(okTx.mockDb, okSpec, okTx.mockFileOps);
  assert.equal(okOutcome.status, 201);
  assert.equal(okOutcome.body.ok, true);
  assert.equal(okOutcome.body.image_url, "/uploads/slip_5010_1.png");
  assert.equal(okTx.harness.began, true);
  assert.equal(okTx.harness.committed, true);
  assert.equal(okTx.harness.rolledBack, false);
  assert.equal(okTx.harness.released, true);
  assert.equal(okTx.harness.files.has(okSpec.storedFilePath), true);
  assert.equal(okTx.harness.queries.length, 2);

  const staleTx = createSlipTxHarness({ affectedRows: 0 });
  const staleSpec = buildSlipSpec("slip_5010_2.png");
  const staleOutcome = await submitPaymentSlipTransactional(
    staleTx.mockDb,
    staleSpec,
    staleTx.mockFileOps
  );
  assert.equal(staleOutcome.status, 409);
  assert.equal(staleTx.harness.committed, false);
  assert.equal(staleTx.harness.rolledBack, true);
  assert.equal(staleTx.harness.released, true);
  assert.equal(staleTx.harness.files.has(staleSpec.storedFilePath), false);

  const errTx = createSlipTxHarness({ failUpdate: true });
  const errSpec = buildSlipSpec("slip_5010_3.png");
  await assert.rejects(
    () => submitPaymentSlipTransactional(errTx.mockDb, errSpec, errTx.mockFileOps),
    /simulated update failure/
  );
  assert.equal(errTx.harness.committed, false);
  assert.equal(errTx.harness.rolledBack, true);
  assert.equal(errTx.harness.released, true);
  assert.equal(errTx.harness.files.has(errSpec.storedFilePath), false);

  const okGuardOutcome = await applyGuardedBookingUpdate(
    {
      async query() {
        return [{ affectedRows: 1 }];
      },
    },
    "UPDATE bookings SET status = 'confirmed' WHERE booking_id = ?",
    [5011]
  );
  assert.equal(okGuardOutcome.status, 200);
  assert.equal(okGuardOutcome.body.ok, true);

  const staleGuardOutcome = await applyGuardedBookingUpdate(
    {
      async query() {
        return [{ affectedRows: 0 }];
      },
    },
    "UPDATE bookings SET status = 'confirmed' WHERE booking_id = ?",
    [5011]
  );
  assert.equal(staleGuardOutcome.status, 409);

  const createReviewTxHarness = ({ affectedRows = 1, failPaymentUpdate = false } = {}) => {
    const queries = [];
    const harness = {
      queries,
      committed: false,
      rolledBack: false,
      released: false,
    };
    const mockConn = {
      async beginTransaction() {},
      async query(sqlText, queryParams) {
        queries.push({ sqlText, queryParams });
        if (sqlText.startsWith("UPDATE bookings")) {
          return [{ affectedRows }];
        }
        if (sqlText.startsWith("UPDATE payments")) {
          if (failPaymentUpdate) {
            throw new Error("simulated payment review failure");
          }
          return [{ affectedRows: 1 }];
        }
        throw new Error(`Unexpected review tx SQL: ${sqlText}`);
      },
      async commit() {
        harness.committed = true;
      },
      async rollback() {
        harness.rolledBack = true;
      },
      release() {
        harness.released = true;
      },
    };
    return {
      harness,
      mockDb: {
        async getConnection() {
          return mockConn;
        },
      },
    };
  };

  const approvedReview = createReviewTxHarness({ affectedRows: 1 });
  const approvedReviewOutcome = await reviewPaymentSlipTransactional(approvedReview.mockDb, {
    bookingId: "5012",
    approve: true,
    reason: "",
  });
  assert.equal(approvedReviewOutcome.status, 200);
  assert.equal(approvedReview.harness.committed, true);
  assert.equal(approvedReview.harness.rolledBack, false);
  assert.equal(approvedReview.harness.released, true);
  assert.equal(approvedReview.harness.queries.length, 2);
  assert.equal(
    approvedReview.harness.queries[0].sqlText.includes("AND app_status = 'slipReview'"),
    true
  );
  assert.equal(
    approvedReview.harness.queries[1].sqlText.includes("status = 'verified'"),
    true
  );

  const staleReview = createReviewTxHarness({ affectedRows: 0 });
  const staleReviewOutcome = await reviewPaymentSlipTransactional(staleReview.mockDb, {
    bookingId: "5012",
    approve: false,
    reason: "สลิปไม่ชัด",
  });
  assert.equal(staleReviewOutcome.status, 409);
  assert.equal(staleReview.harness.committed, false);
  assert.equal(staleReview.harness.rolledBack, true);
  assert.equal(staleReview.harness.released, true);
  assert.equal(staleReview.harness.queries.length, 1);

  const failedReview = createReviewTxHarness({ affectedRows: 1, failPaymentUpdate: true });
  await assert.rejects(
    () =>
      reviewPaymentSlipTransactional(failedReview.mockDb, {
        bookingId: "5012",
        approve: true,
        reason: "",
      }),
    /simulated payment review failure/
  );
  assert.equal(failedReview.harness.committed, false);
  assert.equal(failedReview.harness.rolledBack, true);
  assert.equal(failedReview.harness.released, true);

  const missingDescCreate = resolveSpaceMutationInput(
    {
      name: "Cozy Meeting Room",
      category: "ห้องประชุม",
      location: "อารีย์",
      price: 500,
      capacity: 8,
      description: "   ",
    },
    null
  );
  assert.equal(Boolean(missingDescCreate.error), true);

  const invalidHoursCreate = resolveSpaceMutationInput(
    {
      name: "Cozy Meeting Room",
      category: "ห้องประชุม",
      location: "อารีย์",
      price: 500,
      capacity: 8,
      description: "พร้อมโปรเจกเตอร์",
      hours: [{ start: 600, end: 540 }],
    },
    null
  );
  assert.equal(invalidHoursCreate.error, "เวลาเปิดปิดของแต่ละวันไม่ถูกต้อง");
  assert.equal(isValidHoursList([{ start: 540, end: 1080 }]), false);

  const existingSpaceRow = {
    space_id: 2001,
    title: "Studio Alpha",
    category: "สตูดิโอ",
    location: "อารีย์",
    price_per_day: 500,
    capacity: 10,
    description: "ห้องถ่ายภาพ",
    image_url: "/uploads/studio.jpg",
    hours_json: null,
    amenities_json: '["Wi-Fi","แอร์"]',
  };

  const preservedUpdate = resolveSpaceMutationInput(
    { name: "Studio Alpha Renamed" },
    existingSpaceRow
  );
  assert.equal(preservedUpdate.error, undefined);
  assert.equal(preservedUpdate.spaceInput.title, "Studio Alpha Renamed");
  assert.equal(preservedUpdate.spaceInput.shouldSyncAmenities, false);
  assert.equal(preservedUpdate.spaceInput.amenitiesJson, '["Wi-Fi","แอร์"]');

  const updatedAmenities = resolveSpaceMutationInput(
    { amenities: ["Wi-Fi", "  โปรเจกเตอร์  ", ""] },
    existingSpaceRow
  );
  assert.equal(updatedAmenities.error, undefined);
  assert.equal(updatedAmenities.spaceInput.shouldSyncAmenities, true);
  assert.deepEqual(updatedAmenities.spaceInput.amenities, ["Wi-Fi", "โปรเจกเตอร์"]);

  let openedPoolForEmptyReason = false;
  const emptyRejectReasonOutcome = await reviewPaymentSlipTransactional(
    {
      async getConnection() {
        openedPoolForEmptyReason = true;
        throw new Error("Should not open DB connection on missing reject reason");
      },
    },
    { bookingId: "5013", approve: false, reason: "   " }
  );
  assert.equal(emptyRejectReasonOutcome.status, 400);
  assert.equal(openedPoolForEmptyReason, false);

  const favQueries = [];
  let favExists = false;
  const favoriteMockDb = {
    async query(sqlText, queryParams) {
      favQueries.push({ sqlText, queryParams });
      if (sqlText.startsWith("SELECT space_id FROM spaces")) {
        return [String(queryParams[0]) === "9999" ? [] : [{ space_id: 2001 }]];
      }
      if (sqlText.startsWith("SELECT 1 FROM user_favorites")) {
        return [favExists ? [{ 1: 1 }] : []];
      }
      if (sqlText.startsWith("INSERT INTO user_favorites")) {
        favExists = true;
        return [{ affectedRows: 1 }];
      }
      if (sqlText.startsWith("DELETE FROM user_favorites")) {
        favExists = false;
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Unexpected favorite SQL: ${sqlText}`);
    },
  };
  const missingFavOutcome = await toggleSpaceFavorite(favoriteMockDb, 1002, "9999");
  assert.equal(missingFavOutcome.status, 404);
  const addFavOutcome = await toggleSpaceFavorite(favoriteMockDb, 1002, "2001");
  assert.equal(addFavOutcome.status, 200);
  assert.equal(favExists, true);
  const removeFavOutcome = await toggleSpaceFavorite(favoriteMockDb, 1002, "2001");
  assert.equal(removeFavOutcome.status, 200);
  assert.equal(favExists, false);

  const deleteQueries = [];
  const virtualUploadsDir = path.join("virtual", "uploads");
  const deleteSlipPath = path.join(virtualUploadsDir, "slip_9001_1.png");
  const deletePayoutPath = path.join(virtualUploadsDir, "payout_9001_2.png");
  const keepSeedPath = path.join(virtualUploadsDir, "meeting.jpg");
  const deleteFiles = new Map([
    [deleteSlipPath, Buffer.from("slip")],
    [deletePayoutPath, Buffer.from("payout")],
    [keepSeedPath, Buffer.from("keep-seed-image")],
  ]);
  const deleteHarness = { committed: false, rolledBack: false, released: false };
  const deleteConn = {
    async beginTransaction() {},
    async query(sqlText, queryParams) {
      deleteQueries.push({ sqlText, queryParams });
      if (sqlText.startsWith("SELECT booking_id, slip_image_url")) {
        return [[
          {
            booking_id: 9001,
            slip_image_url: "/uploads/slip_9001_1.png",
            payout_slip_url: "/uploads/payout_9001_2.png",
          },
        ]];
      }
      if (sqlText.startsWith("SELECT slip_image_url FROM payments")) {
        return [[{ slip_image_url: "/uploads/meeting.jpg" }]];
      }
      if (sqlText.startsWith("DELETE ")) {
        return [{ affectedRows: 1 }];
      }
      throw new Error(`Unexpected deleteSpace SQL: ${sqlText}`);
    },
    async commit() {
      deleteHarness.committed = true;
    },
    async rollback() {
      deleteHarness.rolledBack = true;
    },
    release() {
      deleteHarness.released = true;
    },
  };
  const deleteFileOps = {
    existsSync(filePath) {
      return deleteFiles.has(filePath);
    },
    unlinkSync(filePath) {
      deleteFiles.delete(filePath);
    },
  };
  const deleteOutcome = await deleteSpaceTransactional(
    { async getConnection() { return deleteConn; } },
    "2099",
    virtualUploadsDir,
    deleteFileOps
  );
  assert.equal(deleteOutcome.status, 200);
  assert.equal(deleteHarness.committed, true);
  assert.equal(deleteHarness.rolledBack, false);
  assert.equal(deleteHarness.released, true);
  assert.equal(deleteFiles.has(deleteSlipPath), false);
  assert.equal(deleteFiles.has(deletePayoutPath), false);
  assert.equal(deleteFiles.has(keepSeedPath), true);
  const deleteOrder = deleteQueries
    .filter((entry) => entry.sqlText.startsWith("DELETE "))
    .map((entry) => entry.sqlText.split(" ")[2]);
  assert.deepEqual(deleteOrder, [
    "reviews",
    "payments",
    "admin_logs",
    "bookings",
    "room_blocks",
    "space_amenities",
    "user_favorites",
    "admin_logs",
    "spaces",
  ]);
});

function invokeRateLimiter(limiter, clientIp) {
  let nextCalled = false;
  let capturedStatus = 200;
  let capturedBody = null;
  const mockRequest = { headers: {}, ip: clientIp, socket: { remoteAddress: clientIp } };
  const mockResponse = {
    status(code) {
      capturedStatus = code;
      return {
        json(body) {
          capturedBody = body;
          return body;
        },
      };
    },
  };
  limiter(mockRequest, mockResponse, () => {
    nextCalled = true;
  });
  return { nextCalled, capturedStatus, capturedBody };
}

test("5. Auth rate limiter blocks excessive attempts per IP with 429", () => {
  const limiter = createAuthRateLimiter({ windowMs: 60000, maxAttempts: 2 });
  assert.equal(invokeRateLimiter(limiter, "10.0.0.5").nextCalled, true);
  assert.equal(invokeRateLimiter(limiter, "10.0.0.5").nextCalled, true);
  const blocked = invokeRateLimiter(limiter, "10.0.0.5");
  assert.equal(blocked.nextCalled, false);
  assert.equal(blocked.capturedStatus, 429);
  assert.equal(typeof blocked.capturedBody.error, "string");
  assert.equal(invokeRateLimiter(limiter, "10.0.0.6").nextCalled, true);
});
