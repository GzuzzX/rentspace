const { hashPassword } = require("./auth_security");

const DEFAULT_WEEK_HOURS = JSON.stringify(
  Array.from({ length: 7 }, () => ({ open: true, start: 540, end: 1080 }))
);

const AUX_TABLES_SQL = [
  `CREATE TABLE IF NOT EXISTS auth_sessions (
    session_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    user_id INT NOT NULL,
    token_hash CHAR(64) NOT NULL,
    expires_at DATETIME NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (session_id),
    UNIQUE KEY uq_auth_sessions_token_hash (token_hash),
    KEY idx_auth_sessions_user_expiry (user_id, expires_at)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  `CREATE TABLE IF NOT EXISTS room_blocks (
    block_id INT NOT NULL AUTO_INCREMENT,
    space_id INT NOT NULL,
    created_by INT NOT NULL,
    start_date DATE NOT NULL,
    end_date DATE NOT NULL,
    start_at DATETIME DEFAULT NULL,
    end_at DATETIME DEFAULT NULL,
    reason VARCHAR(255) DEFAULT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (block_id),
    KEY idx_room_blocks_space_dates (space_id, start_date, end_date)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  `CREATE TABLE IF NOT EXISTS user_favorites (
    user_id INT NOT NULL,
    space_id INT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, space_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
  `CREATE TABLE IF NOT EXISTS issues (
    id VARCHAR(40) NOT NULL,
    reporter_id INT NOT NULL,
    subject VARCHAR(255) NOT NULL,
    detail TEXT NOT NULL,
    closed TINYINT(1) NOT NULL DEFAULT 0,
    resolution TEXT DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`,
];

const COLUMN_UPGRADES = [
  { table: "users", column: "bank_info", def: "VARCHAR(255) DEFAULT ''" },
  { table: "spaces", column: "hours_json", def: "TEXT DEFAULT NULL" },
  { table: "spaces", column: "amenities_json", def: "TEXT DEFAULT NULL" },
  { table: "spaces", column: "review_reason", def: "TEXT DEFAULT NULL" },
  { table: "room_blocks", column: "start_at", def: "DATETIME DEFAULT NULL" },
  { table: "room_blocks", column: "end_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "start_minutes", def: "INT DEFAULT 540" },
  { table: "bookings", column: "end_minutes", def: "INT DEFAULT 660" },
  { table: "bookings", column: "days_count", def: "INT DEFAULT 1" },
  { table: "bookings", column: "attendees", def: "INT DEFAULT 1" },
  { table: "bookings", column: "zone", def: "VARCHAR(150) DEFAULT 'โซนหลัก (พื้นที่มาตรฐาน)'" },
  { table: "bookings", column: "renter_note", def: "TEXT DEFAULT NULL" },
  { table: "bookings", column: "platform_fee", def: "INT DEFAULT NULL" },
  { table: "bookings", column: "app_status", def: "VARCHAR(40) DEFAULT NULL" },
  { table: "bookings", column: "reason", def: "TEXT DEFAULT NULL" },
  { table: "bookings", column: "reason_kind", def: "VARCHAR(40) DEFAULT 'none'" },
  { table: "bookings", column: "approved_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "slip_rejected_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "confirmed_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "completed_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "paid_out_at", def: "DATETIME DEFAULT NULL" },
  { table: "bookings", column: "payout_slip_name", def: "VARCHAR(255) DEFAULT NULL" },
  { table: "bookings", column: "payout_slip_url", def: "TEXT DEFAULT NULL" },
  { table: "bookings", column: "payout_slip_data", def: "LONGTEXT DEFAULT NULL" },
  { table: "bookings", column: "payout_note", def: "TEXT DEFAULT NULL" },
  { table: "payments", column: "file_name", def: "VARCHAR(255) DEFAULT 'slip.jpg'" },
  { table: "payments", column: "note", def: "TEXT DEFAULT NULL" },
  { table: "payments", column: "rejection_reason", def: "TEXT DEFAULT NULL" },
  { table: "payments", column: "image_data", def: "LONGTEXT DEFAULT NULL" },
];

async function hasColumn(db, tableName, columnName) {
  const [rows] = await db.query(
    `SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?`,
    [tableName, columnName]
  );
  return rows.length > 0;
}

async function ensureColumns(db) {
  for (const item of COLUMN_UPGRADES) {
    const exists = await hasColumn(db, item.table, item.column);
    if (!exists) {
      await db.query(`ALTER TABLE \`${item.table}\` ADD COLUMN \`${item.column}\` ${item.def}`);
    }
  }
}

async function ensureDemoPasswords(db) {
  const defaultHash = hashPassword("password");
  await db.query(
    `UPDATE users SET password_hash = ?
     WHERE username IN ('owner01', 'renter01', 'admin01', 'mint_k', 'owner02')
       AND (password_hash LIKE 'scrypt$%' OR password_hash = 'SEED_ONLY_NOT_A_LOGIN_HASH')`,
    [defaultHash]
  );
}

async function ensureSchema(db) {
  for (const ddl of AUX_TABLES_SQL) {
    await db.query(ddl);
  }
  await ensureColumns(db);
  await ensureDemoPasswords(db);
}

module.exports = {
  DEFAULT_WEEK_HOURS,
  ensureSchema,
};
