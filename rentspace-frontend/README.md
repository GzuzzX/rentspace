# RentSpace frontend

Flutter เชื่อม Node.js API และ MySQL จริงเป็นค่าเริ่มต้น ดู [วิธีรันทั้งระบบ](../README.md)

## สิ่งที่เชื่อมแล้ว

- เข้าสู่ระบบ สมัคร โปรไฟล์ เปลี่ยนรหัสผ่าน และจัดการผู้ใช้
- JWT ใน secure storage และตรวจ token กับ backend เมื่อคืนเซสชัน
- ค้นหา รายการโปรด เพิ่มและแก้ไขพื้นที่ เวลาทำการ ช่วงปิด และตรวจประกาศ
- จอง เจ้าของตอบรับ ยกเลิก จบรายการ และรีวิว
- ส่งสลิปแบบ multipart ประวัติสลิป ตรวจสลิป และบันทึกจ่ายเจ้าของ
- รายงานปัญหาและปิดรายงาน
- โหลดข้อมูลใหม่ทุก 30 วินาทีและหลังบันทึก พร้อมแสดงสถานะรอและข้อผิดพลาด

## โครงสร้าง

- services/api_client.dart: JSON, multipart, Bearer token และ timeout
- services/remote_store.dart: แปลงข้อมูล backend เป็น model สำหรับ UI
- data/app_store.dart: cache ตามสิทธิ์ที่โหลดจาก MySQL ผ่าน API เท่านั้น (ไม่มีข้อมูลจำลองในแอป)
- controllers: เรียก backend API และอัปเดต snapshot จากฐานข้อมูลโดยตรง
- AppStore(): เชื่อม ApiClient เป็นค่าเริ่มต้นและโหมดเดียวของแอป

## รันและตรวจสอบ

Flutter 3.44.8 / Dart 3.12.2

```powershell
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3001/api
flutter analyze
flutter test
flutter build web
```

URL ต้องรวม /api; เปลี่ยน dart-define แล้วต้องรันหรือ build ใหม่

## ขอบเขต

- บันทึกจ่ายเป็นการเก็บสถานะ ไม่มีการโอนเงินจริงหรือตรวจสลิปกับธนาคารอัตโนมัติ
- อัปเดตผ่าน polling ไม่ใช่ WebSocket
- Snapshot รวมภาพสลิปตามสิทธิ์ หากข้อมูลมากควรเพิ่ม pagination และแยกโหลดภาพ
- Backend แปลงเวลาและขอบเขตวันเป็นเวลาไทย (`Asia/Bangkok`, `UTC+7`) อัตโนมัติ ไม่ขึ้นกับ timezone ของเครื่องเซิร์ฟเวอร์
- Android/Windows ต้องทดสอบเพิ่มเติมบนอุปกรณ์เป้าหมาย
