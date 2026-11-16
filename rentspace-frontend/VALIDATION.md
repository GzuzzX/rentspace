# ผลตรวจฉบับส่งมอบ — 16 พฤศจิกายน 2026

ขอบเขตงานรอบนี้: Full-stack Flutter (`rentspace-frontend`) เชื่อมต่อ Node.js + Express REST API (`backend/`) และฐานข้อมูล MySQL (`rent_space`) รองรับการยืนยันตัวตนด้วย JWT (`flutter_secure_storage` / `TokenService`) การทดสอบ UI ด้วย Mocktail ในโหมดออฟไลน์ การทดสอบ Unit Logic แบบออฟไลน์ และ Live Integration กับ Backend จริง

สภาพแวดล้อม: Windows, Flutter `3.44.8`, Dart `3.12.2`, Node.js `v24.19.0`, MySQL (`rent_space`)

| การตรวจ | ผล |
|---|---|
| `flutter analyze` (`flutter_lints`) | ผ่าน — `No issues found` |
| `flutter test` (โหมดออฟไลน์: Logic + Image decode + Offline domain) | ผ่าน `27` เคส (ข้าม Live Backend API `16` เคสเมื่อไม่เปิด backend เพื่อรองรับการรันออฟไลน์/CI) |
| `flutter test --dart-define=RUN_LIVE_TESTS=true` (เปิด `backend` ที่ `http://localhost:3001/api`) | ผ่านครบ **43 tests passed** (`0` failed, `0` skipped) |
| `flutter build web` | ผ่าน — `Built build\web` |
| `npm test` (ใน `backend/`) | ผ่าน **11 tests passed** (`app.test.js` `7` เคส, `privacy.test.js` `4` เคส) |

## ลักษณะหน้าจอ

แอปจัดวางเลย์เอาต์คอลัมน์เดียวสำหรับมือถือ (`top bar` ด้านบน + `NavigationBar` ด้านล่างแยกเมนูตามบทบาท: ผู้เช่า 4 เมนู [`ค้นหา`, `การจอง`, `รายการโปรด`, `โปรไฟล์`], เจ้าของพื้นที่ 5 เมนู [`ภาพรวม`, `พื้นที่`, `การจอง`, `รายรับ`, `โปรไฟล์`], ผู้ดูแลระบบ 5 เมนู [`ภาพรวม`, `ตรวจสอบ`, `การเงิน`, `ผู้ใช้`, `โปรไฟล์`]) และสลับโหมดสว่าง/มืดได้จาก top bar (ค่าเริ่มต้นโหมดสว่าง)

ธีม (`lib/ui/theme.dart`) ใช้โทเค็นสีตามชุดธีม OpenSEO daisyUI ทั้งโหมดสว่างและมืด หัวเรื่องใหญ่ขนาด `28px` / `FontWeight.w800` พร้อมสีสถานะ semantic สำหรับป้ายกำกับและการแจ้งเตือน

บนหน้าจอที่มีความกว้างเกิน `430px` (`kMobileMaxWidth = 430`, `kMobileMaxHeight = 932`) `RentSpaceApp` (`lib/app.dart`) จะครอบ UI ไว้ในกรอบมือถือ `_MobileFrame` กลางจอเพื่อจำลองหน้าจอมือถือบนเดสก์ท็อป

## โครงสร้างโลจิกและการเชื่อมต่อ

- `lib/services/api_client.dart` และ `lib/services/token_service.dart` — สื่อสารกับ REST API (`API_BASE_URL` ค่าเริ่มต้น `http://localhost:3001/api`) แนบ Bearer JWT และกู้คืน session อัตโนมัติตอนเปิดแอป
- `lib/controllers/` (`AuthController`, `SpaceController`, `BookingController`, `PaymentController`) — รองรับการส่งเข้าผ่าน constructor ของหน้า UI เพื่อสลับใช้ Mocktail controllers ใน Widget tests ได้
- `platformFee` (`platformFeePercent = 5`) คำนวณครั้งเดียวตอนสร้าง `Booking` แล้วเก็บไว้ในรายการ — เปลี่ยนอัตราค่าบริการภายหลังไม่กระทบรายการเก่า
- `ReasonKind` แยกความหมายของ `Booking.reason` (`ownerRejected` / `slipRejected` / `canceledByUser` / `expiredBySystem`) แทนการใช้ฟิลด์เดียวแบบกำกวม
- `deadlineHint(now)` บอกเวลาที่เหลือของขั้นตอนที่กำลังรอ (`ownerReview`, `paymentDue`, `slipRejected`)
- ตารางเปลี่ยนสถานะกลาง `BookingStatusFlow` + `Booking.moveTo()` — บังคับให้การเปลี่ยนสถานะผ่านเส้นทางที่อนุญาตจากจุดเดียว

## สิ่งที่ชุดทดสอบและเอกสารตรวจสอบ

- **แผนแบ่งงาน Widget & UI Tests (`docs/widget-tests/` + `test/fixtures/mock_controllers.dart`):** เตรียมเอกสารแบ่งงาน `6` โมดูล (`01-login-page.md` ถึง `06-image-and-responsive.md` และ `README.md` เป้าหมายรวม `29` เคส) พร้อม Mocktail Controller Bundle (`MockAuth`, `MockSpace`, `MockBooking`, `MockPayment`) และ Test Helpers กลางใน `test/fixtures/mock_controllers.dart` สำหรับให้ทีมพัฒนาสร้างไฟล์ทดสอบใน `test/pages/`
- **Offline Logic unit tests (`24` เคสใน `test/logic/`):** `domain_and_store_test.dart` (`14` เคส: Enums/labels/`holdsTime`/`progressStep`, `BookingStatusFlow.nextStates`/`moveTo`, `Booking` fee/net/dates/deadlines/`deadlineHint`, `Availability` `accepts`/`acceptsRange`/`copy`, `AppUser.phoneLabel`, `Space.hasImage`, formatters พ.ศ./บาท/เวลา, `AppStore` role scoping/`navBadges`/`conflicts`/`refresh`/`poll`/`mutate`/`toggleTheme`/`clearSession`, `RemoteStore.applySnapshot`/`decodeImageSafely`, `ApiClient` HTTP/multipart/error mapping ผ่าน `MockClient`, `TokenService`, และ `buildAppTheme` light/dark) และ `controllers_logic_test.dart` (`10` เคส: validation รวม confirmPassword และ magic bytes ไฟล์สั้น, filtering, slot bounds, race guard ตอน `logoutAsync` ระหว่าง `restoreSessionAsync`, error handling และ API mutations ของ `AuthController`, `BookingController`, `SpaceController`, `PaymentController`)
- **Image decode & Live/Offline root tests (`19` เคส):** `test/image_decode_test.dart` (`2` เคส) และ `test/unit_test.dart` (`17` เคส: `16` เคส Live Backend API ร่วมกับ MySQL ครอบคลุม login, spaces, favorites, admin approve/suspend/users, booking/payment/slip/review workflow, availability/blocks, issues และการตรวจ input + `1` เคส Offline Domain Rules)
- **Backend tests (`11` เคสใน `backend/test/`):** `app.test.js` (`7` เคส: Argon2/SHA-256 password verification, role mapping, JWT, live MySQL `/api/state` & `/api/spaces`, multipart upload, security guards/PII leak protection, transactional booking validation) และ `privacy.test.js` (`4` เคส: การซ่อน PII และจำกัด snapshot ตามบทบาท, auth security & token revocation, และ booking guards/permissions)

## ขอบเขตที่ยังไม่ได้ทดสอบในชุดอัตโนมัติรอบนี้

ไฟล์ทดสอบ Widget UI ภายใต้ `test/pages/` ถูกถอดออกและแทนที่ด้วยเอกสารแบ่งงานใน `docs/widget-tests/` (ยังคง Fixture กลางใน `test/fixtures/mock_controllers.dart`), native `main()` entrypoint บนอุปกรณ์จริง, native file picker UI ของระบบปฏิบัติการ Android/iOS จริง, การ build เป็นแพ็กเกจ Android/Windows release และโหลดทดสอบพร้อมกันหลายเครื่อง (รอบนี้ตรวจระดับ Web release build, Unit Logic และ Live API integration tests)

## คำสั่งสำหรับตรวจซ้ำ

```powershell
# 1) รันชุดทดสอบและเซิร์ฟเวอร์ Backend
cd e:\666\backend
npm test
npm start

# 2) ตรวจและ build Frontend (ต้องรันในโฟลเดอร์ root ที่มี pubspec.yaml; เปิดอีกเทอร์มินัลหากต้องการรัน Live tests)
cd e:\666\rentspace-frontend
flutter pub get
flutter analyze
flutter test                                    # รันเคสออฟไลน์ 27 เคส (และ Live 16 เคสหากเปิด backend ไว้)
flutter test --dart-define=RUN_LIVE_TESTS=true  # บังคับรันครบทั้ง 43 เคสกับ http://localhost:3001/api
flutter build web
```

ผล build อยู่ที่ `rentspace-frontend/build/web` ต้องเปิดผ่าน HTTP server ไม่ใช่ดับเบิลคลิก `index.html`

CI workflow ที่แนบมา (`.github/workflows/flutter.yml`, pin Flutter `3.44.8`) รัน `flutter pub get`, `flutter analyze`, `flutter test` และ `flutter build web` เมื่อ push หรือเปิด PR บน GitHub (ยังไม่ได้รัน CI บน GitHub ในรอบตรวจบนเครื่องนี้)
