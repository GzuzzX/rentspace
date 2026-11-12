-- RentSpace (lean) — MySQL 8.0.16+
DROP DATABASE IF EXISTS rentspace;
CREATE DATABASE rentspace CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE rentspace;

CREATE TABLE users (
  id            VARCHAR(40)  PRIMARY KEY,
  role          ENUM('renter','owner','admin') NOT NULL,
  name          VARCHAR(120) NOT NULL,
  email         VARCHAR(190) NOT NULL UNIQUE,
  password_hash VARCHAR(100) NOT NULL,           -- bcrypt
  phone         VARCHAR(20)  NOT NULL DEFAULT '',
  bank_info     VARCHAR(190) NOT NULL DEFAULT '',
  active        BOOLEAN      NOT NULL DEFAULT TRUE
);

CREATE TABLE spaces (
  id            VARCHAR(40)  PRIMARY KEY,
  owner_id      VARCHAR(40)  NOT NULL,
  name          VARCHAR(160) NOT NULL,
  category      VARCHAR(60)  NOT NULL,
  location      VARCHAR(190) NOT NULL,
  price         INT          NOT NULL CHECK (price > 0),     -- baht/hour
  capacity      INT          NOT NULL CHECK (capacity > 0),
  description   TEXT         NOT NULL,
  image         VARCHAR(500) NOT NULL DEFAULT '',
  amenities     JSON         NOT NULL,                       -- ["Wi-Fi","โปรเจกเตอร์"]
  -- 7 entries, Mon..Sun: [{"open":true,"start":540,"end":1080}, ...]
  hours         JSON         NOT NULL,
  status        ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
  review_reason TEXT NULL,
  KEY (owner_id), KEY (status, category),
  FOREIGN KEY (owner_id) REFERENCES users(id)
);

CREATE TABLE blocked_periods (
  id       VARCHAR(40)  PRIMARY KEY,
  space_id VARCHAR(40)  NOT NULL,
  start_at DATETIME     NOT NULL,
  end_at   DATETIME     NOT NULL,
  reason   VARCHAR(255) NOT NULL,
  CHECK (end_at > start_at),
  FOREIGN KEY (space_id) REFERENCES spaces(id) ON DELETE CASCADE
);

CREATE TABLE favorites (
  user_id  VARCHAR(40) NOT NULL,
  space_id VARCHAR(40) NOT NULL,
  PRIMARY KEY (user_id, space_id),
  FOREIGN KEY (user_id)  REFERENCES users(id)  ON DELETE CASCADE,
  FOREIGN KEY (space_id) REFERENCES spaces(id) ON DELETE CASCADE
);

-- time fields are minutes since midnight (600 = 10:00)
-- platform fee = 5% of rent_amount, owner gets the rest: calculate in code
CREATE TABLE bookings (
  id            VARCHAR(40)  PRIMARY KEY,
  space_id      VARCHAR(40)  NOT NULL,
  owner_id      VARCHAR(40)  NOT NULL,
  renter_id     VARCHAR(40)  NOT NULL,
  space_name    VARCHAR(160) NOT NULL,              -- snapshot
  booking_date  DATE         NOT NULL,
  start_minutes SMALLINT     NOT NULL,
  end_minutes   SMALLINT     NOT NULL,
  days_count    TINYINT      NOT NULL DEFAULT 1,
  attendees     INT          NOT NULL DEFAULT 1,
  zone          VARCHAR(120) NOT NULL DEFAULT 'โซนหลัก (พื้นที่มาตรฐาน)',
  renter_note   TEXT NULL,
  rent_amount   INT          NOT NULL,              -- snapshot
  status ENUM('owner_review','payment_due','slip_review','confirmed',
              'slip_rejected','owner_rejected','completed','canceled')
         NOT NULL DEFAULT 'owner_review',
  reason        TEXT NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  approved_at      DATETIME NULL,
  slip_rejected_at DATETIME NULL,
  confirmed_at     DATETIME NULL,
  completed_at     DATETIME NULL,
  end_date DATE GENERATED ALWAYS AS (DATE_ADD(booking_date, INTERVAL days_count-1 DAY)) STORED,
  KEY (space_id, booking_date), KEY (renter_id), KEY (owner_id), KEY (status),
  FOREIGN KEY (space_id)  REFERENCES spaces(id),
  FOREIGN KEY (owner_id)  REFERENCES users(id),
  FOREIGN KEY (renter_id) REFERENCES users(id),
  CHECK (days_count BETWEEN 1 AND 14),
  CHECK (attendees >= 1),
  CHECK (start_minutes >= 0 AND end_minutes <= 1440
         AND end_minutes - start_minutes BETWEEN 60 AND 720)
);

-- One payment per booking. Create the row when the owner approves the booking.
CREATE TABLE payments (
  booking_id  VARCHAR(40) PRIMARY KEY,
  amount      INT         NOT NULL CHECK (amount > 0),   -- what the renter pays
  paid_out_at DATETIME    NULL,                          -- when admin paid the owner (once)
  FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE
);

-- Every slip the renter uploads for a payment; latest slip = highest id
CREATE TABLE payment_slips (
  id               BIGINT AUTO_INCREMENT PRIMARY KEY,
  booking_id       VARCHAR(40)  NOT NULL,
  file_name        VARCHAR(255) NOT NULL,
  image_data       MEDIUMBLOB   NOT NULL,            -- JPG/PNG, max 5 MB
  note             TEXT NULL,
  submitted_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  rejection_reason TEXT NULL,
  CHECK (OCTET_LENGTH(image_data) BETWEEN 1 AND 5242880),
  FOREIGN KEY (booking_id) REFERENCES payments(booking_id) ON DELETE CASCADE
);

CREATE TABLE reviews (
  booking_id VARCHAR(40) PRIMARY KEY,
  rating     TINYINT     NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment    TEXT        NOT NULL,
  created_at DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (booking_id) REFERENCES bookings(id) ON DELETE CASCADE
);

CREATE TABLE issues (
  id          VARCHAR(40)  PRIMARY KEY,
  reporter_id VARCHAR(40)  NOT NULL,
  subject     VARCHAR(255) NOT NULL,
  detail      TEXT         NOT NULL,
  closed      BOOLEAN      NOT NULL DEFAULT FALSE,
  resolution  TEXT NULL,
  created_at  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (reporter_id) REFERENCES users(id)
);

-- No double booking (same minute window on every day of a multi-day booking)
DELIMITER $$
CREATE TRIGGER trg_no_overlap BEFORE INSERT ON bookings FOR EACH ROW
BEGIN
  DECLARE lock_id VARCHAR(40);
  DECLARE hit VARCHAR(40);
  IF NEW.status NOT IN ('owner_rejected','canceled') THEN
    SELECT id INTO lock_id FROM spaces WHERE id = NEW.space_id FOR UPDATE;
    SELECT id INTO hit FROM bookings
     WHERE space_id = NEW.space_id
       AND status NOT IN ('owner_rejected','canceled')
       AND booking_date <= DATE_ADD(NEW.booking_date, INTERVAL NEW.days_count-1 DAY)
       AND end_date >= NEW.booking_date
       AND start_minutes < NEW.end_minutes AND end_minutes > NEW.start_minutes
     LIMIT 1;
    IF hit IS NOT NULL THEN
      SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'ช่วงเวลานี้มีการจองแล้ว';
    END IF;
  END IF;
END$$
DELIMITER ;

-- Seed (all passwords: demo1234)
INSERT INTO users VALUES
 ('renter-1','renter','มินตรา','renter@demo.com','$2b$10$uljzr/W/vI.xou4dvogiGec4hjaqyi1eFrzjOCS7l5Y9zGsmhNup6','081-234-5678','',1),
 ('renter-2','renter','ธนา','renter2@demo.com','$2b$10$uljzr/W/vI.xou4dvogiGec4hjaqyi1eFrzjOCS7l5Y9zGsmhNup6','082-345-6789','',1),
 ('owner-1','owner','เจ้าของพื้นที่ตัวอย่าง','owner@demo.com','$2b$10$uljzr/W/vI.xou4dvogiGec4hjaqyi1eFrzjOCS7l5Y9zGsmhNup6','089-111-2233','กสิกรไทย 123-4-56789-0',1),
 ('owner-2','owner','เจ้าของ Loft','owner2@demo.com','$2b$10$uljzr/W/vI.xou4dvogiGec4hjaqyi1eFrzjOCS7l5Y9zGsmhNup6','086-999-8877','ไทยพาณิชย์ 987-6-54321-0',1),
 ('admin-1','admin','Admin','admin@demo.com','$2b$10$uljzr/W/vI.xou4dvogiGec4hjaqyi1eFrzjOCS7l5Y9zGsmhNup6','02-000-0000','',1);

SET @h = JSON_ARRAY(
  JSON_OBJECT('open',TRUE,'start',540,'end',1080), JSON_OBJECT('open',TRUE,'start',540,'end',1080),
  JSON_OBJECT('open',TRUE,'start',540,'end',1080), JSON_OBJECT('open',TRUE,'start',540,'end',1080),
  JSON_OBJECT('open',TRUE,'start',540,'end',1080), JSON_OBJECT('open',TRUE,'start',540,'end',1080),
  JSON_OBJECT('open',TRUE,'start',540,'end',1080));

INSERT INTO spaces (id,owner_id,name,category,location,price,capacity,description,image,amenities,hours,status) VALUES
 ('space-1','owner-1','สตูดิโอแสงเหนือ','สตูดิโอ','สุขุมวิท · เขตวัฒนา',850,8,'สตูดิโอโปร่งพร้อมแสงธรรมชาติ เหมาะสำหรับถ่ายภาพและงานสร้างสรรค์','https://images.unsplash.com/photo-1497366754035-f200968a6e72?auto=format&fit=crop&w=1000&q=85',JSON_ARRAY('ไฟสตูดิโอ','Wi-Fi'),@h,'approved'),
 ('space-2','owner-1','ห้องประชุม The Green Room','ห้องประชุม','อารีย์ · พญาไท',550,10,'ห้องประชุมพร้อมจอและไวท์บอร์ด เดินทางสะดวก','https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1000&q=85',JSON_ARRAY('โปรเจกเตอร์','กาแฟ'),@h,'approved'),
 ('space-3','owner-1','ห้องอ่านหนังสือเงียบสงบ','ห้องอ่านหนังสือ','สามย่าน · ปทุมวัน',120,4,'พื้นที่ส่วนตัวพร้อมปลั๊กไฟและอินเทอร์เน็ต','https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=1000&q=85',JSON_ARRAY(),@h,'approved'),
 ('space-4','owner-2','Creative Loft Studio','สตูดิโอ','เจริญกรุง · บางรัก',1200,15,'ลอฟต์สำหรับเวิร์กช็อป ถ่ายทำ และกิจกรรมกลุ่ม','https://images.unsplash.com/photo-1497366811353-6870744d04b2?auto=format&fit=crop&w=1000&q=85',JSON_ARRAY(),@h,'pending');

INSERT INTO bookings (id,space_id,owner_id,renter_id,space_name,booking_date,start_minutes,end_minutes,rent_amount,status,completed_at)
VALUES ('RS-DEMO-COMPLETED','space-2','owner-1','renter-1','ห้องประชุม The Green Room',
        CURDATE() - INTERVAL 1 DAY,600,720,1100,'completed',NOW() - INTERVAL 1 DAY);
INSERT INTO payments (booking_id, amount) VALUES ('RS-DEMO-COMPLETED', 1100);
INSERT INTO reviews (booking_id,rating,comment)
VALUES ('RS-DEMO-COMPLETED',5,'ห้องสะอาด อุปกรณ์ครบ เดินทางสะดวกมาก');
