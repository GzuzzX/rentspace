const test = require("node:test");
const assert = require("node:assert/strict");
const { buildSnapshot } = require("../snapshot_builder");

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
    issues: [
      { id: "iss-1", reporter_id: 1002, subject: "Renter issue", detail: "Wi-Fi slow", closed: 0 },
      { id: "iss-2", reporter_id: 1004, subject: "Stranger private dispute", detail: "Confidential", closed: 0 },
    ],
    logs: [
      { log_id: 1, admin_name: "admin01", action: "PAYOUT_OWNER", details: "Transferred 950 THB", created_at: "2027-05-10T12:00:00Z" },
    ],
  };

  return {
    async query(sqlText) {
      if (sqlText.includes("FROM users")) return [tables.users];
      if (sqlText.includes("FROM spaces")) return [tables.spaces];
      if (sqlText.includes("FROM bookings")) return [tables.bookings];
      if (sqlText.includes("FROM room_blocks")) return [[]];
      if (sqlText.includes("FROM payments")) return [tables.payments];
      if (sqlText.includes("FROM reviews")) return [[]];
      if (sqlText.includes("FROM user_favorites")) return [[]];
      if (sqlText.includes("FROM issues")) return [tables.issues];
      if (sqlText.includes("FROM admin_logs")) return [tables.logs];
      if (sqlText.includes("FROM space_amenities")) return [[]];
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

  // Busy slots still include all active bookings across users to block double-booking
  assert.equal(snapshot.busy.length, 2);
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
});
