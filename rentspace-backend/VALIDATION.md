# ผลตรวจฉบับส่งมอบ — 7 พฤศจิกายน 2026

สภาพแวดล้อม: Windows, Flutter 3.44.8, Dart 3.12.2

| การตรวจ | ผล |
|---|---|
| Dart analyzer (กฎ flutter_lints ของโปรเจกต์) | ผ่าน — No issues found |
| Unit tests สำหรับ Controllers และ Models ที่เกี่ยวข้อง | ผ่าน 33 เคส |
| Widget tests | ผ่าน 9 เคส |
| รวม flutter test | **42 tests passed** |
| Flutter web release build | ผ่าน — Built build/web (38.0 วินาที), Wasm dry run ผ่าน |

UI ใช้ชุดสีขาว-เทา/น้ำเงินหม่นแบบ daisyUI (OpenSEO-inspired) มี sidebar 240px บนเดสก์ท็อป, top bar + drawer + bottom navigation บนมือถือ และสลับโหมดสว่าง/มืดได้จากปุ่มใน sidebar/top bar (ค่าเริ่มต้นโหมดสว่าง)

Widget tests ตรวจ login ว่าง, กรอกฟอร์มเพิ่มพื้นที่แล้วสลับบทบาทให้ Admin อนุมัติ, กดจองผ่าน checkout จนเปิดรายละเอียดสำเร็จ และเมนูทุกบทบาทที่ความกว้าง 360/1280 โดยตรวจ exception จาก layout ด้วย

Unit tests ตรวจเวลาชน/ต่อกัน, พื้นที่ชื่อซ้ำ, เปลี่ยนชื่อพื้นที่, เวลาในอดีต/ผิดลำดับ, วันปิดเฉพาะพื้นที่, draft ก่อนบันทึก, สิทธิ์ผู้ใช้, การอนุมัติประกาศ, การคำนวณราคา/ค่าบริการ, สลิปไม่ผ่านและส่งใหม่, ข้ามขั้นตอน, ไฟล์ผิดชนิด/ขนาด, จบการใช้งานและจ่ายครั้งเดียว, บัญชี/โปรไฟล์, รายงานปัญหา, จำกัดเวลา 60 นาที–12 ชม., ยกเลิกอัตโนมัติเมื่อเลยกำหนดตอบรับ/ชำระเงิน, จบรายการอัตโนมัติ และบันทึกกิจกรรมออกจากระบบครั้งเดียว

ขอบเขตที่ยังไม่ได้ทดสอบ: native file picker บนอุปกรณ์จริง, Android/Windows release build, การใช้งานพร้อมกันหลายเครื่อง และระบบ backend (ไม่มีใน Sprint นี้) Widget tests ไม่เรียกภาพภายนอกเพื่อให้ผลทดสอบไม่ขึ้นกับเครือข่าย

คำสั่งสำหรับตรวจซ้ำ:

```powershell
flutter pub get
flutter analyze
flutter test
flutter build web
```

CI workflow ที่แนบมาจะรันเมื่อ push หรือเปิด PR ใน GitHub ยังไม่ได้รัน CI บน GitHub ในงานนี้
