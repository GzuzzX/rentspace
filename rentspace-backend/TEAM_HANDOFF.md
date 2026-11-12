# RentSpace — Backend API & Model Test Handoff (For Flutter Team)

This document explains **everything that was added and changed** in the repository, **what each part does**, and **how the new Node.js + MySQL backend maps to your existing Flutter controllers and models** without breaking any of your current Flutter code.

---

## 1. TL;DR — Did Anything in Flutter Break?

**No.** Your Flutter app (`lib/`) was **not modified at all**:
- [`lib/models/domain.dart`](lib/models/domain.dart) — **Untouched**
- [`lib/data/app_store.dart`](lib/data/app_store.dart) — **Untouched** (still runs in-memory mock data)
- [`lib/controllers/`](lib/controllers/) — **Untouched**
- [`lib/ui/`](lib/ui/) — **Untouched**

### Summary of All Changes in the Repo

| Path | Status | What Changed & Why |
| :--- | :---: | :--- |
| `backend/` | **NEW FOLDER** | Full **Node.js + Express + MySQL REST API** (26 endpoints) matching your Flutter controllers and [`database/rentspace_lite.sql`](database/rentspace_lite.sql). |
| [`test/domain_test.dart`](test/domain_test.dart) | **NEW FILE** | Dedicated **Model Unit Tests** for [`lib/models/domain.dart`](lib/models/domain.dart) (testing enums, `Availability`, `Booking` fee/deadline calculations, `PaymentSlip`, and date/time helpers in pure isolation). |
| [`pubspec.yaml`](pubspec.yaml) | **MODIFIED (2 lines)** | Added `http: ^1.2.1` and `shared_preferences: ^2.2.3` under `dependencies:` so the Flutter team has the HTTP client and JWT storage packages ready when connecting to the backend. *(Run `flutter pub get` after pulling).* |

---

## 2. How the Normalized MySQL DB (`rentspace_lite.sql`) Works With Your Flutter `domain.dart`

Even though the MySQL database ([`database/rentspace_lite.sql`](database/rentspace_lite.sql)) splits data into **9 normalized relational tables**, **you do NOT need to change [`lib/models/domain.dart`](lib/models/domain.dart)**.

The Node.js API handles the SQL `JOIN`s and JSON parsing so the data maps cleanly to your Dart classes:

| Flutter Model (`lib/models/domain.dart`) | MySQL Tables (`database/rentspace_lite.sql`) | What the Node.js API Does |
| :--- | :--- | :--- |
| **`AppUser`** (`id`, `role`, `name`, `email`, `phone`, `bankInfo`, `active`, `Set<String> favorites`) | `users` + `favorites (user_id, space_id)` | `GET /api/auth/me` queries `users` and joins `favorites` to return `favorites: ["space-1", ...]`. Passwords are stored as bcrypt hashes (`password_hash`) in MySQL instead of plain text. |
| **`Space`** (`id`, `ownerId`, `name`, `category`, `location`, `price`, `capacity`, `description`, `image`, `amenities`, `status`, `reviewReason`, `Availability`) | `spaces` + `blocked_periods` | Parses `spaces.amenities` (MySQL `JSON` array) and `spaces.hours` (MySQL `JSON` 7-day array `[{open, start, end}, ...]`). `blocked_periods` stores each `BlockedPeriod` row separately and cascades on delete. |
| **`Booking`** (`id`, `spaceId`, `ownerId`, `renterId`, `spaceName`, `date`, `startMinutes`, `endMinutes`, `days`, `attendees`, `zone`, `renterNote`, `rentAmount`, `status`, `reason`, timestamps, `paidOutAt`, `slips`, `review`) | `bookings` + `payments` + `payment_slips` + `reviews` | `bookings` stores the reservation and timestamps. `end_date` is a MySQL `GENERATED ALWAYS` column (`booking_date + days_count - 1`). When the owner approves a booking, the API creates a row in `payments (booking_id, amount, paid_out_at)`. `GET /api/bookings` `LEFT JOIN`s `payments.paid_out_at`, and `GET /api/bookings/:id` attaches `slips[]` and `review`. |
| **`Booking.platformFee` (5%) & `Booking.ownerNet`** | Calculated in code (no DB column needed) | Your Dart getters (`(rentAmount * 5 / 100).round()` and `rentAmount - platformFee`) continue to calculate this directly from `rentAmount`. |
| **`PaymentSlip`** (`name`, `bytes`, `submittedAt`, `note`, `rejectionReason`) | `payment_slips` (`id`, `booking_id`, `file_name`, `image_data MEDIUMBLOB`, `note`, `submitted_at`, `rejection_reason`) | Uploaded JPG/PNG files (up to 5 MB) are stored as `MEDIUMBLOB` in MySQL and served as raw bytes at `GET /api/payments/:bookingId/slip/:slipId/image`. |
| **`SpaceReview`** (`rating`, `comment`, `createdAt`) | `reviews` (`booking_id` PK, `rating` 1–5, `comment`, `created_at`) | One review per completed booking (`booking_id` is Primary Key). |
| **`Issue`** (`id`, `reporterId`, `subject`, `detail`, `closed`, `resolution`) | `issues` | Stored directly in `issues` table; joined with `users` to include `reporter_name`. |

---

## 3. What Was Added in `backend/` (File-by-File Breakdown)

```text
backend/
  package.json               # Dependencies & npm scripts (npm start, npm run dev)
  .env.example               # Template environment variables
  .env                       # Local DB + JWT config (edit DB_PASSWORD before running)
  src/
    index.js                 # Express server entry point & route mounting
    db.js                    # MySQL2 connection pool (utf8mb4 enabled)
    utils/
      errors.js              # AppError class (backend equivalent of DomainError)
    middleware/
      auth.js                # JWT verification (authenticate) & role guard (requireRole)
    routes/
      auth.js                # Maps to Flutter's AuthController
      spaces.js              # Maps to Flutter's SpaceController
      bookings.js            # Maps to Flutter's BookingController
      payments.js            # Maps to Flutter's PaymentController
      admin.js               # Maps to Admin actions across Auth/Space/Payment controllers
```

### 3.1 How Each Backend Route Maps to Your Flutter Controllers

#### A. `backend/src/routes/auth.js` ↔ `lib/controllers/auth_controller.dart`
| Flutter Method (`AuthController`) | Backend Endpoint | What It Does |
| :--- | :--- | :--- |
| `login(email, password)` | `POST /api/auth/login` | Checks email & `active` status, verifies `bcrypt` password hash, returns `{ token, user }`. *(All seed accounts in `rentspace_lite.sql` use password `demo1234`)*. |
| `register(name, email, password, role, phone)` | `POST /api/auth/register` | Blocks `admin` registration, validates email/phone regex and password length `>= 8`, hashes password with `bcrypt`, inserts into `users`, returns `{ token, userId, role }`. |
| `store.currentUser` | `GET /api/auth/me` | Reads `Authorization: Bearer <token>`, returns user profile + `favorites` list (for renters). |
| `updateProfile(name, email, phone, bankInfo)` | `PUT /api/auth/profile` | Validates fields, checks email uniqueness (`id != currentUser.id`), updates `users`. |
| `changePassword(current, next, confirm)` | `PUT /api/auth/password` | Verifies `currentPassword` against bcrypt hash, checks `newPassword === confirmPassword` & `>= 8` chars, updates `password_hash`. |

#### B. `backend/src/routes/spaces.js` ↔ `lib/controllers/space_controller.dart`
| Flutter Method (`SpaceController`) | Backend Endpoint | What It Does |
| :--- | :--- | :--- |
| `search(...)` | `GET /api/spaces?category=&search=&sort=` | Public endpoint returning `approved` spaces with `owner_name`, `avg_rating`, and `review_count`. Supports `sort=recommended\|priceAsc\|priceDesc\|capacityDesc`. |
| `store.space(id)` | `GET /api/spaces/:id` | Returns a single space with parsed `amenities` and 7-day `hours`. |
| Owner's spaces list | `GET /api/spaces/owner/mine` | Returns all spaces belonging to the logged-in owner (`pending`, `approved`, `rejected`). |
| `save(...)` (Create) | `POST /api/spaces` | *(Owner only)* Validates `price > 0`, `capacity > 0`, creates space with `status = 'pending'`. |
| `save(...)` (Edit) | `PUT /api/spaces/:id` | *(Owner/Admin)* Verifies ownership, updates space details, resets `status = 'pending'` and `review_reason = NULL`. |
| Delete space | `DELETE /api/spaces/:id` | *(Owner/Admin)* Deletes space (cascades to `blocked_periods` and `favorites`). |
| `saveAvailability(id, value)` | `PUT /api/spaces/:id/availability` | *(Owner only)* Updates the 7-day `hours` JSON on `spaces` and replaces the space's rows in `blocked_periods`. |
| `hourlySlots()` + `busySlotLabels()` | `GET /api/spaces/:id/slots?date=YYYY-MM-DD` | Returns `{ open, slots: [{start, end, available}], busyLabels: [...] }` for the given date. |
| `favorite(id)` | `POST /api/spaces/:id/favorite` | *(Renter only)* Toggles `(user_id, space_id)` in `favorites` table, returns `{ favorited: true/false }`. |
| `reviewedBookings(spaceId)` | `GET /api/spaces/:id/reviews` | Returns all reviews (`rating`, `comment`, `created_at`, `renter_name`) for a space. |

#### C. `backend/src/routes/bookings.js` ↔ `lib/controllers/booking_controller.dart`
| Flutter Method (`BookingController`) | Backend Endpoint | What It Does |
| :--- | :--- | :--- |
| `store.visibleBookings()` | `GET /api/bookings?status=&spaceId=` | Automatically filters by role (`renter_id` for renters, `owner_id` for owners, all for admin) and `LEFT JOIN`s `payments.paid_out_at`. |
| `store.booking(id)` | `GET /api/bookings/:id` | Returns booking details + `slips[]` metadata + `review` object (verifies caller is renter, owner, or admin). |
| `create(...)` | `POST /api/bookings` | *(Renter only)* Validates `60 <= end - start <= 720` mins, `1 <= days <= 14`, checks space is `approved`, checks multi-day overlap conflicts (also enforced by MySQL trigger `trg_no_overlap`), snapshots `space_name` and `rent_amount = price * ceil((end-start)/60) * days`, inserts with status `owner_review`. |
| `ownerReview(id, true, '')` | `POST /api/bookings/:id/approve` | *(Owner only)* Re-checks conflicts, updates status to `payment_due`, sets `approved_at = NOW()`, and creates the `payments (booking_id, amount)` row. |
| `ownerReview(id, false, reason)` | `POST /api/bookings/:id/reject` | *(Owner only)* Requires non-empty `reason`, sets status to `owner_rejected`. |
| `cancel(id, reason)` | `POST /api/bookings/:id/cancel` | *(Renter/Owner/Admin)* Cancels booking if status is `owner_review`, `payment_due`, `slip_review`, or `slip_rejected`. |
| `submitReview(id, rating, comment)` | `POST /api/bookings/:id/review` | *(Renter only)* Validates `rating` 1–5 and non-empty `comment` on `completed` bookings; prevents duplicate reviews. |

#### D. `backend/src/routes/payments.js` ↔ `lib/controllers/payment_controller.dart`
| Flutter Method (`PaymentController`) | Backend Endpoint | What It Does |
| :--- | :--- | :--- |
| `submit(id, name, bytes, note)` | `POST /api/payments/:bookingId/slip` | *(Renter only)* Accepts `multipart/form-data` (`file` JPG/PNG ≤ 5 MB, `note`), inserts `MEDIUMBLOB` into `payment_slips`, sets booking status to `slip_review`. |
| Slip image viewer | `GET /api/payments/:bookingId/slip/:slipId/image` | Streams the raw `image/png` or `image/jpeg` bytes from `payment_slips.image_data` (works directly with Flutter `Image.memory` / `Image.network`). |
| `review(id, approve, reason)` | `POST /api/payments/:bookingId/review` | *(Admin only)* If `approve: true`, sets booking `confirmed` (`confirmed_at = NOW()`). If `approve: false`, requires `reason`, sets booking `slip_rejected` (`slip_rejected_at = NOW()`), and records `rejection_reason` on the latest slip. |
| `payout(id)` | `POST /api/payments/:bookingId/payout` | *(Admin only)* Verifies booking is `completed` and not yet paid out, sets `payments.paid_out_at = NOW()`. |

#### E. `backend/src/routes/admin.js` (Admin Portal Endpoints)
- `GET /api/admin/spaces?status=` — List all spaces across all statuses
- `PUT /api/admin/spaces/:id/approve` — Approve a pending space (`status = 'approved'`)
- `PUT /api/admin/spaces/:id/reject` — Reject/suspend a space with mandatory `reason` (`status = 'rejected'`)
- `PUT /api/admin/spaces/:id/activate` — Re-activate a rejected space (`status = 'approved'`)
- `GET /api/admin/users` — List all users
- `PUT /api/admin/users/:id/toggle` — Toggle `user.active` (blocks admin from disabling their own account)
- `GET /api/admin/bookings?status=` — List all bookings with `renter_name` and `owner_name`
- `POST /api/admin/issues` — File an issue (`subject`, `detail`) *(any logged-in user)*
- `GET /api/admin/issues` — List all issues *(admin only)*
- `PUT /api/admin/issues/:id/close` — Close an issue with mandatory `resolution` *(admin only)*

---

## 4. What Was Added in `test/domain_test.dart` (Model Unit Tests)

Previously, the repository had:
1. [`test/controllers_test.dart`](test/controllers_test.dart) — Controller & business logic tests
2. [`test/widget_test.dart`](test/widget_test.dart) — UI widget tests

However, there was no dedicated unit test file for the **Model layer** ([`lib/models/domain.dart`](lib/models/domain.dart)). We added [`test/domain_test.dart`](test/domain_test.dart) so all 3 MVC layers (Model, Controller, Widget) have dedicated test suites.

### What `test/domain_test.dart` Covers (50+ assertions):
1. **Enums & Thai Labels:** `UserRole.label`, `SpaceStatus.label`, `SpaceSort.label`, `BookingStatus.label`
2. **`BookingStatus.holdsTime`:** Verifies `ownerReview`, `paymentDue`, `slipReview`, `confirmed`, `slipRejected`, and `completed` hold time slots (`true`), while `ownerRejected` and `canceled` free the slot (`false`).
3. **`BookingStatus.progressStep`:** Verifies the 4-step progress bar mapping (`0` → `1` → `2` → `3`).
4. **24-Hour SLA Constants:** Verifies `ownerResponseWindow`, `paymentWindow`, `slipResubmitWindow`, and `autoCompleteWindow`.
5. **`AppUser` Model:** `phoneLabel` fallback (`ไม่ระบุ` when empty/whitespace), default `active = true`, and `favorites` set initialization.
6. **`DayHours` & `Availability` Model:**
   - Default hours (`09:00–18:00` / `540–1080`) and deep copy (`Availability.copy()`) independence.
   - `Availability.accepts(date, start, end)` for valid slots, closed weekdays, out-of-hours slots, invalid/reversed intervals, overlapping `BlockedPeriod`s, and adjacent `BlockedPeriod`s.
   - `Availability.acceptsRange(date, start, end, days: N)` for multi-day spans and 1–30 day bounds.
7. **`Booking` Financial & Date Calculations:**
   - `platformFee` (5% rounded) and `ownerNet` (`platformFee + ownerNet == rentAmount`).
   - `startsAt`, `endsAt`, `endDate`, and `autoCompleteAt` for single-day and multi-day bookings.
   - `coversDate()` across multi-day ranges regardless of time-of-day.
   - Deadline getters (`ownerResponseDeadline`, `paymentDeadline`, `slipResubmitDeadline`) and `effectiveSlipResubmitDeadline` (picks the earlier of `startsAt` or `slipResubmitDeadline`).
   - `latestSlip` getter on `Booking.slips`.
8. **`PaymentSlip` Defensive Byte Copy:** Ensures mutating the input `Uint8List` after creating a `PaymentSlip` does not mutate `slip.bytes`.
9. **Date/Time Formatting Helpers:** `dateOnly()`, `atMinute()`, `timeLabel()`, `dateLabel()`, `dateTimeLabel()`, and `bookingWhen()`.

---

## 5. Quick Start Guide for Teammates

### Running Flutter Tests
```powershell
flutter pub get
flutter test
```
To run each test layer individually:
```powershell
flutter test test/domain_test.dart       # Model unit tests
flutter test test/controllers_test.dart  # Controller unit tests
flutter test test/widget_test.dart       # UI widget tests
```

### Running the Node.js + MySQL Backend
1. **Import the database schema & seed data into MySQL 8.0+:**
   ```powershell
   mysql -u root -p < database/rentspace_lite.sql
   ```
2. **Configure [`backend/.env`](backend/.env):**
   Set `DB_PASSWORD` to your local MySQL root password.
3. **Start the API server:**
   ```powershell
   cd backend
   npm install
   npm run dev
   ```
4. **Verify health check:**
   Open `http://localhost:3000/api/health` → returns `{"status":"ok","time":"..."}`.
