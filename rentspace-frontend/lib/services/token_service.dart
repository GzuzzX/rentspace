import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// service เก็บ session token ของผู้ใช้ (แบบเดียวกับ authService ในตัวอย่างอาจารย์)
///
/// เป็น dependency ที่ถูก inject เข้า AuthController — ในเทสต์จะสลับเป็น mock
class TokenService {
  TokenService({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const tokenKey = 'token';
  final FlutterSecureStorage _storage;

  Future<void> saveToken(String token) async {
    try {
      await _storage.write(key: tokenKey, value: token);
    } catch (e) {
      // เครื่องที่ไม่มี keystore (เช่นตอนรันเทสต์) ต้องไม่ทำให้ล็อกอินพัง
      debugPrint('saveToken failed: $e');
    }
  }

  Future<String?> loadToken() async {
    try {
      return await _storage.read(key: tokenKey);
    } catch (e) {
      debugPrint('loadToken failed: $e');
      return null;
    }
  }

  Future<void> deleteToken() async {
    try {
      await _storage.delete(key: tokenKey);
    } catch (e) {
      debugPrint('deleteToken failed: $e');
    }
  }
}
