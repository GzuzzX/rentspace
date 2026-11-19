const fs = require("node:fs");
const path = require("node:path");
const con = require("../db_config");

const SCHEMA = process.env.DB_NAME || "rent_space";
const BACKEND_FILES = ["app.js", "snapshot_builder.js", "booking_guards.js"].map((name) =>
  fs.readFileSync(path.join(__dirname, "..", name), "utf8")
);
const FRONTEND_ROOT = path.join(__dirname, "..", "..", "rentspace-frontend", "lib");

function readDartSources(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) return readDartSources(full);
    return entry.name.endsWith(".dart") ? [fs.readFileSync(full, "utf8")] : [];
  });
}

function toCamelCase(snake) {
  return snake.replace(/_([a-z])/g, (_m, letter) => letter.toUpperCase());
}

function mentions(sources, name) {
  const pattern = new RegExp(`\\b${name}\\b`);
  return sources.some((source) => pattern.test(source));
}

function classifyColumn(backendSources, frontendSources, column) {
  const names = [column, toCamelCase(column)];
  const inBackend = names.some((n) => mentions(backendSources, n));
  const inFrontend = names.some((n) => mentions(frontendSources, n));
  return { inBackend, inFrontend };
}

async function main() {
  const frontendSources = readDartSources(FRONTEND_ROOT);
  const [rows] = await con.promise().query(
    `SELECT TABLE_NAME AS tableName, COLUMN_NAME AS columnName
     FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = ? ORDER BY TABLE_NAME, ORDINAL_POSITION`,
    [SCHEMA]
  );
  const lines = ["table,column,backend,frontend"];
  for (const row of rows) {
    const { inBackend, inFrontend } = classifyColumn(BACKEND_FILES, frontendSources, row.columnName);
    lines.push(`${row.tableName},${row.columnName},${inBackend ? "Y" : "N"},${inFrontend ? "Y" : "N"}`);
  }
  console.log(lines.join("\n"));
  await con.promise().end();
}

main().catch((error) => {
  console.error(error.message);
  process.exitCode = 1;
});
