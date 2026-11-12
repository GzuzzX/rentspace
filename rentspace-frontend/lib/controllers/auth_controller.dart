import 'dart:async';
import 'dart:convert';

import '../data/app_store.dart';
import '../models/domain.dart';
import '../services/auth_service.dart';
import '../services/token_service.dart';

class AuthController {
  /// แบบของตัวอย่างอาจารย์: ไม่ส่่ง tokenService = ใช้ของจริง,
  /// ส่งมา = ใช้ตัวที่ฉีดเข้ามา (mock ในเทสต์)
  AuthController(AppStore store, {TokenService? tokenService})
    : _svc = AuthService(store),
      _tokens = tokenService ?? TokenService();

  /// สำหรับเทสต์: ฉีด service ปลอม (mock) เข้ามาแทนของจริง
  AuthController.withService(this._svc, {TokenService? tokenService})
    : _tokens = tokenService ?? TokenService();

  final AuthService _svc;
  final TokenService _tokens;
  static bool validEmail(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());
  /// token ที่เก็บไว้อาจเป็น user id ตรง ๆ หรือ JWT จาก backend
  /// (JWT มี 3 ส่วนคั่นด้วยจุด — อ่าน sub จากส่วนกลางโดยไม่ต้องตรวจลายเซ็น)
  static String _subjectOf(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return token;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final sub = payload is Map ? payload['sub'] : null;
      return sub is String && sub.isNotEmpty ? sub : token;
    } catch (_) {
      return token;
    }
  }

  void login(String email, String password) {
    final matches = _svc.matchCredentials(email, password);
    if (matches.isEmpty) throw DomainError('อีเมลหรือรหัสผ่านไม่ถูกต้อง');
    if (!matches.first.active) throw DomainError('บัญชีนี้ถูกระงับการใช้งาน');
    _svc.signIn(matches.first);
    unawaited(_tokens.saveToken(matches.first.id));
    _svc.changed('เข้าสู่ระบบ');
    _svc.sweepExpired();
  }

  void demo(UserRole role) {
    final account = _svc.user(switch (role) {
      UserRole.renter => 'renter-1',
      UserRole.owner => 'owner-1',
      UserRole.admin => 'admin-1',
    });
    login(account.email, account.password);
  }

  void logout() {
    _svc.changed('ออกจากระบบ');
    _svc.signOut();
    unawaited(_tokens.deleteToken());
  }

  /// คืนเซสชันเดิมหลังเปิดแอปใหม่ (อ่าน token ที่เก็บไว้)
  Future<AppUser?> restoreSession() async {
    final stored = await _tokens.loadToken();
    if (stored == null) return null;
    final id = _subjectOf(stored);
    final AppUser account;
    try {
      account = _svc.user(id);
    } catch (_) {
      await _tokens.deleteToken();
      return null;
    }
    if (!account.active) return null;
    _svc.signIn(account);
    _svc.changed('คืนเซสชันผู้ใช้');
    return account;
  }

  void register(
    String name,
    String email,
    String password,
    UserRole role,
    String phone, [
    String? confirmPassword,
  ]) {
    if (role == UserRole.admin) throw DomainError('ไม่สามารถสมัครบัญชี Admin');
    validateProfile(name, email, phone);
    if (password.length < 8) {
      throw DomainError('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
    }
    _validateConfirmPassword(password, confirmPassword);
    final user = AppUser(
      id: _svc.nextId('USER'),
      name: name.trim(),
      email: email.trim().toLowerCase(),
      password: password,
      role: role,
      phone: phone.trim(),
    );
    _svc.addUser(user);
    _svc.signIn(user);
    _svc.changed('สมัครสมาชิก');
  }

  void _validateConfirmPassword(String password, String? confirmPassword) {
    if (confirmPassword == null) return;
    if (confirmPassword.isEmpty) {
      throw DomainError('กรุณายืนยันรหัสผ่าน');
    }
    if (password != confirmPassword) {
      throw DomainError('ยืนยันรหัสผ่านไม่ตรงกัน');
    }
  }

  void validateProfile(
    String name,
    String email,
    String phone, {
    String? excluding,
  }) {
    if (name.trim().isEmpty || !validEmail(email)) {
      throw DomainError('กรุณาระบุชื่อและอีเมลที่ถูกต้อง');
    }
    if (_svc.users.any(
      (u) =>
          u.id != excluding &&
          u.email.toLowerCase() == email.trim().toLowerCase(),
    )) {
      throw DomainError('อีเมลนี้ถูกใช้งานแล้ว');
    }
    if (phone.trim().isEmpty || !RegExp(r'^[0-9+\- ]{8,15}$').hasMatch(phone.trim())) {
      throw DomainError('หมายเลขโทรศัพท์ไม่ถูกต้อง');
    }
  }

  void updateProfile(
    String name,
    String email,
    String phone, [
    String? bankInfo,
  ]) {
    final u = _svc.requireUser();
    validateProfile(name, email, phone, excluding: u.id);
    u.name = name.trim();
    u.email = email.trim().toLowerCase();
    u.phone = phone.trim();
    if (bankInfo != null) {
      u.bankInfo = bankInfo.trim();
    }
    _svc.changed('บันทึกโปรไฟล์');
  }

  void changePassword(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) {
    final u = _svc.requireUser();
    if (u.password != currentPassword) {
      throw DomainError('รหัสผ่านปัจจุบันไม่ถูกต้อง');
    }
    if (newPassword.length < 8) {
      throw DomainError('รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร');
    }
    if (newPassword != confirmPassword) {
      throw DomainError('ยืนยันรหัสผ่านใหม่ไม่ตรงกัน');
    }
    u.password = newPassword;
    _svc.changed('เปลี่ยนรหัสผ่าน');
  }

  List<AppUser> filterUsers({String query = '', UserRole? role}) {
    final q = query.trim().toLowerCase();
    return _svc.users.where((u) {
      if (role != null && u.role != role) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
  }

  void toggleUser(String id) {
    final admin = _svc.requireUser(UserRole.admin);
    final u = _svc.user(id);
    if (u.id == admin.id || u.role == UserRole.admin) {
      throw DomainError('ไม่สามารถระงับบัญชี Admin');
    }
    u.active = !u.active;
    _svc.changed('${u.active ? 'เปิดใช้งาน' : 'ระงับ'}บัญชี ${u.email}');
  }
}
