import '../models/domain.dart';
import 'store_service.dart';

/// service ของบัญชีผู้ใช้: ล็อกอิน ค้นหาบัญชี และเซสชันปัจจุบัน
class AuthService extends StoreService {
  AuthService(super.store);

  /// ค้นหาบัญชีที่ใช้อีเมลและรหัสผ่านตรงกัน
  List<AppUser> matchCredentials(String email, String password) => store.users
      .where(
        (u) =>
            u.email.toLowerCase() == email.trim().toLowerCase() &&
            u.password == password,
      )
      .toList();

  /// เปิดเซสชัน (ตั้งผู้ใช้ที่ล็อกอินอยู่)
  void signIn(AppUser user) => store.currentUser = user;

  /// ปิดเซสชัน
  void signOut() => store.currentUser = null;

  /// เพิ่มบัญชีใหม่เข้าที่เก็บ
  void addUser(AppUser user) => store.users.add(user);
}
