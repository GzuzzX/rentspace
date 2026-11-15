import 'package:flutter/foundation.dart';

import '../data/app_store.dart';
import '../models/domain.dart';
import '../services/api_client.dart';
import '../services/token_service.dart';

/// จัดการบัญชีและเซสชันผ่าน backend API และ TokenService
class AuthController {
  AuthController(AppStore store, {TokenService? tokenService})
    : _store = store,
      _tokens = tokenService ?? TokenService();

  static final _versions = Expando<int>();
  final AppStore _store;
  final TokenService _tokens;

  int get _version => _versions[_store] ?? 0;

  void _invalidateRestore() => _versions[_store] = _version + 1;

  Future<void> loginAsync(String email, String password) async {
    if (email.trim().isEmpty || password.isEmpty) {
      throw DomainError('กรุณากรอกอีเมลและรหัสผ่าน');
    }
    _invalidateRestore();
    final version = _version;
    final authPayload = await _store.api.request('POST', '/auth/login', {
      'email': email.trim(),
      'password': password,
    });
    if (version != _version) return;
    await _openRemote(authPayload['token'] as String);
  }

  Future<void> _openRemote(String token) async {
    final version = _version;
    final session = _store.beginSession(token);
    try {
      await _store.refresh();
      if (version == _version && session == _store.sessionVersion) {
        await _tokens.saveToken(token);
      }
    } catch (_) {
      if (session == _store.sessionVersion) _store.clearSession();
      rethrow;
    }
  }

  Future<AppUser?> restoreSessionAsync() async {
    final version = _version;
    final token = await _tokens.loadToken();
    if (version != _version || token == null) return null;
    try {
      await _openRemote(token);
    } on ApiError catch (e) {
      if (e.status != 401) rethrow;
      await _tokens.deleteToken();
      return null;
    }
    return _store.currentUser;
  }

  Future<void> registerAsync(
    String name,
    String email,
    String password,
    UserRole role,
    String phone, [
    String? confirmPassword,
  ]) async {
    if (role == UserRole.admin) throw DomainError('ไม่สามารถสมัครบัญชี Admin');
    validateProfile(name, email, phone);
    if (password.length < 8) {
      throw DomainError('รหัสผ่านต้องมีอย่างน้อย 8 ตัวอักษร');
    }
    _validateConfirmPassword(password, confirmPassword);
    _invalidateRestore();
    final version = _version;
    final authPayload = await _store.api.request('POST', '/auth/register', {
      'name': name.trim(),
      'email': email.trim(),
      'password': password,
      'role': role.name,
      'phone': phone.trim(),
    });
    if (version != _version) return;
    await _openRemote(authPayload['token'] as String);
  }

  Future<void> logoutAsync() async {
    _invalidateRestore();
    if (_store.api.token != null) {
      try {
        await _store.api.request('POST', '/auth/logout');
      } on Object catch (err) {
        debugPrint('Best-effort logout request failed: $err');
      }
    }
    _store.clearSession();
    await _tokens.deleteToken();
  }

  Future<void> updateProfileAsync(
    String name,
    String email,
    String phone, [
    String? bankInfo,
  ]) async {
    validateProfile(name, email, phone, excluding: _store.currentUser?.id);
    await _store.mutate('PUT', '/auth/profile', {
      'name': name.trim(),
      'email': email.trim(),
      'phone': phone.trim(),
      'bankInfo': ?bankInfo,
    });
  }

  Future<void> changePasswordAsync(
    String currentPassword,
    String newPassword,
    String confirmPassword,
  ) async {
    if (currentPassword.isEmpty) {
      throw DomainError('กรุณากรอกรหัสผ่านปัจจุบัน');
    }
    if (newPassword.length < 8) {
      throw DomainError('รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร');
    }
    if (newPassword != confirmPassword) {
      throw DomainError('ยืนยันรหัสผ่านใหม่ไม่ตรงกัน');
    }
    await _store.mutate('PUT', '/auth/password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      'confirmPassword': confirmPassword,
    });
  }

  Future<void> toggleUserAsync(String id) async {
    await _store.mutate('PUT', '/admin/users/$id/toggle');
  }

  static bool validEmail(String s) =>
      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(s.trim());

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
    final duplicate = _store.users.any(
      (u) =>
          u.id != excluding &&
          u.email.toLowerCase() == email.trim().toLowerCase(),
    );
    if (duplicate) throw DomainError('อีเมลนี้ถูกใช้งานแล้ว');
    if (phone.trim().isEmpty ||
        !RegExp(r'^[0-9+\- ]{8,15}$').hasMatch(phone.trim())) {
      throw DomainError('หมายเลขโทรศัพท์ไม่ถูกต้อง');
    }
  }

  List<AppUser> filterUsers({String query = '', UserRole? role}) {
    final q = query.trim().toLowerCase();
    return _store.users.where((u) {
      if (role != null && u.role != role) return false;
      if (q.isEmpty) return true;
      return u.name.toLowerCase().contains(q) ||
          u.email.toLowerCase().contains(q);
    }).toList();
  }
}
