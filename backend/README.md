# RentSpace Backend (Clean-Room New Folder)

Backend ชุดใหม่ในโฟลเดอร์ `e:\666\backend` สร้างขึ้นใหม่ทั้งหมดตามรูปแบบในบทเรียน **Mobile Programming Laboratory (Week 10: Database & Week 11: Authentication and Authorization)** และเชื่อมต่อกับฐานข้อมูล `rent_space` จาก [`foolgood809-gif/rent-space-db`](https://github.com/foolgood809-gif/rent-space-db)

## โครงสร้างไฟล์

- `db_config.js` — ตั้งค่าการเชื่อมต่อ MySQL (`mysql2`) ไปยังฐานข้อมูล `rent_space`
- `auth_security.js` — จัดการรหัสผ่านด้วย `@node-rs/argon2` (`argon2.hashSync`, `argon2.verifySync`), รองรับรหัสผ่านจาก `rent_space.sql`, และ Middleware `verifyToken(allowedRoles)` ด้วย `jsonwebtoken` (`JWT_SECRET`)
- `schema_bootstrap.js` — ตรวจสอบตารางและคอลัมน์ในฐานข้อมูล `rent_space` ให้อัตโนมัติโดยไม่กระทบข้อมูลเดิม
- `snapshot_builder.js` — แปลงข้อมูลจากตารางใน `rent_space` ให้เข้ากับทั้งแอป Flutter (`rentspace-frontend`) และ REST API มาตรฐาน พร้อมกรองข้อมูลส่วนบุคคล (PII) ตามบทบาทผู้เรียก
- `booking_guards.js` — ตรวจสอบสิทธิ์การเข้าถึงพื้นที่/การจอง (`guardSpaceAccess`, `guardBookingAccess`) และจัดการธุรกรรมสร้างการจอง (`createBookingTransactional`) เพื่อป้องกันเวลาซ้อนทับ เวลาปิดให้บริการ และจำนวนผู้เข้าพักเกินความจุ
- `app.js` — Express API Server หลัก รันที่พอร์ต `3001`
- `database/rent_space.sql` — ไฟล์ SQL รวมชุดเดียว (สคีมาหลัก, ตารางเสริม `auth_sessions` / `room_blocks` / `user_favorites` / `issues`, คอลัมน์ทั้งหมด และข้อมูลตั้งต้น)
- `test/app.test.js` — ชุดทดสอบ Unit Test และ Live MySQL Integration Test
- `test/privacy.test.js` — ชุดทดสอบการซ่อนข้อมูลส่วนบุคคล (PII) และการจำกัด snapshot ตามบทบาทผู้ใช้

## วิธีรันเซิร์ฟเวอร์

```powershell
cd e:\666\backend
npm install
npm start
```

## วิธีรันชุดทดสอบ

```powershell
cd e:\666\backend
npm test
```
