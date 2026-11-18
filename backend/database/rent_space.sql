-- Unified RentSpace Database Schema & Initial Data
-- Includes base schema, auth_sessions, room_blocks, user_favorites, issues, and app columns
-- Target: MariaDB / MySQL (utf8mb4)

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

CREATE DATABASE IF NOT EXISTS `rent_space`
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;
USE `rent_space`;

-- --------------------------------------------------------
-- Table structure for table `users`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `users` (
  `user_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `email` varchar(100) NOT NULL,
  `phone` varchar(30) DEFAULT '',
  `password_hash` varchar(255) NOT NULL,
  `role` enum('customer','owner','admin') NOT NULL DEFAULT 'customer',
  `status` enum('active','suspended') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `bank_info` varchar(255) DEFAULT '',
  PRIMARY KEY (`user_id`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `email` (`email`)
) ENGINE=InnoDB AUTO_INCREMENT=1006 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `users` (`user_id`, `name`, `username`, `email`, `phone`, `password_hash`, `role`, `status`, `created_at`) VALUES
(1001, 'ภูมิ ศรีสุข (Owner)', 'owner01', 'owner01@rentspace.test', '089-876-5432', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'owner', 'active', '2026-11-05 07:46:46'),
(1002, 'ณัฐ วงศ์ดี (Renter)', 'renter01', 'renter01@rentspace.test', '081-234-5678', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'customer', 'active', '2026-11-05 07:46:46'),
(1003, 'ผู้ดูแลระบบ (Admin)', 'admin01', 'admin01@rentspace.test', '02-999-8888', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'admin', 'active', '2026-11-05 07:46:46'),
(1004, 'มินท์ กมลวรรณ', 'mint_k', 'mint@rentspace.test', '082-333-4444', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'customer', 'active', '2026-11-05 07:46:46'),
(1005, 'แพรว ใจงาม', 'owner02', 'owner02@rentspace.test', '086-555-7777', '5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8', 'owner', 'suspended', '2026-11-05 07:46:46');

-- --------------------------------------------------------
-- Table structure for table `spaces`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `spaces` (
  `space_id` int(11) NOT NULL AUTO_INCREMENT,
  `owner_id` int(11) NOT NULL,
  `title` varchar(150) NOT NULL,
  `description` text DEFAULT NULL,
  `location` varchar(255) NOT NULL,
  `price_per_day` decimal(10,2) NOT NULL,
  `category` varchar(50) DEFAULT 'meeting_room',
  `capacity` int(11) DEFAULT 10,
  `image_url` longtext DEFAULT NULL,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  `rating` decimal(3,2) NOT NULL DEFAULT 4.80,
  `rating_count` int(11) NOT NULL DEFAULT 1,
  `status` enum('pending','approved','rejected','hidden') NOT NULL DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `hours_json` text DEFAULT NULL,
  `amenities_json` text DEFAULT NULL,
  `review_reason` text DEFAULT NULL,
  PRIMARY KEY (`space_id`),
  KEY `owner_id` (`owner_id`),
  CONSTRAINT `spaces_ibfk_1` FOREIGN KEY (`owner_id`) REFERENCES `users` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2011 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `spaces` (`space_id`, `owner_id`, `title`, `description`, `location`, `price_per_day`, `category`, `capacity`, `image_url`, `is_active`, `rating`, `rating_count`, `status`, `created_at`) VALUES
(2001, 1001, 'ห้องประชุมสว่างใจ', 'ห้องประชุมพร้อมจอสมาร์ททีวีและอินเทอร์เน็ตความเร็วสูง', '88 ซ.อารีย์ 4 พญาไท กรุงเทพฯ', 350.00, 'ห้องประชุม', 10, '/uploads/meeting.jpg', 1, 5.00, 1, 'approved', '2026-11-05 07:46:46'),
(2002, 1001, 'The Quiet Nook (ห้องอ่านหนังสือ)', 'ห้องอ่านหนังสือเงียบสงบ แสงธรรมชาติ เหมาะสำหรับอ่านหนังสือหรือติวสอบ', '12 ถ.พระราม 4 ปทุมวัน กรุงเทพฯ', 120.00, 'Co-working', 4, '/uploads/study.jpg', 1, 0.00, 0, 'approved', '2026-11-05 07:46:46'),
(2005, 1001, 'พื้นที่จัดเวิร์กช็อป', 'พื้นที่อเนกประสงค์สำหรับกิจกรรมกลุ่ม เวิร์กช็อป และสัมมนา', 'เชียงใหม่ นิมมานเหมินท์', 3200.00, 'พื้นที่อีเวนต์', 30, '/uploads/meeting.jpg', 1, 0.00, 0, 'pending', '2026-11-05 07:46:46'),
(2007, 1005, 'ห้อง thinkstation', 'ห้องประชุมพร้อมโต๊ะทำงานและอุปกรณ์มาตรฐาน', 'ch', 800.00, 'ห้องประชุม', 10, NULL, 1, 0.00, 0, 'pending', '2026-11-05 08:19:51'),
(2008, 1001, 'ห้อง nitro', 'on you work.', 'chin', 1500.00, 'ห้องประชุม', 10, NULL, 1, 0.00, 0, 'approved', '2026-11-05 08:23:37');

-- --------------------------------------------------------
-- Table structure for table `amenities`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `amenities` (
  `amenity_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `icon` varchar(100) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`amenity_id`),
  UNIQUE KEY `uq_amenities_name` (`name`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `amenities` (`amenity_id`, `name`, `description`, `icon`, `created_at`) VALUES
(1, 'Wi-Fi', 'อินเทอร์เน็ตไร้สาย', 'wifi', '2026-11-11 11:35:04'),
(2, 'ที่จอดรถ', 'มีพื้นที่จอดรถสำหรับผู้เช่า', 'parking', '2026-11-11 11:35:04'),
(3, 'โปรเจกเตอร์', 'มีโปรเจกเตอร์สำหรับนำเสนอ', 'projector', '2026-11-11 11:35:04'),
(4, 'เครื่องปรับอากาศ', 'มีเครื่องปรับอากาศ', 'ac', '2026-11-11 11:35:04'),
(5, 'LiteClient Test Amenity', 'ทดสอบเพิ่มสิ่งอำนวยความสะดวก', 'wifi', '2026-11-11 12:44:39');

-- --------------------------------------------------------
-- Table structure for table `space_amenities`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `space_amenities` (
  `space_id` int(11) NOT NULL,
  `amenity_id` int(11) NOT NULL,
  PRIMARY KEY (`space_id`,`amenity_id`),
  KEY `idx_space_amenities_amenity_id` (`amenity_id`),
  CONSTRAINT `fk_space_amenities_amenity` FOREIGN KEY (`amenity_id`) REFERENCES `amenities` (`amenity_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_space_amenities_space` FOREIGN KEY (`space_id`) REFERENCES `spaces` (`space_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `space_amenities` (`space_id`, `amenity_id`) VALUES
(2001, 1);

-- --------------------------------------------------------
-- Table structure for table `space_images`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `space_images` (
  `image_id` int(11) NOT NULL AUTO_INCREMENT,
  `space_id` int(11) NOT NULL,
  `image_url` varchar(2048) NOT NULL,
  `alt_text` varchar(255) DEFAULT NULL,
  `sort_order` int(11) NOT NULL DEFAULT 0,
  `is_primary` tinyint(1) NOT NULL DEFAULT 0,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`image_id`),
  KEY `idx_space_images_space_order` (`space_id`,`sort_order`),
  CONSTRAINT `fk_space_images_space` FOREIGN KEY (`space_id`) REFERENCES `spaces` (`space_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------
-- Table structure for table `bookings`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `bookings` (
  `booking_id` int(11) NOT NULL AUTO_INCREMENT,
  `space_id` int(11) NOT NULL,
  `customer_id` int(11) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `start_time` datetime DEFAULT NULL,
  `end_time` datetime DEFAULT NULL,
  `total_price` decimal(10,2) DEFAULT NULL,
  `status` enum('pending','approved','rejected','cancelled','confirmed','completed') NOT NULL DEFAULT 'pending',
  `is_paid` tinyint(1) NOT NULL DEFAULT 0,
  `payment_ref` varchar(100) DEFAULT NULL,
  `slip_image_url` text DEFAULT NULL,
  `rating` int(11) DEFAULT NULL,
  `review_comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `start_minutes` int(11) DEFAULT 540,
  `end_minutes` int(11) DEFAULT 660,
  `days_count` int(11) DEFAULT 1,
  `attendees` int(11) DEFAULT 1,
  `zone` varchar(150) DEFAULT 'โซนหลัก (พื้นที่มาตรฐาน)',
  `renter_note` text DEFAULT NULL,
  `platform_fee` int(11) DEFAULT NULL,
  `app_status` varchar(40) DEFAULT NULL,
  `reason` text DEFAULT NULL,
  `reason_kind` varchar(40) DEFAULT 'none',
  `approved_at` datetime DEFAULT NULL,
  `slip_rejected_at` datetime DEFAULT NULL,
  `confirmed_at` datetime DEFAULT NULL,
  `completed_at` datetime DEFAULT NULL,
  `paid_out_at` datetime DEFAULT NULL,
  `payout_slip_name` varchar(255) DEFAULT NULL,
  `payout_slip_url` text DEFAULT NULL,
  `payout_slip_data` longtext DEFAULT NULL,
  `payout_note` text DEFAULT NULL,
  PRIMARY KEY (`booking_id`),
  KEY `space_id` (`space_id`),
  KEY `customer_id` (`customer_id`),
  CONSTRAINT `bookings_ibfk_1` FOREIGN KEY (`space_id`) REFERENCES `spaces` (`space_id`),
  CONSTRAINT `bookings_ibfk_2` FOREIGN KEY (`customer_id`) REFERENCES `users` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3009 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `bookings` (`booking_id`, `space_id`, `customer_id`, `start_date`, `end_date`, `start_time`, `end_time`, `total_price`, `status`, `is_paid`, `payment_ref`, `slip_image_url`, `rating`, `review_comment`, `created_at`) VALUES
(3001, 2001, 1002, '2026-11-15', '2026-11-15', '2026-11-15 10:00:00', '2026-11-15 12:00:00', 700.00, 'confirmed', 1, 'SLIP-3001-A', '/uploads/meeting.jpg', 5, 'ห้องดีมาก แอร์เย็น สะอาด', '2026-11-05 07:46:46'),
(3002, 2002, 1002, '2026-11-20', '2026-11-20', '2026-11-20 13:00:00', '2026-11-20 17:00:00', 480.00, 'confirmed', 1, 'SLIP-3002-A', '/uploads/study.jpg', NULL, NULL, '2026-11-05 07:46:46'),
(3003, 2005, 1002, '2026-12-10', '2026-12-12', NULL, NULL, NULL, 'cancelled', 0, NULL, NULL, NULL, NULL, '2026-11-05 07:54:23'),
(3004, 2007, 1005, '2026-12-11', '2026-12-12', NULL, NULL, NULL, 'rejected', 0, NULL, NULL, NULL, NULL, '2026-11-05 08:21:29'),
(3006, 2008, 1001, '2026-12-14', '2026-12-15', NULL, NULL, NULL, 'cancelled', 0, NULL, NULL, NULL, NULL, '2026-11-05 08:24:12'),
(3007, 2008, 1002, '2026-12-10', '2026-12-12', NULL, NULL, NULL, 'cancelled', 0, NULL, NULL, NULL, NULL, '2026-11-05 10:37:38'),
(3008, 2001, 1002, '2026-11-10', '2026-11-10', '2026-11-10 09:00:00', '2026-11-10 11:00:00', 700.00, 'completed', 1, 'SLIP-3008-A', '/uploads/meeting.jpg', NULL, NULL, '2026-11-05 11:00:00');

-- --------------------------------------------------------
-- Table structure for table `payments`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `payments` (
  `payment_id` int(11) NOT NULL AUTO_INCREMENT,
  `booking_id` int(11) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `payment_method` varchar(40) NOT NULL,
  `status` enum('pending','submitted','verified','rejected','refunded') NOT NULL DEFAULT 'pending',
  `transaction_ref` varchar(100) DEFAULT NULL,
  `slip_image_url` text DEFAULT NULL,
  `paid_at` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  `file_name` varchar(255) DEFAULT 'slip.jpg',
  `note` text DEFAULT NULL,
  `rejection_reason` text DEFAULT NULL,
  `image_data` longtext DEFAULT NULL,
  PRIMARY KEY (`payment_id`),
  KEY `idx_payments_booking_id` (`booking_id`),
  KEY `idx_payments_status` (`status`),
  CONSTRAINT `fk_payments_booking` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`booking_id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `payments` (`payment_id`, `booking_id`, `amount`, `payment_method`, `status`, `transaction_ref`, `slip_image_url`, `paid_at`, `created_at`, `updated_at`) VALUES
(1, 3004, 800.00, 'bank_transfer', 'refunded', 'TEST-LC-001', '/uploads/test-slip.png', '2026-11-11 19:24:06', '2026-11-11 12:19:17', '2026-11-11 12:54:55'),
(2, 3008, 700.00, 'bank_transfer', 'verified', 'SLIP-3008-A', '/uploads/meeting.jpg', '2026-11-11 19:57:07', '2026-11-11 12:30:29', '2026-11-11 12:57:07'),
(3, 3007, 800.00, 'bank_transfer', 'refunded', 'TEST-LC-001', '/uploads/test-slip.png', '2026-11-11 12:30:33', '2026-11-11 12:30:33', '2026-11-11 13:22:51'),
(4, 3001, 700.00, 'bank_transfer', 'verified', 'SLIP-3001-A', '/uploads/meeting.jpg', '2026-11-11 12:31:04', '2026-11-11 12:31:04', '2026-11-11 12:31:04'),
(5, 3002, 480.00, 'bank_transfer', 'verified', 'SLIP-3002-A', '/uploads/study.jpg', '2026-11-11 12:31:06', '2026-11-11 12:31:06', '2026-11-11 12:31:06'),
(6, 3003, 800.00, 'bank_transfer', 'rejected', 'TEST-LC-001', '/uploads/test-slip.png', NULL, '2026-11-11 12:31:09', '2026-11-11 12:31:09'),
(7, 3006, 800.00, 'bank_transfer', 'refunded', 'TEST-LC-001', '/uploads/test-slip.png', '2026-11-11 12:54:11', '2026-11-11 12:54:11', '2026-11-11 13:22:45');

-- --------------------------------------------------------
-- Table structure for table `reviews`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `reviews` (
  `review_id` int(11) NOT NULL AUTO_INCREMENT,
  `booking_id` int(11) NOT NULL,
  `rating` tinyint(3) UNSIGNED NOT NULL,
  `review_comment` text DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`review_id`),
  UNIQUE KEY `uq_reviews_booking_id` (`booking_id`),
  CONSTRAINT `fk_reviews_booking` FOREIGN KEY (`booking_id`) REFERENCES `bookings` (`booking_id`) ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `reviews` (`review_id`, `booking_id`, `rating`, `review_comment`, `created_at`, `updated_at`) VALUES
(1, 3001, 5, 'ทดสอบรีวิวจาก LiteClient', '2026-11-11 12:40:32', '2026-11-11 12:40:32');

-- --------------------------------------------------------
-- Table structure for table `admin_logs`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `admin_logs` (
  `log_id` int(11) NOT NULL AUTO_INCREMENT,
  `admin_id` int(11) NOT NULL DEFAULT 1003,
  `admin_name` varchar(100) NOT NULL,
  `action` varchar(100) NOT NULL,
  `target_type` varchar(50) NOT NULL,
  `target_id` int(11) NOT NULL,
  `details` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`log_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `admin_logs` (`log_id`, `admin_id`, `admin_name`, `action`, `target_type`, `target_id`, `details`, `created_at`) VALUES
(1, 1003, 'ผู้ดูแลระบบ', 'APPROVE_SPACE', 'space', 2001, 'อนุมัติประกาศ ห้องประชุมสว่างใจ', '2026-11-05 07:46:46'),
(2, 1003, 'ผู้ดูแลระบบ', 'APPROVE_SPACE', 'space', 2002, 'อนุมัติประกาศ The Quiet Nook', '2026-11-05 07:46:46'),
(3, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_PAYMENT_STATUS', 'payment', 1, 'submitted -> verified', '2026-11-11 12:24:06'),
(4, 1003, 'ผู้ดูแลระบบ (Admin)', 'CREATE_AMENITY', 'amenity', 5, 'เพิ่มสิ่งอำนวยความสะดวก: LiteClient Test Amenity', '2026-11-11 12:44:39'),
(5, 1003, 'ผู้ดูแลระบบ (Admin)', 'SET_SPACE_AMENITIES', 'space', 2001, 'amenity_ids=1', '2026-11-11 12:49:53'),
(6, 1003, 'ผู้ดูแลระบบ (Admin)', 'SET_SPACE_AMENITIES', 'space', 2001, 'amenity_ids=1', '2026-11-11 12:51:56'),
(7, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_PAYMENT_STATUS', 'payment', 1, 'verified -> refunded', '2026-11-11 12:54:55'),
(8, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_PAYMENT_STATUS', 'payment', 2, 'submitted -> verified', '2026-11-11 12:57:07'),
(9, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_BOOKING_STATUS', 'booking', 3004, 'pending -> rejected', '2026-11-11 13:08:12'),
(10, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_BOOKING_STATUS', 'booking', 3007, 'pending -> approved', '2026-11-11 13:11:24'),
(11, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_SPACE_STATUS', 'space', 2008, 'pending -> approved', '2026-11-11 13:13:51'),
(12, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_SPACE_STATUS', 'space', 2007, 'pending -> rejected', '2026-11-11 13:14:57'),
(13, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_BOOKING_STATUS', 'booking', 3006, 'approved -> cancelled', '2026-11-11 13:22:45'),
(14, 1003, 'ผู้ดูแลระบบ (Admin)', 'UPDATE_BOOKING_STATUS', 'booking', 3007, 'approved -> cancelled', '2026-11-11 13:22:51');

-- --------------------------------------------------------
-- Table structure for table `auth_sessions`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `auth_sessions` (
  `session_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `user_id` int(11) NOT NULL,
  `token_hash` char(64) NOT NULL,
  `expires_at` datetime NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`session_id`),
  UNIQUE KEY `uq_auth_sessions_token_hash` (`token_hash`),
  KEY `idx_auth_sessions_user_expiry` (`user_id`,`expires_at`),
  CONSTRAINT `fk_auth_sessions_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------
-- Table structure for table `room_blocks`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `room_blocks` (
  `block_id` int(11) NOT NULL AUTO_INCREMENT,
  `space_id` int(11) NOT NULL,
  `created_by` int(11) NOT NULL,
  `start_date` date NOT NULL,
  `end_date` date NOT NULL,
  `start_at` datetime DEFAULT NULL,
  `end_at` datetime DEFAULT NULL,
  `reason` varchar(255) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`block_id`),
  KEY `idx_room_blocks_space_dates` (`space_id`,`start_date`,`end_date`),
  KEY `fk_room_blocks_user` (`created_by`),
  CONSTRAINT `fk_room_blocks_space` FOREIGN KEY (`space_id`) REFERENCES `spaces` (`space_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_room_blocks_user` FOREIGN KEY (`created_by`) REFERENCES `users` (`user_id`),
  CONSTRAINT `chk_room_blocks_dates` CHECK (`end_date` >= `start_date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------
-- Table structure for table `user_favorites`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `user_favorites` (
  `user_id` int(11) NOT NULL,
  `space_id` int(11) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`user_id`,`space_id`),
  KEY `fk_user_favorites_space` (`space_id`),
  CONSTRAINT `fk_user_favorites_space` FOREIGN KEY (`space_id`) REFERENCES `spaces` (`space_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_user_favorites_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------
-- Table structure for table `issues`
-- --------------------------------------------------------

CREATE TABLE IF NOT EXISTS `issues` (
  `id` varchar(40) NOT NULL,
  `reporter_id` int(11) NOT NULL,
  `subject` varchar(255) NOT NULL,
  `detail` text NOT NULL,
  `closed` tinyint(1) NOT NULL DEFAULT 0,
  `resolution` text DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_issues_reporter` (`reporter_id`),
  CONSTRAINT `fk_issues_reporter` FOREIGN KEY (`reporter_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
