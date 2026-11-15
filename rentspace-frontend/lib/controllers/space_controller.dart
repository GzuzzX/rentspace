import 'dart:convert';
import 'dart:typed_data';

import '../data/app_store.dart';
import '../models/domain.dart';

/// จัดการประกาศพื้นที่ การค้นหา เวลาทำการ รายการโปรด และรายงานปัญหาผ่าน backend API
class SpaceController {
  SpaceController(this._store);

  final AppStore _store;

  Future<Space> saveAsync({
    String? id,
    required String name,
    required String category,
    required String location,
    required int price,
    required int capacity,
    required String description,
    required List<String> amenities,
    String image = '',
    Uint8List? imageBytes,
  }) async {
    _validateSpaceInput(
      name: name,
      category: category,
      location: location,
      price: price,
      capacity: capacity,
      description: description,
      image: image,
    );
    final payload = _buildSpacePayload(
      id: id,
      name: name,
      category: category,
      location: location,
      price: price,
      capacity: capacity,
      description: description,
      amenities: amenities,
      image: image,
      imageBytes: imageBytes,
    );
    final response = await _store.mutate(
      id == null ? 'POST' : 'PUT',
      id == null ? '/spaces' : '/spaces/$id',
      payload,
    );
    return _store.space(id ?? response['id'] as String);
  }

  void _validateSpaceInput({
    required String name,
    required String category,
    required String location,
    required int price,
    required int capacity,
    required String description,
    required String image,
  }) {
    if ([name, category, location, description].any((s) => s.trim().isEmpty) ||
        price <= 0 ||
        capacity <= 0) {
      throw DomainError('กรอกข้อมูลให้ครบ ราคาและความจุต้องมากกว่า 0');
    }
    final trimmedImage = image.trim();
    if (trimmedImage.isNotEmpty && !trimmedImage.startsWith('/api/spaces/')) {
      final imageUri = Uri.tryParse(trimmedImage);
      final apiUri = Uri.tryParse(_store.api.baseUrl);
      final isHttps = imageUri?.scheme == 'https';
      final matchesApiHttpOrigin =
          apiUri != null &&
          apiUri.scheme == 'http' &&
          imageUri?.scheme == 'http' &&
          apiUri.host.isNotEmpty &&
          imageUri?.host == apiUri.host &&
          imageUri?.port == apiUri.port;
      final isLocalHttp =
          imageUri?.scheme == 'http' &&
          (imageUri?.host == 'localhost' ||
              imageUri?.host == '127.0.0.1' ||
              matchesApiHttpOrigin);
      if (!isHttps && !isLocalHttp) {
        throw DomainError('ลิงก์ภาพต้องขึ้นต้นด้วย https://');
      }
    }
  }

  Map<String, dynamic> _buildSpacePayload({
    required String? id,
    required String name,
    required String category,
    required String location,
    required int price,
    required int capacity,
    required String description,
    required List<String> amenities,
    required String image,
    required Uint8List? imageBytes,
  }) {
    final encodedImage = imageBytes == null
        ? image.trim()
        : 'data:image/${imageBytes.length > 3 && imageBytes[0] == 137 ? 'png' : 'jpeg'};base64,${base64Encode(imageBytes)}';
    final hours = (id == null ? Availability() : _store.space(id).availability)
        .days
        .map((d) => {'open': d.open, 'start': d.start, 'end': d.end})
        .toList();
    return {
      'name': name.trim(),
      'category': category.trim(),
      'location': location.trim(),
      'price': price,
      'capacity': capacity,
      'description': description.trim(),
      'amenities': amenities
          .where((a) => a.trim().isNotEmpty)
          .map((a) => a.trim())
          .toList(),
      'image': encodedImage,
      'hours': hours,
    };
  }

  Future<void> saveAvailabilityAsync(String id, Availability value) async {
    _validateAvailability(id, value);
    await _store.mutate('PUT', '/spaces/$id/availability', {
      'days': value.days
          .map((d) => {'open': d.open, 'start': d.start, 'end': d.end})
          .toList(),
      'blocks': value.blocks
          .map(
            (b) => {
              'start': b.start.toIso8601String(),
              'end': b.end.toIso8601String(),
              'reason': b.reason.trim(),
            },
          )
          .toList(),
    });
  }

  void _validateAvailability(String id, Availability value) {
    if (value.days.length != 7 ||
        value.days.any((d) => d.start < 0 || d.end > 1440 || d.end <= d.start)) {
      throw DomainError('เวลาปิดต้องอยู่หลังเวลาเปิด');
    }
    if (value.blocks.any(
      (b) => !b.end.isAfter(b.start) || b.reason.trim().isEmpty,
    )) {
      throw DomainError('ช่วงปิดหรือเหตุผลไม่ถูกต้อง');
    }
    final overlapsBooking = _store.bookings.any(
      (b) =>
          b.spaceId == id &&
          b.status.holdsTime &&
          b.endsAt.isAfter(_store.clock()) &&
          !value.acceptsRange(
            b.date,
            b.startMinutes,
            b.endMinutes,
            days: b.days,
          ),
    );
    if (overlapsBooking) {
      throw DomainError('เวลาที่ตั้งทับรายการจองเดิม กรุณาจัดการการจองก่อน');
    }
  }

  Future<void> reviewAsync(String id, bool approve, String reason) async {
    if (!approve && reason.trim().isEmpty) {
      throw DomainError('กรุณาระบุเหตุผลที่ปฏิเสธ');
    }
    await _store.mutate(
      'PUT',
      '/admin/spaces/$id/${approve ? 'approve' : 'reject'}',
      {'reason': reason.trim()},
    );
  }

  Future<void> suspendSpaceAsync(String id, String reason) async {
    if (reason.trim().isEmpty) {
      throw DomainError('กรุณาระบุเหตุผลการระงับพื้นที่');
    }
    await _store.mutate('PUT', '/admin/spaces/$id/reject', {
      'reason': reason.trim(),
    });
  }

  Future<void> activateSpaceAsync(String id) async {
    await _store.mutate('PUT', '/admin/spaces/$id/activate');
  }

  Future<void> favoriteAsync(String id) async {
    await _store.mutate('POST', '/spaces/$id/favorite');
  }

  Future<void> reportAsync(String subject, String detail) async {
    if (detail.trim().isEmpty) {
      throw DomainError('กรุณาระบุรายละเอียด');
    }
    await _store.mutate('POST', '/admin/issues', {
      'subject': subject,
      'detail': detail.trim(),
    });
  }

  Future<void> closeIssueAsync(String id, String resolution) async {
    if (resolution.trim().isEmpty) {
      throw DomainError('กรุณาระบุผลการแก้ไข');
    }
    await _store.mutate('PUT', '/admin/issues/$id/close', {
      'resolution': resolution.trim(),
    });
  }

  List<Space> filterSpaces({
    bool favoritesOnly = false,
    String category = 'ทั้งหมด',
    String query = '',
    SpaceSort sort = SpaceSort.recommended,
    int? maxPrice,
    int? minCapacity,
  }) {
    final filtered = _store.spaces
        .where(
          (s) => _matchesFilter(
            s,
            favoritesOnly: favoritesOnly,
            category: category,
            query: query,
            maxPrice: maxPrice,
            minCapacity: minCapacity,
          ),
        )
        .toList();
    _sortSpaces(filtered, sort);
    return filtered;
  }

  bool _isOwnerActive(String ownerId) {
    for (final user in _store.users) {
      if (user.id == ownerId) return user.active;
    }
    return false;
  }

  bool _matchesFilter(
    Space space, {
    required bool favoritesOnly,
    required String category,
    required String query,
    int? maxPrice,
    int? minCapacity,
  }) {
    if (space.status != SpaceStatus.approved || !_isOwnerActive(space.ownerId)) {
      return false;
    }
    if (favoritesOnly &&
        !(_store.currentUser?.favorites.contains(space.id) ?? false)) {
      return false;
    }
    return _matchesAttributes(space, category, query, maxPrice, minCapacity);
  }

  bool _matchesAttributes(
    Space space,
    String category,
    String query,
    int? maxPrice,
    int? minCapacity,
  ) {
    final searchable =
        '${space.name} ${space.location} ${space.amenities.join(' ')}'
            .toLowerCase();
    return (category == 'ทั้งหมด' || space.category == category) &&
        (maxPrice == null || space.price <= maxPrice) &&
        (minCapacity == null || space.capacity >= minCapacity) &&
        searchable.contains(query.trim().toLowerCase());
  }

  void _sortSpaces(List<Space> list, SpaceSort sort) {
    switch (sort) {
      case SpaceSort.recommended:
        return;
      case SpaceSort.priceAsc:
        list.sort((a, b) => a.price.compareTo(b.price));
      case SpaceSort.priceDesc:
        list.sort((a, b) => b.price.compareTo(a.price));
      case SpaceSort.capacityDesc:
        list.sort((a, b) => b.capacity.compareTo(a.capacity));
    }
  }

  List<SpaceReview> reviewsFor(String spaceId) =>
      _store.publicReviews[spaceId] ?? const [];

  int reviewCountFor(String spaceId) {
    final reviews = reviewsFor(spaceId);
    if (reviews.isNotEmpty) return reviews.length;
    for (final space in _store.spaces) {
      if (space.id == spaceId) return space.dbReviewCount;
    }
    return 0;
  }

  double? averageRating(String spaceId) {
    final reviews = reviewsFor(spaceId);
    if (reviews.isNotEmpty) {
      final sum = reviews.fold<int>(0, (total, r) => total + r.rating);
      return sum / reviews.length;
    }
    for (final space in _store.spaces) {
      if (space.id == spaceId && space.dbReviewCount > 0) {
        return space.dbRating;
      }
    }
    return null;
  }
}
