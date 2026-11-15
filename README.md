# RentSpace — Flutter + Node.js (`e:\666\backend`) + MariaDB/MySQL (`rent_space`)

Frontend เชื่อม API จริงเป็นค่าเริ่มต้น ข้อมูลทั้งหมดอ่าน/เขียนกับฐานข้อมูล `rent_space` (`foolgood809-gif/rent-space-db`)

## รันทั้งระบบ

1. เปิด MariaDB/MySQL (เช่น XAMPP port `3306`) และนำเข้าฐานข้อมูลไฟล์เดียว (หากยังไม่มี):
   - `backend/database/rent_space.sql` (รวมสคีมาหลัก, ตารางเสริม, คอลัมน์ทั้งหมด และข้อมูลตัวอย่างตั้งต้นไว้ในไฟล์เดียวแล้ว)
2. รัน Backend (`e:\666\backend`):
   ```powershell
   cd backend
   npm install
   npm start
   ```
3. รัน Frontend (`e:\666\rentspace-frontend`):
   ```powershell
   cd rentspace-frontend
   flutter pub get
   flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3001/api
   ```

## ตรวจสอบ

- Backend tests: `cd backend && npm test`
- Frontend: `cd rentspace-frontend && flutter analyze && flutter test`
