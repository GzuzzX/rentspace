import 'dart:typed_data';

import '../data/app_store.dart';
import '../models/domain.dart';

/// จัดการสลิป การตรวจชำระเงิน และบันทึกจ่ายเจ้าของผ่าน backend API
class PaymentController {
  PaymentController(this._store);

  final AppStore _store;

  static const maxBytes = 5 * 1024 * 1024;

  Future<void> submitAsync(
    String id,
    String name,
    Uint8List bytes,
    String note,
  ) async {
    validateSlip(name, bytes);
    await _store.api.upload('/payments/$id/slip', name, bytes, note.trim());
    await _store.refreshAfterMutation();
  }

  Future<void> reviewAsync(String id, bool approve, String reason) async {
    if (!approve && reason.trim().isEmpty) {
      throw DomainError('กรุณาระบุเหตุผลที่สลิปไม่ผ่าน');
    }
    await _store.mutate('POST', '/payments/$id/review', {
      'approve': approve,
      'reason': reason.trim(),
    });
  }

  Future<void> payoutAsync(
    String id, {
    String? fileName,
    Uint8List? bytes,
    String note = '',
  }) async {
    final trimmedNote = note.trim();
    if (fileName != null || bytes != null) {
      final resolvedName = fileName ?? '';
      final resolvedBytes = bytes ?? Uint8List(0);
      validateSlip(resolvedName, resolvedBytes);
      await _store.api.upload(
        '/payments/$id/payout',
        resolvedName,
        resolvedBytes,
        trimmedNote,
      );
      await _store.refreshAfterMutation();
      return;
    }
    await _store.mutate(
      'POST',
      '/payments/$id/payout',
      trimmedNote.isEmpty ? null : {'note': trimmedNote},
    );
  }

  static void validateSlip(String name, Uint8List bytes) {
    final extension = name.split('.').last.toLowerCase();
    final png =
        bytes.length >= 8 &&
        [
          137,
          80,
          78,
          71,
          13,
          10,
          26,
          10,
        ].asMap().entries.every((e) => bytes[e.key] == e.value);
    final jpg =
        bytes.length >= 3 &&
        bytes[0] == 255 &&
        bytes[1] == 216 &&
        bytes[2] == 255;
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw DomainError('ภาพต้องมีขนาดมากกว่า 0 และไม่เกิน 5 MB');
    }
    if (!((extension == 'png' && png) ||
        (['jpg', 'jpeg'].contains(extension) && jpg))) {
      throw DomainError('รองรับภาพ JPG และ PNG เท่านั้น');
    }
  }
}
