import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:rentspace/app.dart';
import 'package:rentspace/data/app_store.dart';
import 'package:rentspace/models/domain.dart';
import 'package:rentspace/services/api_client.dart';
import 'package:rentspace/ui/booking_pages.dart';
import 'package:rentspace/ui/common.dart';
import 'package:rentspace/ui/home_page.dart';
import 'package:rentspace/ui/space_form.dart';

const String _validPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
final Uint8List _validPngBytes = base64Decode(_validPngBase64);
final Uint8List _brokenImageBytes = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

final DateTime _fixedNow = DateTime(2026, 11, 15, 10, 0);

class FakeBackend {
  FakeBackend({DateTime? clockNow}) : _clockNow = clockNow ?? _fixedNow {
    _seedInitialRecords();
  }

  final DateTime _clockNow;
  final Map<String, Map<String, dynamic>> _usersById = {};
  final Map<String, String> _passwordsByUserId = {};
  final Map<String, String> _userIdByToken = {};
  final Map<String, Set<String>> _favoritesByUserId = {};
  final List<Map<String, dynamic>> _spaces = [];
  final List<Map<String, dynamic>> _blocks = [];
  final List<Map<String, dynamic>> _bookings = [];
  final List<Map<String, dynamic>> _slips = [];
  final List<Map<String, dynamic>> _reviews = [];
  final List<Map<String, dynamic>> _issues = [];
  final List<Map<String, dynamic>> _logs = [];

  int _nextId = 4000;
  int _tokenCounter = 0;

  bool failNextLoginNetwork = false;
  bool failNextStateNetwork = false;
  bool failNextBookingConflict = false;
  int? failNextStateStatusCode;
  String? failNextStateError;
  Completer<void>? loginDelay;
  Completer<void>? stateDelay;
  Completer<void>? actionDelay;
  int loginCallCount = 0;
  String? lastClipboardText;

  String get _nowIso => _clockNow.toUtc().toIso8601String();
  String _isoDate(DateTime dt) => dt.toIso8601String().substring(0, 10);

  List<Map<String, dynamic>> _defaultWeekHours() => List.generate(
    7,
    (_) => {'open': true, 'start': 540, 'end': 1080},
  );

  void _seedInitialRecords() {
    _addSeedUser(
      id: '1001',
      name: 'ผู้เช่า หนึ่ง',
      email: 'renter01@rentspace.test',
      role: 'renter',
      phone: '081-111-1111',
      active: true,
    );
    _addSeedUser(
      id: '1002',
      name: 'เจ้าของ พื้นที่',
      email: 'owner01@rentspace.test',
      role: 'owner',
      phone: '082-222-2222',
      bankInfo: 'กสิกรไทย 123-4-56789-0',
      active: true,
    );
    _addSeedUser(
      id: '1003',
      name: 'แอดมิน ระบบ',
      email: 'admin01@rentspace.test',
      role: 'admin',
      phone: '083-333-3333',
      active: true,
    );
    _addSeedUser(
      id: '1004',
      name: 'เจ้าของ ไม่มีบัญชี',
      email: 'owner02@rentspace.test',
      role: 'owner',
      phone: '084-444-4444',
      bankInfo: '',
      active: true,
    );
    _addSeedUser(
      id: '1005',
      name: 'บัญชี ถูกระงับ',
      email: 'suspended@rentspace.test',
      role: 'renter',
      phone: '085-555-5555',
      active: false,
    );
    _addSeedUser(
      id: '1006',
      name: 'ผู้เช่า ไม่มีเบอร์',
      email: 'nophone@rentspace.test',
      role: 'renter',
      phone: '',
      active: true,
    );

    _spaces.addAll([
      {
        'id': '2001',
        'owner_id': '1002',
        'name': 'สตูดิโอ กลางเมือง',
        'category': 'ห้องประชุม',
        'location': 'สยาม กรุงเทพ',
        'price': 350,
        'capacity': 10,
        'description': 'ห้องประชุมแสงธรรมชาติ พร้อมจอแสดงผล',
        'image': 'data:image/png;base64,$_validPngBase64',
        'amenities': ['Wi-Fi', 'โปรเจกเตอร์', 'แอร์'],
        'status': 'approved',
        'hours': _defaultWeekHours(),
        'avg_rating': 5.0,
        'review_count': 1,
        'review_reason': '',
      },
      {
        'id': '2002',
        'owner_id': '1002',
        'name': 'เวิร์กสเปซ อารีย์',
        'category': 'Co-Working',
        'location': 'อารีย์ กรุงเทพ',
        'price': 200,
        'capacity': 4,
        'description': 'มุมทำงานเงียบสงบ ใกล้รถไฟฟ้า',
        'image': '',
        'amenities': ['Wi-Fi', 'กาแฟ'],
        'status': 'approved',
        'hours': _defaultWeekHours(),
        'avg_rating': 4.0,
        'review_count': 1,
        'review_reason': '',
      },
      {
        'id': '2003',
        'owner_id': '1002',
        'name': 'ห้องสัมมนา ใหญ่พิเศษ',
        'category': 'สตูดิโอ',
        'location': 'สุขุมวิท',
        'price': 900,
        'capacity': 30,
        'description': 'รองรับเวิร์กช็อปและงานถ่ายทำ',
        'image': 'https://invalid.example.invalid/broken-space.png',
        'amenities': ['ระบบเสียง', 'ที่จอดรถ'],
        'status': 'approved',
        'hours': _defaultWeekHours(),
        'avg_rating': null,
        'review_count': 0,
        'review_reason': '',
      },
      {
        'id': '2004',
        'owner_id': '1002',
        'name': 'ห้องรอแอดมิน ตรวจ',
        'category': 'ห้องประชุม',
        'location': 'สีลม',
        'price': 450,
        'capacity': 12,
        'description': 'รอตรวจสอบประกาศใหม่',
        'image': 'https://invalid.example.invalid/broken-pending.png',
        'amenities': ['Wi-Fi', 'ไวท์บอร์ด'],
        'status': 'pending',
        'hours': _defaultWeekHours(),
        'avg_rating': null,
        'review_count': 0,
        'review_reason': '',
      },
      {
        'id': '2005',
        'owner_id': '1002',
        'name': 'ห้องซ้อม ถูกระงับ',
        'category': 'ห้องซ้อม',
        'location': 'รัชดา',
        'price': 300,
        'capacity': 8,
        'description': 'ประกาศที่ไม่ผ่านเกณฑ์ภาพถ่าย',
        'image': '',
        'amenities': ['ที่จอดรถ'],
        'status': 'rejected',
        'hours': _defaultWeekHours(),
        'avg_rating': null,
        'review_count': 0,
        'review_reason': 'ภาพประกอบไม่ชัด',
      },
    ]);

    _bookings.addAll([
      _buildBookingRecord(
        id: '3001',
        spaceId: '2001',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'สตูดิโอ กลางเมือง',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 10))),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 700,
        status: 'ownerReview',
      ),
      _buildBookingRecord(
        id: '3002',
        spaceId: '2001',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'สตูดิโอ กลางเมือง',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 11))),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 700,
        status: 'paymentDue',
        approvedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3003',
        spaceId: '2001',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'สตูดิโอ กลางเมือง',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 12))),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 700,
        status: 'slipReview',
        approvedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3004',
        spaceId: '2002',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'เวิร์กสเปซ อารีย์',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 13))),
        startMinutes: 600,
        endMinutes: 720,
        rentAmount: 400,
        status: 'confirmed',
        approvedAt: _nowIso,
        confirmedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3005',
        spaceId: '2002',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'เวิร์กสเปซ อารีย์',
        bookingDate: _isoDate(_clockNow.subtract(const Duration(days: 1))),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 400,
        status: 'confirmed',
        approvedAt: _nowIso,
        confirmedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3006',
        spaceId: '2001',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'สตูดิโอ กลางเมือง',
        bookingDate: _isoDate(_clockNow.subtract(const Duration(days: 3))),
        startMinutes: 540,
        endMinutes: 660,
        rentAmount: 1000,
        status: 'completed',
        approvedAt: _nowIso,
        confirmedAt: _nowIso,
        completedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3007',
        spaceId: '2002',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'เวิร์กสเปซ อารีย์',
        bookingDate: _isoDate(_clockNow.subtract(const Duration(days: 5))),
        startMinutes: 780,
        endMinutes: 900,
        rentAmount: 800,
        status: 'completed',
        approvedAt: _nowIso,
        confirmedAt: _nowIso,
        completedAt: _nowIso,
        paidOutAt: _nowIso,
        payoutSlipName: 'existing_payout.png',
        payoutSlipData: _validPngBase64,
        payoutNote: 'โอนงวดแรกเรียบร้อย',
      ),
      _buildBookingRecord(
        id: '3008',
        spaceId: '2001',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'สตูดิโอ กลางเมือง',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 14))),
        startMinutes: 780,
        endMinutes: 900,
        rentAmount: 700,
        status: 'slipRejected',
        reason: 'สลิปเดิมไม่ชัด',
        reasonKind: 'slipRejected',
        approvedAt: _nowIso,
        slipRejectedAt: _nowIso,
      ),
      _buildBookingRecord(
        id: '3009',
        spaceId: '2002',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'เวิร์กสเปซ อารีย์',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 15))),
        startMinutes: 780,
        endMinutes: 900,
        rentAmount: 400,
        status: 'canceled',
        reason: 'เปลี่ยนกำหนดการ',
        reasonKind: 'canceledByUser',
      ),
      _buildBookingRecord(
        id: '3010',
        spaceId: '2002',
        ownerId: '1002',
        renterId: '1001',
        spaceName: 'เวิร์กสเปซ อารีย์',
        bookingDate: _isoDate(_clockNow.add(const Duration(days: 16))),
        startMinutes: 780,
        endMinutes: 900,
        rentAmount: 400,
        status: 'ownerRejected',
        reason: 'ติดงานซ่อมระบบไฟ',
        reasonKind: 'ownerRejected',
      ),
    ]);

    _slips.addAll([
      {
        'id': '401',
        'booking_id': '3003',
        'file_name': 'slip_3003.png',
        'image_data': _validPngBase64,
        'image_url': '',
        'submitted_at': _nowIso,
        'note': 'โอนผ่านพร้อมเพย์',
        'rejection_reason': '',
      },
      {
        'id': '402',
        'booking_id': '3008',
        'file_name': 'slip_3008_bad.png',
        'image_data': _validPngBase64,
        'image_url': '',
        'submitted_at': _nowIso,
        'note': 'โอนครั้งแรก',
        'rejection_reason': 'สลิปเดิมไม่ชัด',
      },
    ]);

    _reviews.add({
      'id': '501',
      'booking_id': '3007',
      'space_id': '2002',
      'rating': 4,
      'comment': 'พื้นที่สงบ ใช้งานได้ดีมาก',
      'created_at': _nowIso,
    });

    _issues.add({
      'id': 'iss_1',
      'reporter_id': '1001',
      'subject': 'แอร์ไม่เย็น',
      'detail': 'ห้องประชุมชั้น 2 แอร์ไม่เย็นช่วงบ่าย',
      'closed': false,
      'resolution': '',
    });
  }

  void _addSeedUser({
    required String id,
    required String name,
    required String email,
    required String role,
    required String phone,
    String bankInfo = '',
    bool active = true,
  }) {
    _usersById[id] = {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'phone': phone,
      'bank_info': bankInfo,
      'active': active,
    };
    _passwordsByUserId[id] = 'password';
    _favoritesByUserId[id] = {};
  }

  Map<String, dynamic> _buildBookingRecord({
    required String id,
    required String spaceId,
    required String ownerId,
    required String renterId,
    required String spaceName,
    required String bookingDate,
    required int startMinutes,
    required int endMinutes,
    required int rentAmount,
    required String status,
    int daysCount = 1,
    int attendees = 2,
    String zone = 'โซนหลัก (พื้นที่มาตรฐาน)',
    String renterNote = '',
    String reason = '',
    String reasonKind = 'none',
    String? approvedAt,
    String? slipRejectedAt,
    String? confirmedAt,
    String? completedAt,
    String? paidOutAt,
    String payoutSlipName = '',
    String payoutSlipData = '',
    String payoutNote = '',
  }) {
    return {
      'id': id,
      'space_id': spaceId,
      'owner_id': ownerId,
      'renter_id': renterId,
      'space_name': spaceName,
      'booking_date': bookingDate,
      'start_minutes': startMinutes,
      'end_minutes': endMinutes,
      'rent_amount': rentAmount,
      'platform_fee': (rentAmount * platformFeePercent / 100).round(),
      'days_count': daysCount,
      'attendees': attendees,
      'zone': zone,
      'renter_note': renterNote,
      'status': status,
      'reason': reason,
      'reason_kind': reasonKind,
      'created_at': _nowIso,
      'approved_at': approvedAt,
      'slip_rejected_at': slipRejectedAt,
      'confirmed_at': confirmedAt,
      'completed_at': completedAt,
      'paid_out_at': paidOutAt,
      'payout_slip_name': payoutSlipName,
      'payout_slip_url': '',
      'payout_slip_data': payoutSlipData,
      'payout_note': payoutNote,
    };
  }

  String issueTokenForUser(String userId) {
    _tokenCounter++;
    final issuedToken = 'tok_${userId}_$_tokenCounter';
    _userIdByToken[issuedToken] = userId;
    return issuedToken;
  }

  Map<String, dynamic> findBooking(String bookingId) =>
      _bookings.firstWhere((row) => row['id'] == bookingId);

  Map<String, dynamic> findSpace(String spaceId) =>
      _spaces.firstWhere((row) => row['id'] == spaceId);

  void insertSpace(Map<String, dynamic> spaceRecord) {
    _spaces.add(spaceRecord);
  }

  Future<(int, Map<String, dynamic>)> dispatch(
    String method,
    String path, {
    String? token,
    Map<String, dynamic>? jsonBody,
    String? fileName,
    Uint8List? fileBytes,
    String noteText = '',
  }) async {
    if (actionDelay != null) {
      await actionDelay!.future;
    }

    if (method == 'POST' && path == '/auth/login') {
      loginCallCount++;
      if (loginDelay != null) {
        await loginDelay!.future;
      }
      if (failNextLoginNetwork) {
        failNextLoginNetwork = false;
        throw http.ClientException('Connection refused');
      }
      return _handleLogin(jsonBody ?? const {});
    }

    if (method == 'POST' && path == '/auth/register') {
      return _handleRegister(jsonBody ?? const {});
    }

    final viewerId = token != null ? _userIdByToken[token] : null;
    if (viewerId == null) {
      return (401, {'error': 'กรุณาเข้าสู่ระบบ'});
    }
    final viewer = _usersById[viewerId]!;
    if (viewer['active'] != true) {
      return (403, {'error': 'บัญชีนี้ถูกระงับการใช้งาน'});
    }

    if (method == 'POST' && path == '/auth/logout') {
      _userIdByToken.remove(token);
      return (200, {'ok': true});
    }

    if (method == 'GET' && path == '/state') {
      if (stateDelay != null) {
        await stateDelay!.future;
      }
      if (failNextStateNetwork) {
        failNextStateNetwork = false;
        throw http.ClientException('Network unreachable');
      }
      if (failNextStateStatusCode != null) {
        final statusCode = failNextStateStatusCode!;
        final errorText = failNextStateError ?? 'เซิร์ฟเวอร์ขัดข้อง';
        failNextStateStatusCode = null;
        failNextStateError = null;
        return (statusCode, {'error': errorText});
      }
      return (200, _buildSnapshot(viewerId));
    }

    if (method == 'PUT' && path == '/auth/profile') {
      return _handleUpdateProfile(viewerId, jsonBody ?? const {});
    }
    if (method == 'PUT' && path == '/auth/password') {
      return _handleChangePassword(viewerId, jsonBody ?? const {});
    }

    if (method == 'POST' && path == '/spaces') {
      return _handleCreateSpace(viewerId, jsonBody ?? const {});
    }
    final putSpaceMatch = RegExp(r'^/spaces/([^/]+)$').firstMatch(path);
    if (method == 'PUT' && putSpaceMatch != null) {
      return _handleUpdateSpace(putSpaceMatch.group(1)!, jsonBody ?? const {});
    }
    final availabilityMatch = RegExp(
      r'^/spaces/([^/]+)/availability$',
    ).firstMatch(path);
    if (method == 'PUT' && availabilityMatch != null) {
      return _handleAvailability(
        availabilityMatch.group(1)!,
        jsonBody ?? const {},
      );
    }
    final favMatch = RegExp(r'^/spaces/([^/]+)/favorite$').firstMatch(path);
    if (method == 'POST' && favMatch != null) {
      final spaceId = favMatch.group(1)!;
      final favSet = _favoritesByUserId.putIfAbsent(viewerId, () => {});
      if (!favSet.add(spaceId)) favSet.remove(spaceId);
      return (200, {'ok': true});
    }

    if (method == 'POST' && path == '/bookings') {
      return _handleCreateBooking(viewerId, jsonBody ?? const {});
    }
    final bookingActionMatch = RegExp(
      r'^/bookings/([^/]+)/(approve|reject|cancel|complete|review)$',
    ).firstMatch(path);
    if (method == 'POST' && bookingActionMatch != null) {
      return _handleBookingAction(
        bookingId: bookingActionMatch.group(1)!,
        actionName: bookingActionMatch.group(2)!,
        actorRole: viewer['role'] as String,
        body: jsonBody ?? const {},
      );
    }

    final paymentMatch = RegExp(
      r'^/payments/([^/]+)/(slip|review|payout)$',
    ).firstMatch(path);
    if (method == 'POST' && paymentMatch != null) {
      return _handlePaymentAction(
        bookingId: paymentMatch.group(1)!,
        actionName: paymentMatch.group(2)!,
        body: jsonBody ?? const {},
        fileName: fileName,
        fileBytes: fileBytes,
        noteText: noteText,
      );
    }

    final adminToggleMatch = RegExp(
      r'^/admin/users/([^/]+)/toggle$',
    ).firstMatch(path);
    if (method == 'PUT' && adminToggleMatch != null) {
      final target = _usersById[adminToggleMatch.group(1)!]!;
      target['active'] = !(target['active'] == true);
      return (200, {'ok': true});
    }

    final adminSpaceMatch = RegExp(
      r'^/admin/spaces/([^/]+)/(approve|reject|activate)$',
    ).firstMatch(path);
    if (method == 'PUT' && adminSpaceMatch != null) {
      final targetSpace = findSpace(adminSpaceMatch.group(1)!);
      final actionName = adminSpaceMatch.group(2)!;
      if (actionName == 'approve' || actionName == 'activate') {
        targetSpace['status'] = 'approved';
        targetSpace['review_reason'] = '';
      } else {
        targetSpace['status'] = 'rejected';
        targetSpace['review_reason'] = '${jsonBody?['reason'] ?? ''}';
      }
      return (200, {'ok': true});
    }

    if (method == 'POST' && path == '/admin/issues') {
      final newId = 'iss_${++_nextId}';
      _issues.add({
        'id': newId,
        'reporter_id': viewerId,
        'subject': '${jsonBody?['subject'] ?? 'แจ้งปัญหา'}',
        'detail': '${jsonBody?['detail'] ?? ''}',
        'closed': false,
        'resolution': '',
      });
      return (201, {'id': newId, 'ok': true});
    }
    final closeIssueMatch = RegExp(
      r'^/admin/issues/([^/]+)/close$',
    ).firstMatch(path);
    if (method == 'PUT' && closeIssueMatch != null) {
      final issueRecord = _issues.firstWhere(
        (entry) => entry['id'] == closeIssueMatch.group(1)!,
      );
      issueRecord['closed'] = true;
      issueRecord['resolution'] = '${jsonBody?['resolution'] ?? ''}';
      return (200, {'ok': true});
    }

    return (404, {'error': 'ไม่พบเส้นทาง $method $path'});
  }

  (int, Map<String, dynamic>) _handleLogin(Map<String, dynamic> body) {
    final identifier = '${body['email'] ?? body['login'] ?? ''}'.trim();
    final rawPassword = '${body['password'] ?? ''}';
    Map<String, dynamic>? matched;
    for (final candidate in _usersById.values) {
      if ('${candidate['email']}'.toLowerCase() == identifier.toLowerCase()) {
        matched = candidate;
        break;
      }
    }
    if (matched == null || _passwordsByUserId[matched['id']] != rawPassword) {
      return (401, {'error': 'อีเมลหรือรหัสผ่านไม่ถูกต้อง'});
    }
    if (matched['active'] != true) {
      return (401, {'error': 'บัญชีนี้ถูกระงับการใช้งาน'});
    }
    final issuedToken = issueTokenForUser('${matched['id']}');
    return (200, {'token': issuedToken, 'id': matched['id']});
  }

  (int, Map<String, dynamic>) _handleRegister(Map<String, dynamic> body) {
    final emailText = '${body['email'] ?? ''}'.trim();
    final roleText = '${body['role'] ?? 'renter'}'.trim();
    if (roleText == 'admin') {
      return (403, {'error': 'ไม่สามารถสมัครบัญชี Admin'});
    }
    final duplicate = _usersById.values.any(
      (candidate) =>
          '${candidate['email']}'.toLowerCase() == emailText.toLowerCase(),
    );
    if (duplicate) {
      return (409, {'error': 'อีเมลนี้ถูกใช้งานแล้ว'});
    }
    final newId = '${++_nextId}';
    _usersById[newId] = {
      'id': newId,
      'name': '${body['name'] ?? ''}'.trim(),
      'email': emailText,
      'role': roleText,
      'phone': '${body['phone'] ?? ''}'.trim(),
      'bank_info': '',
      'active': true,
    };
    _passwordsByUserId[newId] = '${body['password'] ?? ''}';
    _favoritesByUserId[newId] = {};
    return (201, {'token': issueTokenForUser(newId), 'id': newId});
  }

  (int, Map<String, dynamic>) _handleUpdateProfile(
    String viewerId,
    Map<String, dynamic> body,
  ) {
    final target = _usersById[viewerId]!;
    target['name'] = '${body['name'] ?? target['name']}'.trim();
    target['email'] = '${body['email'] ?? target['email']}'.trim();
    target['phone'] = '${body['phone'] ?? target['phone']}'.trim();
    if (body.containsKey('bankInfo')) {
      target['bank_info'] = '${body['bankInfo'] ?? ''}'.trim();
    }
    return (200, {'ok': true});
  }

  (int, Map<String, dynamic>) _handleChangePassword(
    String viewerId,
    Map<String, dynamic> body,
  ) {
    if (_passwordsByUserId[viewerId] != body['currentPassword']) {
      return (400, {'error': 'รหัสผ่านปัจจุบันไม่ถูกต้อง'});
    }
    _passwordsByUserId[viewerId] = '${body['newPassword'] ?? ''}';
    return (200, {'ok': true});
  }

  (int, Map<String, dynamic>) _handleCreateSpace(
    String viewerId,
    Map<String, dynamic> body,
  ) {
    final newId = '${++_nextId}';
    _spaces.add({
      'id': newId,
      'owner_id': viewerId,
      'name': body['name'],
      'category': body['category'],
      'location': body['location'],
      'price': body['price'],
      'capacity': body['capacity'],
      'description': body['description'],
      'image': body['image'] ?? '',
      'amenities': List<String>.from(body['amenities'] as List? ?? const []),
      'status': 'pending',
      'hours': body['hours'] ?? _defaultWeekHours(),
      'avg_rating': null,
      'review_count': 0,
      'review_reason': '',
    });
    return (201, {'id': newId, 'ok': true});
  }

  (int, Map<String, dynamic>) _handleUpdateSpace(
    String spaceId,
    Map<String, dynamic> body,
  ) {
    final spaceRecord = findSpace(spaceId);
    spaceRecord['name'] = body['name'];
    spaceRecord['category'] = body['category'];
    spaceRecord['location'] = body['location'];
    spaceRecord['price'] = body['price'];
    spaceRecord['capacity'] = body['capacity'];
    spaceRecord['description'] = body['description'];
    spaceRecord['image'] = body['image'] ?? '';
    spaceRecord['amenities'] = List<String>.from(
      body['amenities'] as List? ?? const [],
    );
    spaceRecord['hours'] = body['hours'] ?? spaceRecord['hours'];
    spaceRecord['status'] = 'pending';
    spaceRecord['review_reason'] = '';
    return (200, {'id': spaceId, 'ok': true});
  }

  (int, Map<String, dynamic>) _handleAvailability(
    String spaceId,
    Map<String, dynamic> body,
  ) {
    final spaceRecord = findSpace(spaceId);
    spaceRecord['hours'] = body['days'];
    _blocks.removeWhere((entry) => entry['space_id'] == spaceId);
    for (final rawBlock in body['blocks'] as List? ?? const []) {
      final blockMap = Map<String, dynamic>.from(rawBlock as Map);
      _blocks.add({
        'id': 'blk_${++_nextId}',
        'space_id': spaceId,
        'start_at': blockMap['start'],
        'end_at': blockMap['end'],
        'reason': blockMap['reason'],
      });
    }
    return (200, {'ok': true});
  }

  (int, Map<String, dynamic>) _handleCreateBooking(
    String viewerId,
    Map<String, dynamic> body,
  ) {
    if (failNextBookingConflict) {
      failNextBookingConflict = false;
      return (409, {'error': 'ช่วงเวลานี้มีการจองแล้ว'});
    }
    final spaceRecord = findSpace('${body['spaceId']}');
    final startMin = (body['startMinutes'] as num).toInt();
    final endMin = (body['endMinutes'] as num).toInt();
    final daysCount = (body['days'] as num? ?? 1).toInt();
    final rentAmount =
        (spaceRecord['price'] as num).toInt() *
        ((endMin - startMin) / 60).ceil() *
        daysCount;
    final newId = '${++_nextId}';
    _bookings.insert(
      0,
      _buildBookingRecord(
        id: newId,
        spaceId: '${spaceRecord['id']}',
        ownerId: '${spaceRecord['owner_id']}',
        renterId: viewerId,
        spaceName: '${spaceRecord['name']}',
        bookingDate: '${body['date']}',
        startMinutes: startMin,
        endMinutes: endMin,
        rentAmount: rentAmount,
        status: 'ownerReview',
        daysCount: daysCount,
        attendees: (body['attendees'] as num? ?? 1).toInt(),
        zone: '${body['zone'] ?? 'โซนหลัก (พื้นที่มาตรฐาน)'}',
        renterNote: '${body['renterNote'] ?? ''}',
      ),
    );
    return (201, {'id': newId});
  }

  (int, Map<String, dynamic>) _handleBookingAction({
    required String bookingId,
    required String actionName,
    required String actorRole,
    required Map<String, dynamic> body,
  }) {
    final bookingRecord = findBooking(bookingId);
    final currentStatus = bookingRecord['status'] as String;
    switch (actionName) {
      case 'approve':
        if (currentStatus != 'ownerReview') {
          return (400, {'error': 'สถานะไม่ถูกต้อง'});
        }
        bookingRecord['status'] = 'paymentDue';
        bookingRecord['approved_at'] = _nowIso;
        bookingRecord['reason'] = '';
        bookingRecord['reason_kind'] = 'none';
        return (200, {'ok': true});
      case 'reject':
        if (currentStatus != 'ownerReview') {
          return (400, {'error': 'สถานะไม่ถูกต้อง'});
        }
        bookingRecord['status'] = 'ownerRejected';
        bookingRecord['reason'] = '${body['reason'] ?? ''}'.trim();
        bookingRecord['reason_kind'] = 'ownerRejected';
        return (200, {'ok': true});
      case 'cancel':
        final allowedForAdmin = [
          'ownerReview',
          'paymentDue',
          'slipReview',
          'slipRejected',
          'confirmed',
        ];
        final allowedForUser = ['ownerReview', 'paymentDue', 'slipRejected'];
        final allowed = actorRole == 'admin' ? allowedForAdmin : allowedForUser;
        if (!allowed.contains(currentStatus)) {
          return (400, {'error': 'ไม่สามารถยกเลิกในสถานะนี้'});
        }
        bookingRecord['status'] = 'canceled';
        bookingRecord['reason'] = '${body['reason'] ?? ''}'.trim();
        bookingRecord['reason_kind'] = 'canceledByUser';
        return (200, {'ok': true});
      case 'complete':
        if (currentStatus != 'confirmed') {
          return (400, {'error': 'สถานะไม่ถูกต้อง'});
        }
        bookingRecord['status'] = 'completed';
        bookingRecord['completed_at'] = _nowIso;
        return (200, {'ok': true});
      case 'review':
        if (currentStatus != 'completed') {
          return (400, {'error': 'ยังไม่สามารถรีวิวได้'});
        }
        _reviews.add({
          'id': '${++_nextId}',
          'booking_id': bookingId,
          'space_id': bookingRecord['space_id'],
          'rating': body['rating'],
          'comment': body['comment'],
          'created_at': _nowIso,
        });
        return (201, {'ok': true});
    }
    return (400, {'error': 'คำสั่งไม่ถูกต้อง'});
  }

  (int, Map<String, dynamic>) _handlePaymentAction({
    required String bookingId,
    required String actionName,
    required Map<String, dynamic> body,
    String? fileName,
    Uint8List? fileBytes,
    String noteText = '',
  }) {
    final bookingRecord = findBooking(bookingId);
    final currentStatus = bookingRecord['status'] as String;
    switch (actionName) {
      case 'slip':
        if (currentStatus != 'paymentDue' && currentStatus != 'slipRejected') {
          return (400, {'error': 'สถานะไม่รองรับการส่งสลิป'});
        }
        _slips.add({
          'id': '${++_nextId}',
          'booking_id': bookingId,
          'file_name': fileName ?? 'slip.png',
          'image_data': fileBytes != null
              ? base64Encode(fileBytes)
              : _validPngBase64,
          'image_url': '',
          'submitted_at': _nowIso,
          'note': noteText,
          'rejection_reason': '',
        });
        bookingRecord['status'] = 'slipReview';
        return (201, {'ok': true});
      case 'review':
        if (currentStatus != 'slipReview') {
          return (400, {'error': 'สถานะไม่ถูกต้อง'});
        }
        final approved = body['approve'] == true;
        final reason = '${body['reason'] ?? ''}'.trim();
        if (approved) {
          bookingRecord['status'] = 'confirmed';
          bookingRecord['confirmed_at'] = _nowIso;
          bookingRecord['reason'] = '';
          bookingRecord['reason_kind'] = 'none';
        } else {
          bookingRecord['status'] = 'slipRejected';
          bookingRecord['slip_rejected_at'] = _nowIso;
          bookingRecord['reason'] = reason;
          bookingRecord['reason_kind'] = 'slipRejected';
          for (var idx = _slips.length - 1; idx >= 0; idx--) {
            if (_slips[idx]['booking_id'] == bookingId) {
              _slips[idx]['rejection_reason'] = reason;
              break;
            }
          }
        }
        return (200, {'ok': true});
      case 'payout':
        if (currentStatus != 'completed') {
          return (400, {'error': 'สถานะไม่ถูกต้อง'});
        }
        bookingRecord['paid_out_at'] = _nowIso;
        bookingRecord['payout_note'] = noteText.isNotEmpty
            ? noteText
            : '${body['note'] ?? ''}';
        if (fileBytes != null) {
          bookingRecord['payout_slip_name'] = fileName ?? 'payout.png';
          bookingRecord['payout_slip_data'] = base64Encode(fileBytes);
        }
        return (200, {'ok': true});
    }
    return (400, {'error': 'คำสั่งชำระเงินไม่ถูกต้อง'});
  }

  Map<String, dynamic> _buildSnapshot(String viewerId) {
    final viewer = _usersById[viewerId]!;
    final isAdmin = viewer['role'] == 'admin';
    final visibleBookings = isAdmin
        ? _bookings
        : _bookings
              .where(
                (entry) =>
                    entry['renter_id'] == viewerId ||
                    entry['owner_id'] == viewerId,
              )
              .toList();
    final visibleIds = visibleBookings
        .map((entry) => entry['id'] as String)
        .toSet();
    final pairedIds = <String>{viewerId};
    for (final entry in visibleBookings) {
      pairedIds.add(entry['renter_id'] as String);
      pairedIds.add(entry['owner_id'] as String);
    }
    final sanitizedUsers = _usersById.values.map((userRow) {
      if (isAdmin) return Map<String, dynamic>.from(userRow);
      final isSelf = userRow['id'] == viewerId;
      return {
        ...userRow,
        'email': isSelf ? userRow['email'] : '',
        'bank_info': isSelf ? userRow['bank_info'] : '',
        'phone': isSelf || pairedIds.contains(userRow['id'])
            ? userRow['phone']
            : '',
      };
    }).toList();
    final visibleSlips = isAdmin
        ? _slips
        : _slips
              .where((entry) => visibleIds.contains(entry['booking_id']))
              .toList();
    final visibleIssues = _issues
        .where((entry) => isAdmin || entry['reporter_id'] == viewerId)
        .toList();
    final busy = _bookings
        .where(
          (entry) =>
              entry['status'] != 'ownerRejected' && entry['status'] != 'canceled',
        )
        .map(
          (entry) => {
            'space_id': entry['space_id'],
            'booking_date': entry['booking_date'],
            'start_minutes': entry['start_minutes'],
            'end_minutes': entry['end_minutes'],
            'days_count': entry['days_count'],
          },
        )
        .toList();
    return {
      'userId': viewerId,
      'users': sanitizedUsers,
      'favorites': (_favoritesByUserId[viewerId] ?? const <String>{}).toList(),
      'spaces': _spaces.map((entry) => Map<String, dynamic>.from(entry)).toList(),
      'blocks': _blocks.map((entry) => Map<String, dynamic>.from(entry)).toList(),
      'bookings': visibleBookings
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
      'slips': visibleSlips
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
      'reviews': _reviews.map((entry) => Map<String, dynamic>.from(entry)).toList(),
      'issues': visibleIssues
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(),
      'busy': busy,
      'logs': isAdmin ? List<Map<String, dynamic>>.from(_logs) : const [],
    };
  }
}

class FakeHttpClient extends http.BaseClient {
  FakeHttpClient(this.backend);

  final FakeBackend backend;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest baseRequest) async {
    final rawAuth = baseRequest.headers['Authorization'] ?? '';
    final token = rawAuth.startsWith('Bearer ') ? rawAuth.substring(7) : null;
    final fullPath = baseRequest.url.path;
    final apiPath = fullPath.startsWith('/api')
        ? fullPath.substring(4)
        : fullPath;

    Map<String, dynamic>? jsonBody;
    String? fileName;
    Uint8List? fileBytes;
    var noteText = '';

    if (baseRequest is http.MultipartRequest) {
      noteText = baseRequest.fields['note'] ?? '';
      if (baseRequest.files.isNotEmpty) {
        final uploaded = baseRequest.files.first;
        fileName = uploaded.filename;
        fileBytes = await uploaded.finalize().toBytes();
      }
    } else if (baseRequest is http.Request && baseRequest.body.isNotEmpty) {
      jsonBody = Map<String, dynamic>.from(
        jsonDecode(baseRequest.body) as Map,
      );
    }

    final (statusCode, bodyMap) = await backend.dispatch(
      baseRequest.method,
      apiPath,
      token: token,
      jsonBody: jsonBody,
      fileName: fileName,
      fileBytes: fileBytes,
      noteText: noteText,
    );
    final encoded = utf8.encode(jsonEncode(bodyMap));
    return http.StreamedResponse(Stream.value(encoded), statusCode);
  }
}

AppStore createTestStore(FakeBackend backend) {
  final api = ApiClient(
    client: FakeHttpClient(backend),
    baseUrl: 'http://fake.local/api',
  );
  return AppStore(clock: () => _fixedNow, api: api);
}

Finder textFieldByLabel(String label) => find.byWidgetPredicate(
  (widget) =>
      widget is TextField &&
      (widget.decoration?.labelText == label ||
          widget.decoration?.hintText == label),
);

Future<void> configurePhoneViewport(
  WidgetTester tester, {
  Size size = const Size(430, 900),
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = viewInsets;
}

void resetViewport(WidgetTester tester) {
  tester.view.resetPhysicalSize();
  tester.view.resetDevicePixelRatio();
  tester.view.resetViewInsets();
}

Future<void> setupMockChannels(FakeBackend backend) async {
  FlutterSecureStorage.setMockInitialValues({});
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          final args = call.arguments as Map<dynamic, dynamic>?;
          backend.lastClipboardText = args?['text'] as String?;
        }
        return null;
      });
}

Future<AppStore> pumpRentSpaceApp(
  WidgetTester tester,
  FakeBackend backend, {
  bool resetTokenStorage = true,
  bool settle = true,
}) async {
  if (resetTokenStorage) {
    FlutterSecureStorage.setMockInitialValues({});
  }
  await setupMockChannels(backend);
  if (resetTokenStorage) {
    FlutterSecureStorage.setMockInitialValues({});
  }
  final store = createTestStore(backend);
  await tester.pumpWidget(RentSpaceApp(store: store));
  if (settle) {
    await tester.pumpAndSettle();
  }
  return store;
}

Future<void> disposeTestTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> tapWidget(WidgetTester tester, Finder finder) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> enterIntoField(
  WidgetTester tester,
  Finder finder,
  String text,
) async {
  expect(finder, findsOneWidget);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

Future<void> dismissSnackBars(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}

Future<void> loginViaUi(
  WidgetTester tester, {
  required String email,
  String password = 'password',
}) async {
  await enterIntoField(tester, textFieldByLabel('อีเมล'), email);
  await enterIntoField(
    tester,
    textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
    password,
  );
  await tapWidget(
    tester,
    find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
  );
}

Future<void> submitReasonDialog(WidgetTester tester, String reasonText) async {
  await enterIntoField(
    tester,
    textFieldByLabel('เหตุผล / รายละเอียด'),
    reasonText,
  );
  await tapWidget(tester, find.widgetWithText(FilledButton, 'ยืนยัน'));
}

Future<void> verifyBrokenImagesSettled(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('1. Authentication, Session Restore & Logout', () {
    testWidgets(
      'empty fields, wrong pw, network failure, suspended account, register & logout',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        final store = await pumpRentSpaceApp(tester, backend);

        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
        );
        expect(find.text('กรุณากรอกอีเมลและรหัสผ่าน'), findsOneWidget);
        await dismissSnackBars(tester);

        await enterIntoField(
          tester,
          textFieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'wrongpass',
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
        );
        expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
        expect(store.currentUser, isNull);
        await dismissSnackBars(tester);

        backend.failNextLoginNetwork = true;
        await enterIntoField(
          tester,
          textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'),
        );
        expect(
          find.text(
            'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบเครือข่ายและ API_BASE_URL',
          ),
          findsOneWidget,
        );
        await dismissSnackBars(tester);

        await loginViaUi(tester, email: 'suspended@rentspace.test');
        expect(find.text('บัญชีนี้ถูกระงับการใช้งาน'), findsOneWidget);
        expect(store.currentUser, isNull);
        await dismissSnackBars(tester);

        await tapWidget(tester, find.byTooltip('แสดงรหัสผ่าน'));
        await tapWidget(tester, find.byTooltip('ซ่อนรหัสผ่าน'));

        await tapWidget(tester, find.text('สมัครสมาชิก'));
        await tapWidget(tester, find.byTooltip('แสดงยืนยันรหัสผ่าน'));
        await tapWidget(tester, find.byTooltip('ซ่อนยืนยันรหัสผ่าน'));
        await tapWidget(tester, find.text('สร้างบัญชี'));
        expect(find.text('กรุณาระบุชื่อและอีเมลที่ถูกต้อง'), findsOneWidget);
        await dismissSnackBars(tester);

        await enterIntoField(
          tester,
          textFieldByLabel('ชื่อ-นามสกุล'),
          'สมาชิก ทดสอบ',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('อีเมล'),
          'newmember@rentspace.test',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('เบอร์โทรศัพท์ติดต่อ (เช่น 081-234-5678)'),
          '089-999-9999',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password123',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('ยืนยันรหัสผ่าน'),
          'password123',
        );
        await tapWidget(tester, find.byType(DropdownButtonFormField<UserRole>));
        await tapWidget(tester, find.text('เจ้าของพื้นที่').last);
        await tapWidget(tester, find.text('สร้างบัญชี'));

        expect(store.currentUser?.role, UserRole.owner);
        expect(find.text('ภาพรวม'), findsWidgets);

        await tapWidget(tester, find.byTooltip('ออกจากระบบ'));
        expect(store.currentUser, isNull);
        expect(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'), findsOneWidget);

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      'loading overlay during login, initial session restore spinner & poll retry banner',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        backend.loginDelay = Completer<void>();

        final store = await pumpRentSpaceApp(tester, backend);
        await enterIntoField(
          tester,
          textFieldByLabel('อีเมล'),
          'renter01@rentspace.test',
        );
        await enterIntoField(
          tester,
          textFieldByLabel('รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)'),
          'password',
        );
        await tester.tap(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'));
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(backend.loginCallCount, 1);

        backend.loginDelay!.complete();
        await tester.pumpAndSettle();
        expect(store.currentUser?.id, '1001');

        backend.failNextStateNetwork = true;
        await store.poll();
        await tester.pumpAndSettle();
        expect(
          find.text(
            'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ กรุณาตรวจสอบเครือข่ายและ API_BASE_URL',
          ),
          findsOneWidget,
        );
        expect(find.widgetWithText(TextButton, 'ลองใหม่'), findsOneWidget);

        backend.stateDelay = Completer<void>();
        await tester.tap(find.widgetWithText(TextButton, 'ลองใหม่'));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        backend.stateDelay!.complete();
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'ลองใหม่'), findsNothing);
        await disposeTestTree(tester);

        final savedToken = backend.issueTokenForUser('1001');
        FlutterSecureStorage.setMockInitialValues({'token': savedToken});
        await setupMockChannels(backend);
        FlutterSecureStorage.setMockInitialValues({'token': savedToken});
        backend.stateDelay = Completer<void>();
        final restoredStore = createTestStore(backend);
        await tester.pumpWidget(RentSpaceApp(store: restoredStore));
        await tester.pump();
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        backend.stateDelay!.complete();
        await tester.pumpAndSettle();
        expect(restoredStore.currentUser?.id, '1001');
        expect(find.text('ค้นหา'), findsWidgets);

        await disposeTestTree(tester);
      },
    );
  });

  group('2. Role Menus, Navigation, Search, Filter & Favorites', () {
    testWidgets(
      'renter search, filter sheet, empty results, favorites, theme toggle & nav tabs',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        final store = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');

        expect(find.text('ค้นหา'), findsOneWidget);
        expect(find.text('การจอง'), findsOneWidget);
        expect(find.text('รายการโปรด'), findsOneWidget);
        expect(find.text('โปรไฟล์'), findsOneWidget);
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await tapWidget(tester, find.byTooltip('โหมดมืด'));
        expect(store.darkMode, isTrue);
        await tapWidget(tester, find.byTooltip('โหมดสว่าง'));
        expect(store.darkMode, isFalse);

        final searchBox = textFieldByLabel(
          'ค้นหาชื่อ / ที่อยู่ / สิ่งอำนวยความสะดวก',
        );
        await enterIntoField(tester, searchBox, 'ไม่พบชื่อห้องนี้แน่นอน');
        expect(
          find.text('ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท'),
          findsOneWidget,
        );

        await tapWidget(tester, find.byTooltip('ล้างคำค้นหา'));
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await enterIntoField(tester, searchBox, 'อารีย์');
        expect(find.text('พบ 1 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);
        expect(find.text('เวิร์กสเปซ อารีย์'), findsOneWidget);
        await tapWidget(tester, find.byTooltip('ล้างคำค้นหา'));

        await tapWidget(tester, find.byKey(const ValueKey('open-filter-btn')));
        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'ห้องประชุม'));
        await tapWidget(tester, find.byKey(const ValueKey('sort-priceAsc')));
        await tapWidget(tester, find.text('ไม่เกิน ฿600'));
        await tapWidget(tester, find.text('8+ คน'));
        await tapWidget(tester, find.widgetWithText(FilledButton, 'ดูผลลัพธ์'));

        expect(find.text('ตัวกรอง (4)'), findsOneWidget);
        expect(find.text('สตูดิโอ กลางเมือง'), findsOneWidget);
        expect(find.text('เวิร์กสเปซ อารีย์'), findsNothing);

        await tapWidget(tester, find.byKey(const ValueKey('open-filter-btn')));
        await tapWidget(tester, find.text('12+ คน'));
        await tapWidget(tester, find.widgetWithText(FilledButton, 'ดูผลลัพธ์'));
        expect(
          find.text('ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท'),
          findsOneWidget,
        );

        await tapWidget(tester, find.widgetWithText(TextButton, 'ล้างตัวกรอง'));
        expect(find.text('ตัวกรอง'), findsOneWidget);
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await tapWidget(tester, find.byKey(const ValueKey('open-filter-btn')));
        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'สตูดิโอ'));
        await tapWidget(
          tester,
          find.widgetWithText(TextButton, 'ล้างค่าทั้งหมด'),
        );
        await tapWidget(tester, find.widgetWithText(FilledButton, 'ดูผลลัพธ์'));
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await tapWidget(tester, find.byTooltip('รายการโปรด').first);
        await tapWidget(
          tester,
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('รายการโปรด'),
          ),
        );
        expect(find.text('รายการโปรด (1 รายการ)'), findsOneWidget);
        await tapWidget(tester, find.byTooltip('รายการโปรด').first);
        expect(
          find.text('ยังไม่มีรายการโปรดที่ตรงกับตัวกรอง'),
          findsOneWidget,
        );

        await tapWidget(tester, find.byTooltip('ผู้เช่า หนึ่ง (ผู้เช่า)'));
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);
        await tapWidget(tester, find.text('rentSPACE'));
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      'owner dashboard tiles, urgent chips, missing bank, payouts & calendar tabs',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'owner02@rentspace.test');

        for (final tab in ['ภาพรวม', 'พื้นที่', 'การจอง', 'รายรับ', 'โปรไฟล์']) {
          expect(
            find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text(tab),
            ),
            findsOneWidget,
          );
        }
        expect(find.text('ยังไม่ได้ระบุบัญชีรับเงิน'), findsOneWidget);

        await tapWidget(tester, find.text('ยังไม่ได้ระบุบัญชีรับเงิน'));
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);
        await tapWidget(tester, find.byTooltip('ออกจากระบบ'));

        await loginViaUi(tester, email: 'owner01@rentspace.test');
        expect(find.text('แจ้งเตือนผู้ให้เช่า (2 รายการ)'), findsOneWidget);
        expect(find.text('คำขอรออนุมัติ (1)'), findsOneWidget);
        expect(find.text('รอกดยืนยันจบงาน (1)'), findsOneWidget);

        await tapWidget(tester, find.text('คำขอรออนุมัติ (1)'));
        expect(find.text('การจองพื้นที่'), findsOneWidget);
        await tapWidget(tester, find.text('ปฏิทิน'));
        expect(find.byType(CalendarDatePicker), findsOneWidget);
        await tapWidget(tester, find.text('ประวัติ'));
        expect(find.text('เวิร์กสเปซ อารีย์'), findsWidgets);

        await tapWidget(tester, find.text('รายรับ'));
        expect(find.text('คัดลอกสรุปรายรับ'), findsOneWidget);
        await tapWidget(tester, find.text('คัดลอกสรุปรายรับ'));
        expect(find.text('คัดลอกสรุปรายรับลง Clipboard แล้ว'), findsOneWidget);
        expect(backend.lastClipboardText, contains('รายงานรายรับ RentSpace'));
        await dismissSnackBars(tester);

        await tapWidget(tester, find.byTooltip('คัดลอกเลขบัญชี'));
        expect(backend.lastClipboardText, 'กสิกรไทย 123-4-56789-0');
        await dismissSnackBars(tester);

        await tapWidget(tester, find.widgetWithText(TextButton, 'แก้ไขบัญชี'));
        expect(find.text('โปรไฟล์ของฉัน'), findsOneWidget);

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      'admin dashboard urgent chips, moderation tabs, finance filters & user management',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'admin01@rentspace.test');

        expect(find.text('ตรวจสอบ'), findsOneWidget);
        expect(find.text('การเงิน'), findsOneWidget);
        expect(find.text('ผู้ใช้'), findsOneWidget);

        await tapWidget(tester, find.text('ประกาศรอตรวจ (1)'));
        expect(find.text('ห้องรอแอดมิน ตรวจ'), findsOneWidget);
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'อนุมัติประกาศ'),
        );
        expect(backend.findSpace('2004')['status'], 'approved');

        await tapWidget(tester, find.text('รายงานปัญหา (1)'));
        expect(find.text('แอร์ไม่เย็น'), findsOneWidget);
        await tapWidget(
          tester,
          find.widgetWithText(TextButton, 'บันทึกผลและปิดรายงาน'),
        );
        await submitReasonDialog(tester, 'ล้างแอร์เรียบร้อยแล้ว');
        expect(find.text('ผลการแก้ไข: ล้างแอร์เรียบร้อยแล้ว'), findsOneWidget);

        await tapWidget(tester, find.text('พื้นที่ทั้งหมด (5)'));
        await tapWidget(tester, find.text('ถูกระงับ (1)'));
        expect(find.text('ห้องซ้อม ถูกระงับ'), findsOneWidget);
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เปิดใช้งานใหม่'),
        );
        expect(backend.findSpace('2005')['status'], 'approved');

        await tapWidget(tester, find.text('การเงิน'));
        await tapWidget(tester, find.text('คัดลอกสรุปการเงิน'));
        expect(
          backend.lastClipboardText,
          contains('รายงานสรุปการเงิน RentSpace'),
        );
        await dismissSnackBars(tester);

        await tapWidget(tester, find.text('สถานะอื่นๆ'));
        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'ยกเลิกแล้ว'));
        expect(find.text('สถานะ: ยกเลิกแล้ว'), findsOneWidget);
        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'ทั้งหมด').first);

        await tapWidget(tester, find.text('ผู้ใช้'));
        await enterIntoField(
          tester,
          find.byKey(const ValueKey('user-search-field')),
          'ไม่มีคนนี้แน่นอน',
        );
        expect(
          find.text('ไม่พบบัญชีผู้ใช้ที่ตรงกับเงื่อนไข'),
          findsOneWidget,
        );
        await tapWidget(tester, find.byTooltip('ล้างคำค้นหา'));

        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'ผู้เช่า'));
        await enterIntoField(
          tester,
          find.byKey(const ValueKey('user-search-field')),
          'ผู้เช่า ไม่มีเบอร์',
        );
        final userSwitch = find.byType(Switch).first;
        await tapWidget(tester, userSwitch);
        await tapWidget(tester, userSwitch);

        await disposeTestTree(tester);
      },
    );
  });

  group('3. Space Form Validation, Add, Edit & Availability Page', () {
    testWidgets(
      'add/edit space form validation errors, categories, amenities, url preview & availability',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'owner01@rentspace.test');

        await tapWidget(
          tester,
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('พื้นที่'),
          ),
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'เพิ่มพื้นที่'),
        );

        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(
          find.text('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0'),
          findsOneWidget,
        );
        await dismissSnackBars(tester);

        await enterIntoField(
          tester,
          textFieldByLabel('ชื่อพื้นที่'),
          'ห้องสร้างใหม่ ทดสอบ',
        );
        await tapWidget(tester, find.widgetWithText(ChoiceChip, 'สตูดิโอ'));
        await enterIntoField(
          tester,
          textFieldByLabel('ที่อยู่'),
          'เอกมัย กรุงเทพ',
        );
        await enterIntoField(tester, textFieldByLabel('ราคา / ชั่วโมง (บาท)'), '500');
        await enterIntoField(tester, textFieldByLabel('ความจุ (คน)'), '15');
        await enterIntoField(
          tester,
          textFieldByLabel('คำอธิบาย'),
          'พื้นที่สว่าง โปร่งโล่ง',
        );
        await tapWidget(tester, find.widgetWithText(FilterChip, 'Wi-Fi'));
        await tapWidget(tester, find.widgetWithText(FilterChip, 'ไวท์บอร์ด'));

        await tapWidget(
          tester,
          find.widgetWithText(TextButton, 'หรือใช้ลิงก์ภาพ URL'),
        );
        await enterIntoField(
          tester,
          textFieldByLabel('ลิงก์ภาพ URL (https:// หรือ http://localhost)'),
          'http://insecure.example.com/room.jpg',
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(find.text('ลิงก์ภาพต้องขึ้นต้นด้วย https://'), findsOneWidget);
        await dismissSnackBars(tester);

        await enterIntoField(
          tester,
          textFieldByLabel('ลิงก์ภาพ URL (https:// หรือ http://localhost)'),
          'https://cdn.example.invalid/space.jpg',
        );
        await verifyBrokenImagesSettled(tester);
        expect(
          find.text('ไม่สามารถโหลดตัวอย่างภาพจากลิงก์นี้'),
          findsOneWidget,
        );

        await tapWidget(tester, find.widgetWithText(TextButton, 'ลบภาพ'));
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(find.text('ห้องสร้างใหม่ ทดสอบ'), findsOneWidget);

        await tapWidget(tester, find.widgetWithText(OutlinedButton, 'แก้ไข').first);
        await tapWidget(tester, find.widgetWithText(TextButton, 'ลบภาพ'));
        await enterIntoField(
          tester,
          textFieldByLabel('ชื่อพื้นที่'),
          'สตูดิโอ กลางเมือง (อัปเดต)',
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกและส่งตรวจสอบ'),
        );
        expect(find.text('สตูดิโอ กลางเมือง (อัปเดต)'), findsOneWidget);

        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'ตั้งเวลาว่าง / วันปิด').first,
        );
        await tapWidget(tester, find.byType(SwitchListTile).first);
        await tapWidget(tester, find.byType(SwitchListTile).first);

        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'เพิ่มช่วงปิด'),
        );
        await tapWidget(tester, find.text('ตกลง'));
        await tapWidget(tester, find.text('ตกลง'));
        await tapWidget(tester, find.text('ตกลง'));
        await submitReasonDialog(tester, 'ล้างพรมประจำเดือน');
        expect(find.textContaining('ล้างพรมประจำเดือน'), findsOneWidget);

        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'บันทึกการตั้งค่า'),
        );
        expect(find.text('พื้นที่ของฉัน'), findsOneWidget);

        await disposeTestTree(tester);
      },
    );
  });

  group('4. Reserve, Booking Confirmation, Conflict Error & Contact Edit', () {
    testWidgets(
      'date/time/days/attendees/zone selection, report space, contact fix & 409 slot conflict',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        final store = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'nophone@rentspace.test');

        await tapWidget(tester, find.text('ดูรายละเอียดและจอง').first);
        expect(find.text('รายละเอียดและสรุปการจอง'), findsOneWidget);

        await tapWidget(tester, find.byIcon(Icons.calendar_month));
        await tapWidget(tester, find.text('17'));
        await tapWidget(tester, find.text('ตกลง'));

        await tapWidget(tester, find.text('เหมาหลายวัน (ต่อเนื่อง)'));
        await tapWidget(tester, find.byKey(const ValueKey('days-preset-3')));
        await tapWidget(tester, find.byKey(const ValueKey('days-increment')));
        await tapWidget(tester, find.byKey(const ValueKey('days-decrement')));
        expect(find.textContaining('3 วัน'), findsWidgets);

        await tapWidget(tester, find.text('ใช้เวลาเต็มวัน'));
        expect(find.text('เริ่ม 09:00'), findsOneWidget);
        expect(find.text('สิ้นสุด 18:00'), findsOneWidget);

        await tapWidget(tester, find.text('รายชั่วโมง (1 วัน)'));
        await tapWidget(tester, find.byKey(const ValueKey('slot-780-840')));
        await tapWidget(tester, find.byKey(const ValueKey('slot-840-900')));
        expect(find.text('เริ่ม 13:00'), findsOneWidget);
        expect(find.text('สิ้นสุด 15:00'), findsOneWidget);

        await tapWidget(tester, find.widgetWithText(OutlinedButton, 'เริ่ม 13:00'));
        await tapWidget(tester, find.text('14:00').last);
        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'สิ้นสุด 15:00'),
        );
        await tapWidget(tester, find.text('24:00').last);
        expect(find.text('สิ้นสุด 24:00'), findsOneWidget);
        await tapWidget(tester, find.byKey(const ValueKey('slot-780-840')));

        await tapWidget(tester, find.byKey(const ValueKey('attendees-increment')));
        await tapWidget(tester, find.byKey(const ValueKey('attendees-decrement')));
        await tapWidget(tester, find.byKey(const ValueKey('attendees-preset-10')));

        await tapWidget(
          tester,
          find.widgetWithText(ChoiceChip, 'ห้องส่วนตัว / ประชุมย่อย'),
        );
        await tapWidget(
          tester,
          find.widgetWithText(ActionChip, 'ขอโปรเจกเตอร์/จอภาพ'),
        );

        await tapWidget(
          tester,
          find.widgetWithText(TextButton, 'รายงานปัญหาพื้นที่'),
        );
        await submitReasonDialog(tester, 'ทดสอบแจ้งปัญหาพื้นที่');
        await dismissSnackBars(tester);

        await tapWidget(tester, find.widgetWithText(FilledButton, 'ส่งคำขอจอง'));
        expect(find.text('ยืนยันการจอง'), findsOneWidget);

        final confirmBtn = find.byKey(const ValueKey('confirm-booking-btn'));
        expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNull);

        await tapWidget(tester, find.text('ระบุเบอร์'));
        await enterIntoField(
          tester,
          textFieldByLabel('เบอร์โทรศัพท์'),
          '089-888-7777',
        );
        await tapWidget(tester, find.widgetWithText(FilledButton, 'บันทึก'));
        await dismissSnackBars(tester);
        expect(store.currentUser?.phone, '089-888-7777');

        await tapWidget(
          tester,
          find.text('ฉันยอมรับเงื่อนไขการจองและกฎการใช้สถานที่'),
        );
        expect(tester.widget<FilledButton>(confirmBtn).onPressed, isNotNull);

        backend.failNextBookingConflict = true;
        await tapWidget(tester, confirmBtn);
        expect(find.text('ช่วงเวลานี้มีการจองแล้ว'), findsOneWidget);
        await dismissSnackBars(tester);

        await tapWidget(tester, confirmBtn);
        expect(find.text('รายละเอียดการจอง'), findsOneWidget);
        expect(find.text('หลักฐานและรหัสอ้างอิงการจอง'), findsOneWidget);

        await tapWidget(tester, find.byTooltip('กลับหน้าหลัก'));
        expect(find.text('ค้นหา'), findsWidgets);

        await disposeTestTree(tester);
      },
    );
  });

  group('5. Status Buttons, Slip Submit/Reject/Resubmit & Payout Slip', () {
    testWidgets(
      'slip submit -> admin reject -> renter resubmit -> admin approve -> owner complete -> payout & review',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        final store = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(
              store: store,
              bookingId: '3002',
              pickSlip: (_) async => (name: 'slip1.png', bytes: _validPngBytes),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tapWidget(
          tester,
          find.byKey(const ValueKey('copy-booking-id-btn')),
        );
        expect(backend.lastClipboardText, '3002');
        await dismissSnackBars(tester);

        await tapWidget(
          tester,
          find.byKey(const ValueKey('copy-booking-evidence-btn')),
        );
        expect(backend.lastClipboardText, contains('3002'));
        await dismissSnackBars(tester);

        await tapWidget(tester, find.byKey(const ValueKey('copy-account-btn')));
        expect(backend.lastClipboardText, '000-0-00000-0');
        await dismissSnackBars(tester);

        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
        );
        expect(find.text('แนบสลิป'), findsOneWidget);

        final submitSlipFinder = find.widgetWithText(
          FilledButton,
          'ส่งสลิปเพื่อตรวจสอบ',
        );
        expect(tester.widget<FilledButton>(submitSlipFinder).onPressed, isNull);

        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        await enterIntoField(
          tester,
          textFieldByLabel('หมายเหตุ (ไม่บังคับ)'),
          'โอนรอบแรกแล้ว',
        );
        await tapWidget(tester, submitSlipFinder);
        await dismissSnackBars(tester);
        expect(store.booking('3002').status, BookingStatus.slipReview);

        await disposeTestTree(tester);

        final adminBackendStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'admin01@rentspace.test');
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: adminBackendStore, bookingId: '3002'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('ตรวจแล้ว ยืนยันการจอง'), findsOneWidget);
        expect(find.text('ปฏิเสธสลิป'), findsOneWidget);
        expect(find.text('Admin ยกเลิกการจอง'), findsOneWidget);
        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'ปฏิเสธสลิป'),
        );
        await submitReasonDialog(tester, 'ยอดไม่ตรงและภาพเบลอ');
        expect(
          adminBackendStore.booking('3002').status,
          BookingStatus.slipRejected,
        );
        await disposeTestTree(tester);

        final resubmitStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(
              store: resubmitStore,
              bookingId: '3002',
              pickSlip: (_) async => (name: 'slip2.png', bytes: _validPngBytes),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('ยอดไม่ตรงและภาพเบลอ'), findsWidgets);

        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'แนบ / ส่งสลิปใหม่'),
        );
        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'เลือกภาพสลิป'),
        );
        await enterIntoField(
          tester,
          textFieldByLabel('หมายเหตุ (ไม่บังคับ)'),
          'ส่งสลิปใหม่ชัดแล้ว',
        );
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'ส่งสลิปเพื่อตรวจสอบ'),
        );
        await dismissSnackBars(tester);

        expect(resubmitStore.booking('3002').slips.length, 2);
        expect(resubmitStore.booking('3002').status, BookingStatus.slipReview);
        expect(find.text('ประวัติสลิปก่อนหน้า (1 รายการ)'), findsOneWidget);
        await tapWidget(tester, find.text('ประวัติสลิปก่อนหน้า (1 รายการ)'));

        await tapWidget(tester, find.byType(SlipImage).first);
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tapWidget(tester, find.byIcon(Icons.close));

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      'status button visibility guards, quick approve/reject, complete disabled/enabled, payout slip & review',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();

        final renterGuardStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: renterGuardStore, bookingId: '3001'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('ยกเลิกคำขอ'), findsOneWidget);
        expect(find.text('อนุมัติคำขอ'), findsNothing);
        expect(find.text('แนบ / ส่งสลิปใหม่'), findsNothing);
        await disposeTestTree(tester);

        final ownerStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'owner01@rentspace.test');

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: ownerStore, bookingId: '3001'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('อนุมัติคำขอ'), findsOneWidget);
        expect(find.text('ปฏิเสธคำขอ'), findsOneWidget);
        await tapWidget(
          tester,
          find.widgetWithText(FilledButton, 'อนุมัติคำขอ'),
        );
        await dismissSnackBars(tester);
        expect(ownerStore.booking('3001').status, BookingStatus.paymentDue);
        expect(find.text('อนุมัติคำขอ'), findsNothing);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: ownerStore, bookingId: '3004'),
          ),
        );
        await tester.pumpAndSettle();
        final earlyCompleteBtn = find.widgetWithText(
          FilledButton,
          'ทำเครื่องหมายว่าใช้บริการแล้ว',
        );
        expect(
          tester.widget<FilledButton>(earlyCompleteBtn).onPressed,
          isNull,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: ownerStore, bookingId: '3005'),
          ),
        );
        await tester.pumpAndSettle();
        final readyCompleteBtn = find.widgetWithText(
          FilledButton,
          'ทำเครื่องหมายว่าใช้บริการแล้ว',
        );
        expect(
          tester.widget<FilledButton>(readyCompleteBtn).onPressed,
          isNotNull,
        );
        await tapWidget(tester, readyCompleteBtn);
        expect(ownerStore.booking('3005').status, BookingStatus.completed);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: ownerStore, bookingId: '3009'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('อนุมัติคำขอ'), findsNothing);
        expect(find.text('ยกเลิกคำขอ'), findsNothing);
        expect(find.text('แนบ / ส่งสลิปใหม่'), findsNothing);

        await disposeTestTree(tester);

        final adminStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'admin01@rentspace.test');

        await tapWidget(
          tester,
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('การเงิน'),
          ),
        );
        await tapWidget(tester, find.text('ตรวจสลิปด่วน'));
        expect(find.text('ตรวจสลิปด่วน (#3003)'), findsOneWidget);
        await tapWidget(tester, find.widgetWithText(FilledButton, 'อนุมัติสลิป'));
        await dismissSnackBars(tester);
        expect(adminStore.booking('3003').status, BookingStatus.confirmed);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: adminStore, bookingId: '3004'),
          ),
        );
        await tester.pumpAndSettle();
        await tapWidget(
          tester,
          find.widgetWithText(TextButton, 'Admin ยกเลิกการจอง'),
        );
        await submitReasonDialog(tester, 'แอดมินยกเลิกตามคำร้อง');
        expect(adminStore.booking('3004').status, BookingStatus.canceled);
        expect(
          find.widgetWithText(TextButton, 'Admin ยกเลิกการจอง'),
          findsNothing,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showAdminPayoutDialog(
                      context,
                      store: adminStore,
                      booking: adminStore.booking('3006'),
                      pickSlip: (_) async =>
                          (name: 'payout_3006.png', bytes: _validPngBytes),
                    ),
                    child: const Text('เปิดหน้าต่างโอนเงิน'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tapWidget(tester, find.text('เปิดหน้าต่างโอนเงิน'));

        final confirmPayout = find.byKey(const ValueKey('payout-confirm-btn'));
        expect(tester.widget<FilledButton>(confirmPayout).onPressed, isNull);
        await tapWidget(
          tester,
          find.byKey(const ValueKey('payout-pick-slip-btn')),
        );
        expect(tester.widget<FilledButton>(confirmPayout).onPressed, isNotNull);
        await tapWidget(
          tester,
          find.byKey(const ValueKey('payout-clear-slip-btn')),
        );
        expect(tester.widget<FilledButton>(confirmPayout).onPressed, isNull);
        await tapWidget(
          tester,
          find.byKey(const ValueKey('payout-pick-slip-btn')),
        );
        await enterIntoField(
          tester,
          find.byKey(const ValueKey('payout-note-field')),
          'โอนปิดยอด 3006',
        );
        await tapWidget(tester, confirmPayout);
        expect(adminStore.booking('3006').paidOutAt, isNotNull);
        expect(adminStore.booking('3006').payoutSlip?.name, 'payout_3006.png');

        await disposeTestTree(tester);

        final renterReviewStore = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');
        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: renterReviewStore, bookingId: '3006'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('สลิปโอนเงินให้เจ้าของ (Admin)'), findsNothing);
        await tapWidget(tester, find.byTooltip('4 ดาว'));
        await enterIntoField(
          tester,
          textFieldByLabel('ความคิดเห็นหลังใช้งาน'),
          'ประทับใจมาก บริการดีเยี่ยม',
        );
        await tapWidget(tester, find.widgetWithText(FilledButton, 'ส่งรีวิว'));
        expect(renterReviewStore.booking('3006').review?.rating, 4);

        await disposeTestTree(tester);
      },
    );
  });

  group('6. Broken Images, Small Screen + Keyboard + Long Strings & Back/PopScope', () {
    testWidgets(
      'broken image bytes and failing network URL render fallback widgets without exceptions',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        backend.insertSpace({
          'id': '2999',
          'owner_id': '1002',
          'name': 'ห้องภาพเสีย ทดสอบ',
          'category': 'ห้องประชุม',
          'location': 'กรุงเทพ',
          'price': 300,
          'capacity': 6,
          'description': 'ทดสอบ fallback ภาพเสีย',
          'image': 'data:image/png;base64,${base64Encode(_brokenImageBytes)}',
          'amenities': ['Wi-Fi'],
          'status': 'approved',
          'hours': List.generate(
            7,
            (_) => {'open': true, 'start': 540, 'end': 1080},
          ),
          'avg_rating': null,
          'review_count': 0,
          'review_reason': '',
        });

        final store = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');
        await verifyBrokenImagesSettled(tester);

        await tapWidget(tester, find.text('ห้องภาพเสีย ทดสอบ'));
        await verifyBrokenImagesSettled(tester);
        expect(find.text('รายละเอียดและสรุปการจอง'), findsOneWidget);

        await tapWidget(tester, find.widgetWithText(FilledButton, 'ส่งคำขอจอง'));
        await verifyBrokenImagesSettled(tester);
        expect(find.text('ยืนยันการจอง'), findsOneWidget);

        final brokenSlip = PaymentSlip(
          name: 'broken_slip.png',
          bytes: _brokenImageBytes,
          submittedAt: _fixedNow,
        );
        final netSlip = PaymentSlip(
          name: 'net_slip.png',
          bytes: Uint8List(0),
          submittedAt: _fixedNow,
          imageUrl: 'https://invalid.example.invalid/broken-slip.png',
        );
        final brokenSpace = store.space('2999');

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: Scaffold(
              body: Column(
                children: [
                  SlipImage(brokenSlip, height: 80),
                  SlipImage(netSlip, height: 80),
                  SpaceImage(
                    brokenSpace,
                    height: 80,
                    fallback: const Text('ภาพพื้นที่สำรอง'),
                  ),
                ],
              ),
            ),
          ),
        );
        await verifyBrokenImagesSettled(tester);
        expect(find.text('ไม่สามารถเปิดภาพได้'), findsNWidgets(2));
        expect(find.text('ภาพพื้นที่สำรอง'), findsOneWidget);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: SpaceForm(store: store, space: brokenSpace),
          ),
        );
        await verifyBrokenImagesSettled(tester);

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      '360x740 small viewport with open keyboard (viewInsets 300) and long Thai text has zero overflow',
      (tester) async {
        await configurePhoneViewport(
          tester,
          size: const Size(360, 740),
          viewInsets: const FakeViewPadding(bottom: 300),
        );
        addTearDown(() => resetViewport(tester));

        final backend = FakeBackend();
        const longThaiText =
            'ห้องประชุมอเนกประสงค์ขนาดใหญ่ใจกลางย่านธุรกิจพร้อมระบบเสียงและแสงมาตรฐานระดับมืออาชีพสำหรับการจัดประชุมสัมมนาเวิร์กช็อปและกิจกรรมองค์กรทุกขนาดอย่างครบครันพร้อมที่จอดรถและอินเทอร์เน็ตความเร็วสูงตลอดวัน';
        backend.insertSpace({
          'id': '2888',
          'owner_id': '1002',
          'name': longThaiText,
          'category': 'ห้องประชุม',
          'location': longThaiText,
          'price': 999,
          'capacity': 50,
          'description': longThaiText,
          'image': '',
          'amenities': ['Wi-Fi', 'โปรเจกเตอร์', 'ระบบเสียง'],
          'status': 'approved',
          'hours': List.generate(
            7,
            (_) => {'open': true, 'start': 540, 'end': 1080},
          ),
          'avg_rating': null,
          'review_count': 0,
          'review_reason': longThaiText,
        });

        final store = await pumpRentSpaceApp(tester, backend);
        expect(tester.takeException(), isNull);

        await loginViaUi(tester, email: 'renter01@rentspace.test');
        expect(tester.takeException(), isNull);

        await tapWidget(tester, find.text(longThaiText).first);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: SpaceForm(store: store, space: store.space('2888')),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('th'),
            home: BookingPage(store: store, bookingId: '3008'),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await disposeTestTree(tester);
      },
    );

    testWidgets(
      'system back (PopScope) returns non-zero nav tab to home, route back navigation & clean logout',
      (tester) async {
        await configurePhoneViewport(tester);
        addTearDown(() => resetViewport(tester));
        final backend = FakeBackend();
        final store = await pumpRentSpaceApp(tester, backend);
        await loginViaUi(tester, email: 'renter01@rentspace.test');

        await tapWidget(
          tester,
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text('การจอง'),
          ),
        );
        expect(find.text('การจองของฉัน'), findsOneWidget);

        final homeContext = tester.element(find.byType(HomePage));
        await Navigator.of(homeContext).maybePop();
        await tester.pumpAndSettle();
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await tapWidget(tester, find.text('ดูรายละเอียดและจอง').first);
        await tapWidget(tester, find.widgetWithText(FilledButton, 'ส่งคำขอจอง'));
        expect(find.text('ยืนยันการจอง'), findsOneWidget);

        await tapWidget(
          tester,
          find.widgetWithText(OutlinedButton, 'กลับไปแก้ไขข้อมูลการจอง'),
        );
        expect(find.text('รายละเอียดและสรุปการจอง'), findsOneWidget);

        expect(find.byTooltip('กลับ'), findsOneWidget);
        await tapWidget(tester, find.byIcon(Icons.arrow_back));
        expect(find.text('พบ 3 พื้นที่ที่ตรงกับเงื่อนไข'), findsOneWidget);

        await tapWidget(tester, find.byTooltip('ออกจากระบบ'));
        expect(store.currentUser, isNull);
        expect(store.bookings, isEmpty);
        expect(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'), findsOneWidget);

        await disposeTestTree(tester);
      },
    );
  });
}
