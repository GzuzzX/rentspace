import '../models/domain.dart';
import 'store_service.dart';

/// service ของการชำระเงิน: เข้าถึงรายการจองที่ต้องตรวจสลิป
class PaymentService extends StoreService {
  PaymentService(super.store);

  Booking booking(String id) => store.booking(id);

  /// รายการที่รอตรวจสลิป (ใช้กับหน้าคิวของ Admin)
  List<Booking> pendingSlips() => store.bookings
      .where((b) => b.status == BookingStatus.slipReview)
      .toList();

  /// รายการที่จบแล้วแต่ยังไม่ได้จ่ายเจ้าของ
  List<Booking> readyPayouts() => store.bookings
      .where((b) => b.status == BookingStatus.completed && b.paidOutAt == null)
      .toList();
}
