import 'package:flutter/foundation.dart';

import '../models/domain.dart';

class AppStore extends ChangeNotifier {
  AppStore({DateTime Function()? clock, bool seed = true})
    : clock = clock ?? DateTime.now {
    if (seed) _seed();
  }
  final DateTime Function() clock;
  final List<AppUser> users = [];
  final List<Space> spaces = [];
  final List<Booking> bookings = [];
  final List<Issue> issues = [];
  final List<AuditEntry> logs = [];
  AppUser? currentUser;

  /// Explicit light/dark preference. Starts in light mode; the toggle in the
  /// app bar and sidebar flips it without touching the business data.
  bool darkMode = false;
  void toggleTheme() {
    darkMode = !darkMode;
    notifyListeners();
  }

  int _sequence = 0;
  String nextId(String prefix) =>
      '$prefix-${clock().microsecondsSinceEpoch}-${++_sequence}';
  AppUser requireUser([UserRole? role]) {
    final user = currentUser;
    if (user == null || !user.active) {
      throw DomainError('กรุณาเข้าสู่ระบบด้วยบัญชีที่ใช้งานได้');
    }
    if (role != null && role != user.role) {
      throw DomainError('บัญชีนี้ไม่มีสิทธิ์ทำรายการ');
    }
    return user;
  }

  Space space(String id) => spaces.firstWhere(
    (s) => s.id == id,
    orElse: () => throw DomainError('ไม่พบพื้นที่'),
  );
  Booking booking(String id) => bookings.firstWhere(
    (b) => b.id == id,
    orElse: () => throw DomainError('ไม่พบการจอง'),
  );
  AppUser user(String id) => users.firstWhere(
    (u) => u.id == id,
    orElse: () => throw DomainError('ไม่พบบัญชี'),
  );
  void changed(String action, {String? actor}) {
    logs.insert(
      0,
      AuditEntry(clock(), actor ?? currentUser?.name ?? 'ระบบ', action),
    );
    notifyListeners();
  }

  List<Booking> visibleBookings() {
    final u = requireUser();
    return bookings
        .where(
          (b) =>
              u.role == UserRole.admin ||
              (u.role == UserRole.owner
                  ? b.ownerId == u.id
                  : b.renterId == u.id),
        )
        .toList();
  }

  List<int> navBadges() {
    final u = currentUser;
    if (u == null) return const [];
    return switch (u.role) {
      UserRole.renter => _renterBadges(u.id),
      UserRole.owner => _ownerBadges(u.id),
      UserRole.admin => _adminBadges(),
    };
  }

  List<int> _renterBadges(String userId) {
    final actionNeeded = bookings
        .where(
          (b) =>
              b.renterId == userId &&
              (b.status == BookingStatus.paymentDue ||
                  b.status == BookingStatus.slipRejected),
        )
        .length;
    return [0, actionNeeded, 0, 0];
  }

  List<int> _ownerBadges(String userId) {
    final rejectedSpaces = spaces
        .where((s) => s.ownerId == userId && s.status == SpaceStatus.rejected)
        .length;
    final pendingRequests = bookings
        .where(
          (b) => b.ownerId == userId && b.status == BookingStatus.ownerReview,
        )
        .length;
    final readyPayouts = bookings
        .where(
          (b) =>
              b.ownerId == userId &&
              b.status == BookingStatus.completed &&
              b.paidOutAt == null,
        )
        .length;
    return [0, rejectedSpaces, pendingRequests, readyPayouts, 0];
  }

  List<int> _adminBadges() {
    final moderationCount =
        spaces.where((s) => s.status == SpaceStatus.pending).length +
        issues.where((i) => !i.closed).length;
    final financeCount = bookings
        .where(
          (b) =>
              b.status == BookingStatus.slipReview ||
              (b.status == BookingStatus.completed && b.paidOutAt == null),
        )
        .length;
    return [0, moderationCount, financeCount, 0];
  }

  bool conflicts(
    String spaceId,
    DateTime date,
    int start,
    int end, {
    int days = 1,
    String? excluding,
  }) {
    for (var i = 0; i < days; i++) {
      final dayDate = dateOnly(date).add(Duration(days: i));
      if (_conflictsOnDay(spaceId, dayDate, start, end, excluding)) {
        return true;
      }
    }
    return false;
  }

  bool _conflictsOnDay(
    String spaceId,
    DateTime dayDate,
    int start,
    int end,
    String? excluding,
  ) => bookings.any(
    (b) =>
        b.id != excluding &&
        b.spaceId == spaceId &&
        b.status.holdsTime &&
        b.coversDate(dayDate) &&
        b.startMinutes < end &&
        b.endMinutes > start,
  );

  void _seed() {
    users.addAll([
      AppUser(
        id: 'renter-1',
        name: 'มินตรา',
        email: 'renter@demo.com',
        password: 'demo1234',
        role: UserRole.renter,
        phone: '081-234-5678',
      ),
      AppUser(
        id: 'renter-2',
        name: 'ธนา',
        email: 'renter2@demo.com',
        password: 'demo1234',
        role: UserRole.renter,
        phone: '082-345-6789',
      ),
      AppUser(
        id: 'owner-1',
        name: 'เจ้าของพื้นที่ตัวอย่าง',
        email: 'owner@demo.com',
        password: 'demo1234',
        role: UserRole.owner,
        phone: '089-111-2233',
        bankInfo: 'กสิกรไทย 123-4-56789-0',
      ),
      AppUser(
        id: 'owner-2',
        name: 'เจ้าของ Loft',
        email: 'owner2@demo.com',
        password: 'demo1234',
        role: UserRole.owner,
        phone: '086-999-8877',
        bankInfo: 'ไทยพาณิชย์ 987-6-54321-0',
      ),
      AppUser(
        id: 'admin-1',
        name: 'Admin',
        email: 'admin@demo.com',
        password: 'demo1234',
        role: UserRole.admin,
        phone: '02-000-0000',
      ),
    ]);
    spaces.addAll([
      Space(
        id: 'space-1',
        ownerId: 'owner-1',
        name: 'สตูดิโอแสงเหนือ',
        category: 'สตูดิโอ',
        location: 'สุขุมวิท · เขตวัฒนา',
        price: 850,
        capacity: 8,
        description:
            'สตูดิโอโปร่งพร้อมแสงธรรมชาติ เหมาะสำหรับถ่ายภาพและงานสร้างสรรค์',
        amenities: ['ไฟสตูดิโอ', 'Wi-Fi'],
        image:
            'https://images.unsplash.com/photo-1497366754035-f200968a6e72?auto=format&fit=crop&w=1000&q=85',
        status: SpaceStatus.approved,
      ),
      Space(
        id: 'space-2',
        ownerId: 'owner-1',
        name: 'ห้องประชุม The Green Room',
        category: 'ห้องประชุม',
        location: 'อารีย์ · พญาไท',
        price: 550,
        capacity: 10,
        description: 'ห้องประชุมพร้อมจอและไวท์บอร์ด เดินทางสะดวก',
        amenities: ['โปรเจกเตอร์', 'กาแฟ'],
        image:
            'https://images.unsplash.com/photo-1497366216548-37526070297c?auto=format&fit=crop&w=1000&q=85',
        status: SpaceStatus.approved,
      ),
      Space(
        id: 'space-3',
        ownerId: 'owner-1',
        name: 'ห้องอ่านหนังสือเงียบสงบ',
        category: 'ห้องอ่านหนังสือ',
        location: 'สามย่าน · ปทุมวัน',
        price: 120,
        capacity: 4,
        description: 'พื้นที่ส่วนตัวพร้อมปลั๊กไฟและอินเทอร์เน็ต',
        image:
            'https://images.unsplash.com/photo-1524758631624-e2822e304c36?auto=format&fit=crop&w=1000&q=85',
        status: SpaceStatus.approved,
      ),
      Space(
        id: 'space-4',
        ownerId: 'owner-2',
        name: 'Creative Loft Studio',
        category: 'สตูดิโอ',
        location: 'เจริญกรุง · บางรัก',
        price: 1200,
        capacity: 15,
        description: 'ลอฟต์สำหรับเวิร์กช็อป ถ่ายทำ และกิจกรรมกลุ่ม',
        image:
            'https://images.unsplash.com/photo-1497366811353-6870744d04b2?auto=format&fit=crop&w=1000&q=85',
        status: SpaceStatus.pending,
      ),
    ]);
    final yesterday = dateOnly(clock()).subtract(const Duration(days: 1));
    bookings.add(
      Booking(
        id: 'RS-DEMO-COMPLETED',
        spaceId: 'space-2',
        ownerId: 'owner-1',
        renterId: 'renter-1',
        spaceName: spaces[1].name,
        date: yesterday,
        startMinutes: 600,
        endMinutes: 720,
        rentAmount: 1100,
        status: BookingStatus.completed,
        review: SpaceReview(
          rating: 5,
          comment: 'ห้องสะอาด อุปกรณ์ครบ เดินทางสะดวกมาก',
          createdAt: yesterday,
        ),
      ),
    );
    logs.add(
      AuditEntry(
        clock(),
        'ระบบ',
        'สร้างข้อมูลจำลองเริ่มต้น รวมการจองที่เสร็จสิ้น 1 รายการ',
      ),
    );
  }
}
