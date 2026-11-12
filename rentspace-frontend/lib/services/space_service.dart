import '../models/domain.dart';
import 'store_service.dart';

/// service ของพื้นที่: ประกาศพื้นที่ เวลาว่าง รายงานปัญหา และรายการโปรด
class SpaceService extends StoreService {
  SpaceService(super.store);

  List<Space> get spaces => store.spaces;

  Space space(String id) => store.space(id);

  List<Booking> get bookings => store.bookings;

  List<Issue> get issues => store.issues;

  /// เพิ่มประกาศพื้นที่ใหม่
  void addSpace(Space space) => store.spaces.add(space);

  /// เพิ่มรายงานปัญหาไว้บนสุดของรายการ
  void addIssue(Issue issue) => store.issues.insert(0, issue);
}
