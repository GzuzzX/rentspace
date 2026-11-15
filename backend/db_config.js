const mysql = require("mysql2");

const dbConfig = {
  host: process.env.DB_HOST || "localhost",
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "",
  database: process.env.DB_NAME || "rent_space",
  waitForConnections: true,
  connectionLimit: 10,
  timezone: "+07:00",
};

const con = mysql.createPool(dbConfig);

con.on("error", (err) => {
  console.error("Database connection pool error:", err.message);
});

module.exports = con;
