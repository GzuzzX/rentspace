const test = require("node:test");
const assert = require("node:assert/strict");
const con = require("../db_config");

const db = con.promise();
const SCHEMA = process.env.DB_NAME || "rent_space";

const EXPECTED_TABLES = [
  "users",
  "spaces",
  "amenities",
  "space_amenities",
  "space_images",
  "bookings",
  "payments",
  "reviews",
  "admin_logs",
  "auth_sessions",
  "room_blocks",
  "user_favorites",
  "issues",
];

const STRING_TYPES = ["char", "varchar", "text", "tinytext", "mediumtext", "longtext"];
const INT_TYPES = ["int", "tinyint", "smallint", "mediumint", "bigint"];
const DECIMAL_TYPES = ["decimal", "float", "double"];

async function loadTables() {
  const [rows] = await db.query(
    "SELECT TABLE_NAME AS tableName FROM information_schema.TABLES WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE' ORDER BY TABLE_NAME",
    [SCHEMA]
  );
  return rows.map((row) => row.tableName);
}

async function loadColumns(tableName) {
  const [rows] = await db.query(
    `SELECT COLUMN_NAME AS name, DATA_TYPE AS dataType, COLUMN_TYPE AS columnType,
            IS_NULLABLE AS isNullable, COLUMN_DEFAULT AS defaultValue, EXTRA AS extra,
            CHARACTER_MAXIMUM_LENGTH AS maxLength, NUMERIC_PRECISION AS numericPrecision,
            NUMERIC_SCALE AS numericScale
     FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
     ORDER BY ORDINAL_POSITION`,
    [SCHEMA, tableName]
  );
  return rows;
}

async function loadForeignKeys(tableName) {
  const [rows] = await db.query(
    `SELECT COLUMN_NAME AS columnName, REFERENCED_TABLE_NAME AS parentTable,
            REFERENCED_COLUMN_NAME AS parentColumn
     FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND REFERENCED_TABLE_NAME IS NOT NULL`,
    [SCHEMA, tableName]
  );
  return rows;
}

async function loadPrimaryKey(tableName) {
  const [rows] = await db.query(
    `SELECT COLUMN_NAME AS columnName FROM information_schema.KEY_COLUMN_USAGE
     WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND CONSTRAINT_NAME = 'PRIMARY'
     ORDER BY ORDINAL_POSITION`,
    [SCHEMA, tableName]
  );
  return rows.map((row) => row.columnName);
}

function firstEnumValue(columnType) {
  const match = /^enum\('((?:[^']|'')*)'/i.exec(columnType);
  return match ? match[1].replace(/''/g, "'") : null;
}

function buildValueForColumn(column, uniqueSuffix) {
  const type = column.dataType.toLowerCase();
  if (type === "enum") return firstEnumValue(column.columnType);
  if (INT_TYPES.includes(type)) return 1;
  if (DECIMAL_TYPES.includes(type)) return 1;
  if (type === "date") return "2030-01-01";
  if (type === "datetime" || type === "timestamp") return "2030-01-01 10:00:00";
  if (type === "time") return "10:00:00";
  if (type === "json") return "{}";
  if (STRING_TYPES.includes(type)) {
    const limit = column.maxLength ? Math.min(Number(column.maxLength), 40) : 40;
    return `t${uniqueSuffix}`.slice(0, limit);
  }
  return null;
}

async function pickParentValue(parentTable, parentColumn, childTable, childColumn) {
  const [unused] = await db.query(
    `SELECT p.\`${parentColumn}\` AS picked FROM \`${parentTable}\` p
     WHERE p.\`${parentColumn}\` NOT IN (
       SELECT c.\`${childColumn}\` FROM \`${childTable}\` c WHERE c.\`${childColumn}\` IS NOT NULL
     ) LIMIT 1`
  );
  if (unused.length) return unused[0].picked;
  const [rows] = await db.query(`SELECT \`${parentColumn}\` AS picked FROM \`${parentTable}\` LIMIT 1`);
  return rows.length ? rows[0].picked : undefined;
}

async function buildInsertRow(tableName, columns, foreignKeys) {
  const row = {};
  const uniqueSuffix = String(Date.now() % 1e9);
  const fkByColumn = new Map(foreignKeys.map((fk) => [fk.columnName, fk]));
  for (const column of columns) {
    if (/auto_increment|GENERATED/i.test(column.extra)) continue;
    const fk = fkByColumn.get(column.name);
    if (fk) {
      const picked = await pickParentValue(fk.parentTable, fk.parentColumn, tableName, fk.columnName);
      if (picked === undefined) return null;
      row[column.name] = picked;
      continue;
    }
    if (column.isNullable === "YES" || column.defaultValue !== null) {
      if (!/^(email|username|name|token_hash|title)$/.test(column.name)) continue;
    }
    row[column.name] = buildValueForColumn(column, uniqueSuffix);
  }
  return row;
}

async function insertAndRollback(tableName, columns, foreignKeys) {
  const row = await buildInsertRow(tableName, columns, foreignKeys);
  if (row === null) return { skipped: true };
  const connection = await db.getConnection();
  try {
    await connection.beginTransaction();
    const names = Object.keys(row);
    const sql = names.length
      ? `INSERT INTO \`${tableName}\` (${names.map((n) => `\`${n}\``).join(",")}) VALUES (${names.map(() => "?").join(",")})`
      : `INSERT INTO \`${tableName}\` () VALUES ()`;
    const [outcome] = await connection.query(sql, names.map((n) => row[n]));
    return { skipped: false, affectedRows: outcome.affectedRows };
  } finally {
    await connection.rollback();
    connection.release();
  }
}

test.after(async () => {
  await con.end();
});

test("database: every expected table exists", async () => {
  const actual = await loadTables();
  for (const expected of EXPECTED_TABLES) {
    assert.ok(actual.includes(expected), `missing table: ${expected}`);
  }
});

test("database: no undeclared tables (update EXPECTED_TABLES when adding one)", async () => {
  const actual = await loadTables();
  const undeclared = actual.filter((name) => !EXPECTED_TABLES.includes(name));
  assert.deepEqual(undeclared, []);
});

test("database: every table has a primary key and at least one column", async () => {
  for (const tableName of await loadTables()) {
    assert.ok((await loadColumns(tableName)).length > 0, `${tableName} has no columns`);
    assert.ok((await loadPrimaryKey(tableName)).length > 0, `${tableName} has no primary key`);
  }
});

test("database: every table is readable and row counts are consistent", async () => {
  for (const tableName of await loadTables()) {
    const [[counted]] = await db.query(`SELECT COUNT(*) AS total FROM \`${tableName}\``);
    const [rows] = await db.query(`SELECT * FROM \`${tableName}\``);
    assert.equal(rows.length, Number(counted.total), `${tableName} count mismatch`);
  }
});

test("database: no NULLs in NOT NULL columns and no duplicate primary keys", async () => {
  for (const tableName of await loadTables()) {
    const primaryKey = await loadPrimaryKey(tableName);
    const keyList = primaryKey.map((c) => `\`${c}\``).join(",");
    const [duplicates] = await db.query(
      `SELECT ${keyList}, COUNT(*) AS total FROM \`${tableName}\` GROUP BY ${keyList} HAVING total > 1`
    );
    assert.equal(duplicates.length, 0, `${tableName} has duplicate primary keys`);
    for (const column of await loadColumns(tableName)) {
      if (column.isNullable !== "NO") continue;
      const [[nulls]] = await db.query(
        `SELECT COUNT(*) AS total FROM \`${tableName}\` WHERE \`${column.name}\` IS NULL`
      );
      assert.equal(Number(nulls.total), 0, `${tableName}.${column.name} contains NULL`);
    }
  }
});

test("database: all foreign keys have no orphan rows", async () => {
  for (const tableName of await loadTables()) {
    for (const fk of await loadForeignKeys(tableName)) {
      const [[orphans]] = await db.query(
        `SELECT COUNT(*) AS total FROM \`${tableName}\` child
         LEFT JOIN \`${fk.parentTable}\` parent ON child.\`${fk.columnName}\` = parent.\`${fk.parentColumn}\`
         WHERE child.\`${fk.columnName}\` IS NOT NULL AND parent.\`${fk.parentColumn}\` IS NULL`
      );
      assert.equal(
        Number(orphans.total),
        0,
        `${tableName}.${fk.columnName} has orphans referencing ${fk.parentTable}`
      );
    }
  }
});

test("database: enum columns only hold declared values", async () => {
  for (const tableName of await loadTables()) {
    for (const column of await loadColumns(tableName)) {
      if (column.dataType.toLowerCase() !== "enum") continue;
      const [[invalid]] = await db.query(
        `SELECT COUNT(*) AS total FROM \`${tableName}\` WHERE CAST(\`${column.name}\` AS CHAR) = ''`
      );
      assert.equal(Number(invalid.total), 0, `${tableName}.${column.name} has invalid enum`);
    }
  }
});

test("database: unique indexes hold no duplicates", async () => {
  const [indexes] = await db.query(
    `SELECT TABLE_NAME AS tableName, INDEX_NAME AS indexName,
            GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS columnList
     FROM information_schema.STATISTICS
     WHERE TABLE_SCHEMA = ? AND NON_UNIQUE = 0
     GROUP BY TABLE_NAME, INDEX_NAME`,
    [SCHEMA]
  );
  for (const index of indexes) {
    const columnList = index.columnList.split(",").map((c) => `\`${c}\``).join(",");
    const [duplicates] = await db.query(
      `SELECT COUNT(*) AS total FROM \`${index.tableName}\`
       GROUP BY ${columnList} HAVING total > 1`
    );
    assert.equal(duplicates.length, 0, `${index.tableName}.${index.indexName} has duplicates`);
  }
});

test("database: every table accepts a valid insert (rolled back, no data left behind)", async (t) => {
  for (const tableName of await loadTables()) {
    const [[before]] = await db.query(`SELECT COUNT(*) AS total FROM \`${tableName}\``);
    const columns = await loadColumns(tableName);
    const foreignKeys = await loadForeignKeys(tableName);
    const outcome = await insertAndRollback(tableName, columns, foreignKeys);
    if (outcome.skipped) {
      t.diagnostic(`skipped insert for ${tableName}: parent table empty`);
    } else {
      assert.equal(outcome.affectedRows, 1, `${tableName} insert failed`);
    }
    const [[after]] = await db.query(`SELECT COUNT(*) AS total FROM \`${tableName}\``);
    assert.equal(Number(after.total), Number(before.total), `${tableName} not rolled back`);
  }
});

test("database: foreign keys reject rows pointing to missing parents", async () => {
  for (const tableName of await loadTables()) {
    const foreignKeys = await loadForeignKeys(tableName);
    if (!foreignKeys.length) continue;
    const columns = await loadColumns(tableName);
    const row = await buildInsertRow(tableName, columns, foreignKeys);
    if (row === null) continue;
    row[foreignKeys[0].columnName] = 2147483000;
    const connection = await db.getConnection();
    try {
      await connection.beginTransaction();
      const names = Object.keys(row);
      const sql = `INSERT INTO \`${tableName}\` (${names.map((n) => `\`${n}\``).join(",")}) VALUES (${names.map(() => "?").join(",")})`;
      await assert.rejects(
        connection.query(sql, names.map((n) => row[n])),
        (error) => /foreign key|constraint/i.test(error.message),
        `${tableName} accepted an orphan row`
      );
    } finally {
      await connection.rollback();
      connection.release();
    }
  }
});
