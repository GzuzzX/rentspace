import '../models/domain.dart';
import 'store_service.dart';

/// service ของการจอง: เข้าถึงรายการจองและพื้นที่ที่เกี่ยวข้อง
class BookingService extends StoreService {
  BookingService(super.store);

  List<Booking> get bookings => store.bookings;

  Booking booking(String id) => store.booking(id);

  Space space(String id) => store.space(id);

  /// เพิ่มคำขอจองใหม่ไว้บนสุดของรายการ
  void insertBooking(Booking booking) => store.bookings.insert(0, booking);

  /// รายการจองของพื้นที่หนึ่งที่ยังกันเวลาอยู่
  List<Booking> activeBookingsOf(String spaceId) => store.bookings
      .where((b) => b.spaceId == spaceId && b.status.holdsTime)
      .toList();
}
