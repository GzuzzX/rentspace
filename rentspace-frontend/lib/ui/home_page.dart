import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/auth_controller.dart';
import '../controllers/booking_controller.dart';
import '../controllers/payment_controller.dart';
import '../controllers/space_controller.dart';
import '../data/app_store.dart';
import '../models/domain.dart';
import 'booking_pages.dart';
import 'common.dart';
import 'space_form.dart';

String _initial(String name) =>
    name.trim().isEmpty ? '?' : name.trim().substring(0, 1);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.store,
    this.authController,
    this.spaceController,
    this.bookingController,
    this.paymentController,
  });
  final AppStore store;
  final AuthController? authController;
  final SpaceController? spaceController;
  final BookingController? bookingController;
  final PaymentController? paymentController;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppStore get store => widget.store;
  AppUser get user => store.currentUser!;
  AuthController get _authCtrl => widget.authController ?? AuthController(store);
  SpaceController get _spaceCtrl => widget.spaceController ?? SpaceController(store);
  BookingController get _bookingCtrl => widget.bookingController ?? BookingController(store);
  PaymentController get _paymentCtrl => widget.paymentController ?? PaymentController(store);
  final searchController = TextEditingController();
  final userSearchController = TextEditingController();
  int index = 0,
      bookingTab = 0,
      adminTab = 0,
      allSpacesFilter = 0,
      renterBookingTab = 0;
  String query = '', category = 'ทั้งหมด', userQuery = '';
  SpaceSort sort = SpaceSort.recommended;
  int? maxPriceFilter;
  int? minCapacityFilter;
  UserRole? userRoleFilter;
  BookingStatus? filter;
  bool pendingPayoutOnly = false;
  late DateTime calendarDate = dateOnly(store.clock());
  Timer? _pollTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(store.poll());
      }
    });
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        unawaited(store.poll());
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    searchController.dispose();
    userSearchController.dispose();
    super.dispose();
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  void bookingDetail(Booking b) => open(
    BookingPage(
      store: store,
      bookingId: b.id,
      bookingController: widget.bookingController,
      paymentController: widget.paymentController,
      spaceController: widget.spaceController,
    ),
  );
  void select(int v, {BookingStatus? status, bool pendingPayout = false}) {
    setState(() {
      index = v;
      filter = status;
      pendingPayoutOnly = pendingPayout;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (store.currentUser == null) return const SizedBox.shrink();
    final role = user.role;
    final labels = switch (role) {
      UserRole.renter => ['ค้นหา', 'การจอง', 'รายการโปรด', 'โปรไฟล์'],
      UserRole.owner => ['ภาพรวม', 'พื้นที่', 'การจอง', 'รายรับ', 'โปรไฟล์'],
      UserRole.admin => ['ภาพรวม', 'ตรวจสอบ', 'การเงิน', 'ผู้ใช้', 'โปรไฟล์'],
    };
    final icons = switch (role) {
      UserRole.renter => [
        Icons.search,
        Icons.event_note,
        Icons.favorite_border,
        Icons.person_outline,
      ],
      UserRole.owner => [
        Icons.dashboard_outlined,
        Icons.home_work_outlined,
        Icons.event_available,
        Icons.account_balance_wallet_outlined,
        Icons.person_outline,
      ],
      UserRole.admin => [
        Icons.dashboard_outlined,
        Icons.rule_folder_outlined,
        Icons.payments_outlined,
        Icons.people_outline,
        Icons.person_outline,
      ],
    };
    final body = switch (role) {
      UserRole.renter => switch (index) {
        0 => browse(false),
        1 => bookingList(),
        2 => browse(true),
        _ => ProfilePanel(
          store: store,
          authController: widget.authController,
        ),
      },
      UserRole.owner => switch (index) {
        0 => dashboard(),
        1 => spaces(),
        2 => ownerReservations(),
        3 => payouts(),
        _ => ProfilePanel(
          store: store,
          authController: widget.authController,
        ),
      },
      UserRole.admin => switch (index) {
        0 => dashboard(),
        1 => moderation(),
        2 => finance(),
        3 => users(),
        _ => ProfilePanel(
          store: store,
          authController: widget.authController,
        ),
      },
    };
    final badges = store.navBadges();
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) select(0);
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Column(
            children: [
              _MobileTopBar(
                store: store,
                user: user,
                onHomeTap: () => select(0),
                onProfileTap: () => select(labels.length - 1),
                onLogout: () => _authCtrl.logoutAsync(),
              ),
              if (store.syncError != null)
                MaterialBanner(
                  content: Text(store.syncError!),
                  actions: [
                    TextButton(
                      onPressed: () => perform(context, store.refresh),
                      child: const Text('ลองใหม่'),
                    ),
                  ],
                ),
              Expanded(child: body),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: select,
          destinations: List.generate(
            labels.length,
            (i) => NavigationDestination(
              icon: i < badges.length && badges[i] > 0
                  ? Badge.count(count: badges[i], child: Icon(icons[i]))
                  : Icon(icons[i]),
              label: labels[i],
            ),
          ),
        ),
      ),
    );
  }

  int get _activeFilterCount =>
      (category != 'ทั้งหมด' ? 1 : 0) +
      (sort != SpaceSort.recommended ? 1 : 0) +
      (maxPriceFilter != null ? 1 : 0) +
      (minCapacityFilter != null ? 1 : 0);

  void _openFilterSheet(Set<String> categories) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final theme = Theme.of(ctx);
          void update(VoidCallback fn) {
            setState(fn);
            setSheetState(() {});
          }

          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'ตัวกรองและเรียงลำดับ',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        onPressed: () => update(() {
                          category = 'ทั้งหมด';
                          sort = SpaceSort.recommended;
                          maxPriceFilter = null;
                          minCapacityFilter = null;
                        }),
                        child: const Text('ล้างค่าทั้งหมด'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('หมวดหมู่พื้นที่', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: categories
                        .map(
                          (c) => ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) => update(() => category = c),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  Text('เรียงลำดับตาม', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in SpaceSort.values)
                        ChoiceChip(
                          key: ValueKey('sort-${option.name}'),
                          label: Text(option.label),
                          selected: sort == option,
                          onSelected: (_) => update(() => sort = option),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('งบประมาณต่อชั่วโมง', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, priceCap) in [
                        ('ทุกราคา', null),
                        ('ไม่เกิน ฿300', 300),
                        ('ไม่เกิน ฿600', 600),
                        ('ไม่เกิน ฿1,000', 1000),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: maxPriceFilter == priceCap,
                          onSelected: (_) =>
                              update(() => maxPriceFilter = priceCap),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text('ความจุขั้นต่ำ', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (label, cap) in [
                        ('ทุกความจุ', null),
                        ('4+ คน', 4),
                        ('8+ คน', 8),
                        ('12+ คน', 12),
                      ])
                        ChoiceChip(
                          label: Text(label),
                          selected: minCapacityFilter == cap,
                          onSelected: (_) =>
                              update(() => minCapacityFilter = cap),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ดูผลลัพธ์'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget browse(bool favorites) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final categories = {
      'ทั้งหมด',
      ...store.spaces
          .where(
            (s) =>
                s.status == SpaceStatus.approved &&
                (store.maybeUser(s.ownerId)?.active ?? false),
          )
          .map((s) => s.category),
    };
    final list = _spaceCtrl.filterSpaces(
      favoritesOnly: favorites,
      category: category,
      query: query,
      sort: sort,
      maxPrice: maxPriceFilter,
      minCapacity: minCapacityFilter,
    );
    final filterCount = _activeFilterCount;
    return PageBody(
      children: [
        if (favorites)
          heading('รายการโปรด', 'พื้นที่ที่คุณกดหัวใจไว้')
        else
          Container(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'หาพื้นที่ให้ตรงงาน',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'เลือกพื้นที่และช่วงเวลาที่เหมาะกับคุณ',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        SurfaceCard(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: (v) => setState(() => query = v),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: 'ค้นหาชื่อ / ที่อยู่ / สิ่งอำนวยความสะดวก',
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'ล้างคำค้นหา',
                                onPressed: () async {
                                  searchController.clear();
                                  setState(() => query = '');
                                },
                                icon: const Icon(Icons.close, size: 18),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    key: const ValueKey('open-filter-btn'),
                    onPressed: () => _openFilterSheet(categories),
                    icon: const Icon(Icons.tune, size: 18),
                    label: Text(
                      filterCount > 0 ? 'ตัวกรอง ($filterCount)' : 'ตัวกรอง',
                    ),
                  ),
                ],
              ),
              if (filterCount > 0) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (category != 'ทั้งหมด')
                      StatusBadge(category, tone: BadgeTone.primary),
                    if (sort != SpaceSort.recommended)
                      StatusBadge(sort.label, tone: BadgeTone.info),
                    if (maxPriceFilter != null)
                      StatusBadge(
                        '≤ ${bahtLabel(maxPriceFilter!)}/ชม.',
                        tone: BadgeTone.success,
                      ),
                    if (minCapacityFilter != null)
                      StatusBadge(
                        '≥ $minCapacityFilter คน',
                        tone: BadgeTone.warning,
                      ),
                    TextButton(
                      onPressed: () => setState(() {
                        category = 'ทั้งหมด';
                        sort = SpaceSort.recommended;
                        maxPriceFilter = null;
                        minCapacityFilter = null;
                      }),
                      child: const Text('ล้างตัวกรอง'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              favorites
                  ? 'รายการโปรด (${list.length} รายการ)'
                  : 'พบ ${list.length} พื้นที่ที่ตรงกับเงื่อนไข',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        if (list.isEmpty)
          empty(
            favorites
                ? 'ยังไม่มีรายการโปรดที่ตรงกับตัวกรอง'
                : 'ไม่พบพื้นที่ ลองเปลี่ยนคำค้นหาหรือประเภท',
          ),
        for (final s in list)
          SurfaceCard(
            padding: EdgeInsets.zero,
            onTap: () => open(
              ReservePage(
                store: store,
                space: s,
                bookingController: widget.bookingController,
                paymentController: widget.paymentController,
                spaceController: widget.spaceController,
                authController: widget.authController,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (s.hasImage)
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    child: SpaceImage(
                      s,
                      height: 180,
                      width: double.infinity,
                      showLoading: true,
                      fallback: const SizedBox(
                        height: 120,
                        child: Center(
                          child: Icon(Icons.home_work_outlined, size: 56),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.name,
                              style: theme.textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'รายการโปรด',
                            onPressed: () => perform(
                              context,
                              () => _spaceCtrl.favoriteAsync(s.id),
                            ),
                            icon: Icon(
                              user.favorites.contains(s.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: scheme.primary,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${s.category} • ${s.location} • รองรับ ${s.capacity} คน',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Builder(
                        builder: (context) {
                          final todayHours =
                              s.availability.days[store.clock().weekday - 1];
                          return Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${bahtLabel(s.price)}/ชม.',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: scheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              if (_spaceCtrl.averageRating(s.id)
                                  case final avg?)
                                Text(
                                  '★ ${avg.toStringAsFixed(1)} (${_spaceCtrl.reviewCountFor(s.id)} รีวิว)',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: toneColor(
                                      context,
                                      BadgeTone.warning,
                                    ),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              Text(
                                todayHours.open
                                    ? '•  เปิดวันนี้ ${timeLabel(todayHours.start)}–${timeLabel(todayHours.end)}'
                                    : '•  ปิดทำการวันนี้',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: todayHours.open
                                      ? toneColor(context, BadgeTone.success)
                                      : theme.colorScheme.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        s.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton(
                          onPressed: () => open(
                            ReservePage(
                              store: store,
                              space: s,
                              bookingController: widget.bookingController,
                              paymentController: widget.paymentController,
                              spaceController: widget.spaceController,
                              authController: widget.authController,
                            ),
                          ),
                          child: const Text('ดูรายละเอียดและจอง'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget bookingCard(Booking b) {
    final theme = Theme.of(context);
    final tone = bookingTone(b.status);
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: () => bookingDetail(b),
      child: Row(
        children: [
          IconBox(Icons.event_note_outlined, tone: tone, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.spaceName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    StatusBadge(b.status.label, tone: tone),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${bookingWhen(b)} • ${b.attendees} ท่าน',
                  style: theme.textTheme.bodySmall,
                ),
                if (user.role != UserRole.renter)
                  Text(
                    'ผู้เช่า: ${store.user(b.renterId).name}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (b.renterNote.isNotEmpty)
                  Text(
                    '“${b.renterNote}”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.colorScheme.onSurface.withValues(
                        alpha: 0.75,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  bahtLabel(b.rentAmount),
                  style: theme.textTheme.labelLarge,
                ),
                if (b.deadlineHint(store.clock()) case final hint?) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: toneColor(
                        context,
                        b.status == BookingStatus.slipRejected
                            ? BadgeTone.danger
                            : BadgeTone.warning,
                      ),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            size: 18,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ],
      ),
    );
  }

  void _openQuickSlipDialog(Booking b) {
    final theme = Theme.of(context);
    final slip = b.latestSlip;
    final renter = store.user(b.renterId);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('ตรวจสลิปด่วน (#${b.id})'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'พื้นที่: ${b.spaceName}',
                  style: theme.textTheme.titleSmall,
                ),
                Text(
                  'ผู้เช่า: ${renter.name} (${renter.phoneLabel})',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 6),
                Text(
                  'ยอดเงินที่ต้องได้รับ: ${bahtLabel(b.rentAmount)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                if (slip != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SlipImage(
                      slip,
                      height: 240,
                      width: double.infinity,
                      headers: store.api.token?.isNotEmpty == true
                          ? {'Authorization': 'Bearer ${store.api.token}'}
                          : null,
                      fallback: Container(
                        height: 120,
                        color: Colors.grey.shade200,
                        alignment: Alignment.center,
                        child: const Text('ไม่สามารถแสดงภาพสลิปได้'),
                      ),
                    ),
                  ),
                  if (slip.note.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'บันทึกจากผู้เช่า: ${slip.note}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ] else
                  Container(
                    height: 100,
                    color: Colors.grey.shade200,
                    alignment: Alignment.center,
                    child: const Text('ไม่มีข้อมูลสลิป'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ปิด'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              final r = await askReason(context, 'ระบุเหตุผลที่ปฏิเสธสลิป');
              if (r != null && mounted) {
                perform(
                  context,
                  () => _paymentCtrl.reviewAsync(b.id, false, r),
                  'ปฏิเสธสลิปแล้ว',
                );
              }
            },
            child: const Text('ปฏิเสธสลิป'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              perform(
                context,
                () => _paymentCtrl.reviewAsync(b.id, true, ''),
                'อนุมัติสลิปและยืนยันการจองเรียบร้อย',
              );
            },
            child: const Text('อนุมัติสลิป'),
          ),
        ],
      ),
    );
  }

  void _handleQuickPayout(Booking b) =>
      showAdminPayoutDialog(
        context,
        store: store,
        booking: b,
        paymentController: widget.paymentController,
      );

  Widget _adminFinanceCard(Booking b) {
    final theme = Theme.of(context);
    final tone = bookingTone(b.status);
    final owner = store.user(b.ownerId);
    final renter = store.user(b.renterId);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: () => bookingDetail(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.spaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(b.status.label, tone: tone),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bahtLabel(b.rentAmount),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'ค่าบริการ: ${bahtLabel(b.platformFee)}',
                    style: theme.textTheme.labelSmall,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${bookingWhen(b)} • ผู้เช่า: ${renter.name} (${renter.phoneLabel})',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Flexible(
                child: Text(
                  'เจ้าของ: ${owner.name} • บัญชี: ${owner.bankInfo.isEmpty ? "-" : owner.bankInfo}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (owner.bankInfo.isNotEmpty) ...[
                const SizedBox(width: 4),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () async {
                    Clipboard.setData(ClipboardData(text: owner.bankInfo));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('คัดลอกบัญชี ${owner.bankInfo} แล้ว'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Icon(
                      Icons.copy_outlined,
                      size: 13,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (b.status == BookingStatus.completed && b.paidOutAt != null) ...[
            const SizedBox(height: 4),
            Text(
              b.payoutSlip != null
                  ? 'โอนเงินให้เจ้าของแล้ว (${dateLabel(b.paidOutAt!)}) • มีสลิปแนบ'
                  : 'โอนเงินให้เจ้าของแล้ว (${dateLabel(b.paidOutAt!)})',
              style: TextStyle(
                fontSize: 12,
                color: toneColor(context, BadgeTone.success),
              ),
            ),
          ],
          if (b.status == BookingStatus.slipReview ||
              (b.status == BookingStatus.completed && b.paidOutAt == null)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (b.status == BookingStatus.slipReview)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _openQuickSlipDialog(b),
                      icon: const Icon(Icons.receipt_long, size: 16),
                      label: const Text('ตรวจสลิปด่วน'),
                    ),
                  ),
                if (b.status == BookingStatus.completed && b.paidOutAt == null)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _handleQuickPayout(b),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: Text('โอนให้เจ้าของ (${bahtLabel(b.ownerNet)})'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _ownerBookingCard(Booking b) {
    final theme = Theme.of(context);
    final tone = bookingTone(b.status);
    final renter = store.user(b.renterId);
    final canComplete = !store.clock().isBefore(b.endsAt);

    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      onTap: () => bookingDetail(b),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.spaceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    StatusBadge(b.status.label, tone: tone),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bahtLabel(b.ownerNet),
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text('สุทธิรับ', style: theme.textTheme.labelSmall),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${bookingWhen(b)}${b.days > 1 ? ' (${b.days} วัน)' : ''} • โซน: ${b.zone}',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 2),
          Text(
            '${renter.name} (${b.attendees} ท่าน) • โทร ${renter.phoneLabel}',
            style: theme.textTheme.bodySmall,
          ),
          if (b.renterNote.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '“${b.renterNote}”',
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
          if (b.status == BookingStatus.ownerReview &&
              b.ownerResponseDeadline != null) ...[
            const SizedBox(height: 4),
            Text(
              'ตอบรับภายใน: ${dateTimeLabel(b.ownerResponseDeadline!)}',
              style: TextStyle(
                fontSize: 11,
                color: toneColor(context, BadgeTone.warning),
              ),
            ),
          ],
          if (b.status == BookingStatus.confirmed) ...[
            const SizedBox(height: 4),
            Text(
              canComplete
                  ? 'ลูกค้าใช้งานเสร็จสิ้นแล้ว สามารถกดยืนยันจบงานได้'
                  : 'ยืนยันจบงานได้หลังเวลา: ${dateTimeLabel(b.endsAt)}',
              style: TextStyle(
                fontSize: 11,
                color: canComplete
                    ? toneColor(context, BadgeTone.success)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          if (b.status == BookingStatus.ownerReview ||
              (b.status == BookingStatus.confirmed && canComplete)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (b.status == BookingStatus.ownerReview) ...[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => perform(
                        context,
                        () => _bookingCtrl.ownerReviewAsync(b.id, true, ''),
                        'อนุมัติคำขอจองแล้ว',
                      ),
                      icon: const Icon(Icons.check, size: 16),
                      label: const Text('อนุมัติคำขอ'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final r = await askReason(
                          context,
                          'ระบุเหตุผลที่ปฏิเสธคำขอ',
                        );
                        if (r != null && mounted) {
                          perform(
                            context,
                            () => _bookingCtrl.ownerReviewAsync(b.id, false, r),
                            'ปฏิเสธคำขอจองแล้ว',
                          );
                        }
                      },
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('ปฏิเสธคำขอ'),
                    ),
                  ),
                ],
                if (b.status == BookingStatus.confirmed && canComplete)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => perform(
                        context,
                        () => _bookingCtrl.completeAsync(b.id),
                        'ทำเครื่องหมายว่าใช้บริการแล้ว',
                      ),
                      icon: const Icon(Icons.task_alt, size: 16),
                      label: const Text('ยืนยันจบงาน (ใช้บริการแล้ว)'),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget bookingList() {
    final all = store.visibleBookings();
    final actionRequired = all
        .where(
          (b) =>
              b.status == BookingStatus.paymentDue ||
              b.status == BookingStatus.slipRejected,
        )
        .toList();
    final historyStatuses = [
      BookingStatus.completed,
      BookingStatus.canceled,
      BookingStatus.ownerRejected,
    ];
    final active = all
        .where((b) => !historyStatuses.contains(b.status))
        .toList();
    final history = all
        .where((b) => historyStatuses.contains(b.status))
        .toList();

    final tabFiltered = switch (renterBookingTab) {
      1 => history,
      2 => all,
      _ => active,
    };
    final list = tabFiltered
        .where((b) => filter == null || b.status == filter)
        .toList();
    final theme = Theme.of(context);
    return PageBody(
      children: [
        heading('การจองของฉัน', 'ติดตามสถานะคำขอ สลิป และประวัติการใช้งาน'),
        if (actionRequired.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: theme.colorScheme.error,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'มี ${actionRequired.length} รายการรอคุณชำระเงินหรือแนบสลิปใหม่',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => bookingDetail(actionRequired.first),
                  child: const Text('ดำเนินการ'),
                ),
              ],
            ),
          ),
        TabStrip(
          labels: [
            'กำลังดำเนินการ (${active.length})',
            'ประวัติ (${history.length})',
            'ทั้งหมด (${all.length})',
          ],
          selected: renterBookingTab,
          margin: const EdgeInsets.only(bottom: 12),
          onChanged: (v) => setState(() => renterBookingTab = v),
        ),
        statusFilter(),
        if (list.isEmpty) empty('ไม่มีรายการจองในสถานะนี้'),
        ...list.map(bookingCard),
      ],
    );
  }

  Widget statusFilter() {
    void openStatusSheet() {
      showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'กรองตามสถานะการจอง',
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('ทั้งหมด'),
                      selected: filter == null,
                      onSelected: (_) {
                        setState(() => filter = null);
                        Navigator.pop(ctx);
                      },
                    ),
                    for (final s in BookingStatus.values)
                      ChoiceChip(
                        label: Text(s.label),
                        selected: filter == s,
                        onSelected: (_) {
                          setState(() => filter = s);
                          Navigator.pop(ctx);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('booking-status-filter-btn'),
            onPressed: openStatusSheet,
            icon: const Icon(Icons.filter_list, size: 18),
            label: Text(
              filter == null ? 'ตัวกรองสถานะ' : 'สถานะ: ${filter!.label}',
            ),
          ),
          if (filter != null)
            TextButton(
              onPressed: () => setState(() => filter = null),
              child: const Text('ล้าง'),
            ),
        ],
      ),
    );
  }

  List<(String, String, IconData, BadgeTone, VoidCallback)> _dashboardStats(
    List<Booking> bookings,
    List<Space> mine,
    bool isOwner,
  ) {
    final completedRevenue = bahtLabel(
      bookings
          .where((b) => b.status == BookingStatus.completed)
          .fold<int>(0, (sum, b) => sum + b.ownerNet),
    );
    return [
      (
        'พื้นที่',
        '${mine.length}',
        Icons.home_work_outlined,
        BadgeTone.primary,
        () {
          if (!isOwner) {
            setState(() {
              adminTab = 2;
              allSpacesFilter = 0;
            });
          }
          select(1);
        },
      ),
      (
        'คำขอรออนุมัติ',
        '${bookings.where((b) => b.status == BookingStatus.ownerReview).length}',
        Icons.pending_actions_outlined,
        BadgeTone.warning,
        () {
          if (isOwner) setState(() => bookingTab = 0);
          select(2, status: BookingStatus.ownerReview);
        },
      ),
      isOwner
          ? (
              'คิวจองที่ยืนยันแล้ว',
              '${bookings.where((b) => b.status == BookingStatus.confirmed).length}',
              Icons.event_available,
              BadgeTone.info,
              () {
                setState(() => bookingTab = 0);
                select(2, status: BookingStatus.confirmed);
              },
            )
          : (
              'สลิปรอตรวจ',
              '${bookings.where((b) => b.status == BookingStatus.slipReview).length}',
              Icons.receipt_long_outlined,
              BadgeTone.info,
              () => select(2, status: BookingStatus.slipReview),
            ),
      (
        'รายรับสุทธิที่เสร็จสิ้น',
        completedRevenue,
        Icons.account_balance_wallet_outlined,
        BadgeTone.success,
        () => isOwner
            ? select(3)
            : select(2, status: BookingStatus.completed),
      ),
    ];
  }

  Widget _ownerUrgentBanner(
    int pendingRequests,
    int readyToComplete,
    bool missingBank,
  ) {
    final total =
        pendingRequests + readyToComplete + (missingBank ? 1 : 0);
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.notifications_active_outlined,
                color: scheme.error,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'แจ้งเตือนผู้ให้เช่า ($total รายการ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (pendingRequests > 0)
                ActionChip(
                  avatar: const Icon(Icons.pending_actions_outlined, size: 14),
                  label: Text('คำขอรออนุมัติ ($pendingRequests)'),
                  onPressed: () {
                    setState(() => bookingTab = 0);
                    select(2, status: BookingStatus.ownerReview);
                  },
                ),
              if (readyToComplete > 0)
                ActionChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 14),
                  label: Text('รอกดยืนยันจบงาน ($readyToComplete)'),
                  onPressed: () {
                    setState(() => bookingTab = 0);
                    select(2, status: BookingStatus.confirmed);
                  },
                ),
              if (missingBank)
                ActionChip(
                  avatar: const Icon(Icons.account_balance_outlined, size: 14),
                  label: const Text('ยังไม่ได้ระบุบัญชีรับเงิน'),
                  onPressed: () => select(4),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _adminUrgentBanner(
    int pendingSpaces,
    int slipReviews,
    int openIssues,
    int readyPayouts,
  ) {
    final total = pendingSpaces + slipReviews + openIssues + readyPayouts;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.error, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'งานด่วนที่ต้องดำเนินการ ($total รายการ)',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (slipReviews > 0)
                ActionChip(
                  avatar: const Icon(Icons.receipt_long, size: 14),
                  label: Text('สลิปรอตรวจ ($slipReviews)'),
                  onPressed: () => select(2, status: BookingStatus.slipReview),
                ),
              if (pendingSpaces > 0)
                ActionChip(
                  avatar: const Icon(Icons.rule_folder_outlined, size: 14),
                  label: Text('ประกาศรอตรวจ ($pendingSpaces)'),
                  onPressed: () {
                    setState(() => adminTab = 0);
                    select(1);
                  },
                ),
              if (openIssues > 0)
                ActionChip(
                  avatar: const Icon(Icons.report_problem_outlined, size: 14),
                  label: Text('รายงานปัญหา ($openIssues)'),
                  onPressed: () {
                    setState(() => adminTab = 1);
                    select(1);
                  },
                ),
              if (readyPayouts > 0)
                ActionChip(
                  avatar: const Icon(Icons.payments_outlined, size: 14),
                  label: Text('รอโอนให้เจ้าของ ($readyPayouts)'),
                  onPressed: () => select(
                    2,
                    status: BookingStatus.completed,
                    pendingPayout: true,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget dashboard() {
    final bookings = store.visibleBookings();
    final isOwner = user.role == UserRole.owner;
    final mine = store.spaces
        .where((s) => !isOwner || s.ownerId == user.id)
        .toList();
    final pendingSpaces = store.spaces
        .where((s) => s.status == SpaceStatus.pending)
        .length;
    final slipReviews = bookings
        .where((b) => b.status == BookingStatus.slipReview)
        .length;
    final openIssues = store.issues.where((i) => !i.closed).length;
    final readyPayouts = bookings
        .where(
          (b) => b.status == BookingStatus.completed && b.paidOutAt == null,
        )
        .length;
    final ownerPendingRequests = bookings
        .where((b) => b.status == BookingStatus.ownerReview)
        .length;
    final ownerReadyToComplete = bookings
        .where(
          (b) =>
              b.status == BookingStatus.confirmed &&
              !store.clock().isBefore(b.endsAt),
        )
        .length;
    final ownerMissingBank = isOwner && user.bankInfo.trim().isEmpty;
    final stats = _dashboardStats(bookings, mine, isOwner);
    return PageBody(
      children: [
        heading(
          'ภาพรวม',
          'สวัสดี ${user.name} • แตะการ์ดเพื่อเข้าสู่หมวดหมู่ได้ทันที',
        ),
        if (isOwner &&
            (ownerPendingRequests > 0 ||
                ownerReadyToComplete > 0 ||
                ownerMissingBank))
          _ownerUrgentBanner(
            ownerPendingRequests,
            ownerReadyToComplete,
            ownerMissingBank,
          ),
        if (!isOwner &&
            (pendingSpaces + slipReviews + openIssues + readyPayouts) > 0)
          _adminUrgentBanner(
            pendingSpaces,
            slipReviews,
            openIssues,
            readyPayouts,
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth < 400
                ? (constraints.maxWidth - 12) / 2
                : 230.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, value, icon, tone, onTap) in stats)
                  SizedBox(
                    width: tileWidth,
                    child: StatTile(
                      label: label,
                      value: value,
                      icon: icon,
                      tone: tone,
                      onTap: onTap,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        const SectionHeader('การจองล่าสุด'),
        if (bookings.isEmpty) empty('ยังไม่มีการจอง'),
        ...bookings.take(5).map(bookingCard),
        if (!isOwner) ...[
          const SizedBox(height: 20),
          const SectionHeader('ประวัติการดำเนินการล่าสุด'),
          if (store.logs.isEmpty) empty('ยังไม่มีประวัติการดำเนินการ'),
          ...store.logs.take(10).map(_adminAuditLogCard),
        ],
      ],
    );
  }

  Widget _adminAuditLogCard(AuditEntry entry) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: scheme.primary.withValues(alpha: 0.12),
            child: Icon(
              Icons.history_outlined,
              size: 16,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.action, style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'โดย ${entry.actor} • ${dateTimeLabel(entry.at)}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget spaces() {
    final theme = Theme.of(context);
    final mine = store.spaces.where((s) => s.ownerId == user.id).toList();
    return PageBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: heading(
                'พื้นที่ของฉัน',
                'ประกาศที่อนุมัติแล้วจะแสดงให้ผู้เช่าเห็น',
              ),
            ),
            FilledButton.icon(
              onPressed: () => open(
                SpaceForm(store: store, spaceController: widget.spaceController),
              ),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('เพิ่มพื้นที่'),
            ),
          ],
        ),
        if (mine.isEmpty) empty('ยังไม่มีพื้นที่ เริ่มเพิ่มประกาศแรกได้เลย'),
        for (final s in mine)
          Builder(
            builder: (context) {
              final activeQueue = store.bookings
                  .where((b) => b.spaceId == s.id && b.status.holdsTime)
                  .length;
              final spaceNet = store.bookings
                  .where(
                    (b) =>
                        b.spaceId == s.id &&
                        b.status == BookingStatus.completed,
                  )
                  .fold<int>(0, (sum, b) => sum + b.ownerNet);
              final avgRating = _spaceCtrl.averageRating(s.id);
              final reviewCount = _spaceCtrl.reviewCountFor(s.id);

              return SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            s.name,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        StatusBadge(s.status.label, tone: spaceTone(s.status)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${s.category} • ${s.location} • ${bahtLabel(s.price)}/ชม. • ${s.capacity} คน',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${avgRating != null ? '★ ${avgRating.toStringAsFixed(1)} ($reviewCount รีวิว) • ' : ''}คิวจอง $activeQueue รายการ${spaceNet > 0 ? ' • รายได้สะสม ${bahtLabel(spaceNet)}' : ''}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (s.reviewReason.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: toneColor(
                            context,
                            BadgeTone.danger,
                          ).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'เหตุผล: ${s.reviewReason}',
                          style: TextStyle(
                            fontSize: 12,
                            color: toneColor(context, BadgeTone.danger),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: () => open(
                            SpaceForm(
                              store: store,
                              space: s,
                              spaceController: widget.spaceController,
                            ),
                          ),
                          child: const Text('แก้ไข'),
                        ),
                        OutlinedButton(
                          onPressed: () => open(
                            AvailabilityPage(
                              store: store,
                              space: s,
                              spaceController: widget.spaceController,
                            ),
                          ),
                          child: const Text('ตั้งเวลาว่าง / วันปิด'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }

  Widget ownerReservations() {
    final all = store.visibleBookings();
    final history = [
      BookingStatus.completed,
      BookingStatus.canceled,
      BookingStatus.ownerRejected,
    ];
    final list =
        all
            .where(
              (b) =>
                  (bookingTab == 2
                      ? history.contains(b.status)
                      : bookingTab == 1
                      ? b.coversDate(calendarDate) && !history.contains(b.status)
                      : !history.contains(b.status)) &&
                  (filter == null || b.status == filter),
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    return PageBody(
      children: [
        heading('การจองพื้นที่', 'ติดตามคำขอ ปฏิทิน และประวัติการใช้งาน'),
        TabStrip(
          labels: const ['คำขอ / กำลังดำเนินการ', 'ปฏิทิน', 'ประวัติ'],
          selected: bookingTab,
          onChanged: (v) => setState(() {
            bookingTab = v;
            filter = null;
          }),
        ),
        statusFilter(),
        if (bookingTab == 1)
          SurfaceCard(
            child: Column(
              children: [
                CalendarDatePicker(
                  initialDate: calendarDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  onDateChanged: (d) =>
                      setState(() => calendarDate = dateOnly(d)),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'รายการวันที่ ${dateLabel(calendarDate)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        if (list.isEmpty) empty('ไม่มีรายการในช่วง / หมวดนี้'),
        ...list.map(_ownerBookingCard),
      ],
    );
  }

  Widget payouts() {
    final all = store.visibleBookings(),
        completed = all
            .where((b) => b.status == BookingStatus.completed)
            .toList();
    final held = all
        .where((b) => b.status == BookingStatus.confirmed)
        .fold<int>(0, (sum, b) => sum + b.ownerNet);
    final pending = completed
        .where((b) => b.paidOutAt == null)
        .fold<int>(0, (sum, b) => sum + b.ownerNet);
    final paid = completed
        .where((b) => b.paidOutAt != null)
        .fold<int>(0, (sum, b) => sum + b.ownerNet);
    final theme = Theme.of(context);
    return PageBody(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: heading(
                'รายรับและการจ่าย',
                'หักค่าบริการ 5% • คำนวณจากรายการจองในระบบ',
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.copy_outlined, size: 15),
              label: const Text('คัดลอกสรุปรายรับ'),
              onPressed: () async {
                final todayStr = dateLabel(DateTime.now());
                final summary =
                    '[รายงานรายรับ RentSpace สำหรับผู้ให้เช่า]\n'
                    'วันที่: $todayStr\n'
                    'เจ้าของพื้นที่: ${user.name}\n'
                    'บัญชีรับเงิน: ${user.bankInfo.isEmpty ? "ยังไม่ระบุ" : user.bankInfo}\n'
                    '• รอใช้บริการ (สุทธิ): ${bahtLabel(held)}\n'
                    '• พร้อมจ่าย รอ Admin โอน (สุทธิ): ${bahtLabel(pending)}\n'
                    '• จ่ายแล้ว (สุทธิ): ${bahtLabel(paid)}\n'
                    '• รายการเสร็จสิ้นทั้งหมด: ${completed.length} รายการ';
                Clipboard.setData(ClipboardData(text: summary));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('คัดลอกสรุปรายรับลง Clipboard แล้ว'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth < 400
                ? (constraints.maxWidth - 12) / 2
                : 230.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'รอใช้บริการ (สุทธิ)',
                    value: bahtLabel(held),
                    icon: Icons.hourglass_empty,
                    tone: BadgeTone.warning,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'พร้อมจ่าย (สุทธิ)',
                    value: bahtLabel(pending),
                    icon: Icons.payments_outlined,
                    tone: BadgeTone.primary,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'จ่ายแล้ว (สุทธิ)',
                    value: bahtLabel(paid),
                    icon: Icons.check_circle_outline,
                    tone: BadgeTone.success,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        if (user.role == UserRole.owner)
          SurfaceCard(
            title: 'บัญชีรับเงินโอน',
            subtitle: user.bankInfo.isEmpty
                ? 'ยังไม่ได้ระบุบัญชีรับเงินในหน้าโปรไฟล์'
                : user.bankInfo,
            action: TextButton.icon(
              onPressed: () => select(4),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('แก้ไขบัญชี'),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'ข้อมูลบัญชีนี้จะแสดงให้ Admin เห็นเพื่อบันทึกจ่ายเงินสุทธิหลังจบงาน',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (user.bankInfo.isNotEmpty)
                  IconButton(
                    tooltip: 'คัดลอกเลขบัญชี',
                    onPressed: () async {
                      Clipboard.setData(ClipboardData(text: user.bankInfo));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('คัดลอกบัญชี ${user.bankInfo} แล้ว'),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icon(
                      Icons.copy_outlined,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  ),
              ],
            ),
          ),
        const SectionHeader('รายการที่เสร็จสิ้น'),
        if (completed.isEmpty) empty('ยังไม่มีรายการใช้บริการเสร็จสิ้น'),
        for (final b in completed)
          SurfaceCard(
            onTap: () => bookingDetail(b),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        b.spaceName,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    StatusBadge(
                      b.paidOutAt == null ? 'รอ Admin บันทึกจ่าย' : 'จ่ายแล้ว',
                      tone: b.paidOutAt == null
                          ? BadgeTone.warning
                          : BadgeTone.success,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(bookingWhen(b), style: theme.textTheme.bodySmall),
                const SizedBox(height: 6),
                Text(
                  'ค่าเช่า ${bahtLabel(b.rentAmount)} − ค่าบริการ ${bahtLabel(b.platformFee)} = ${bahtLabel(b.ownerNet)}',
                  style: theme.textTheme.labelLarge,
                ),
                if (b.payoutSlip != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'มีสลิปการโอน • แตะเพื่อดูสลิป',
                    style: TextStyle(
                      fontSize: 12,
                      color: toneColor(context, BadgeTone.success),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget moderation() {
    final theme = Theme.of(context);
    final pending = store.spaces
        .where((s) => s.status == SpaceStatus.pending)
        .toList();
    final openIssues = store.issues.where((i) => !i.closed).length;
    return PageBody(
      children: [
        heading('ตรวจสอบ', 'อนุมัติประกาศพื้นที่ รายงานปัญหา และระงับประกาศ'),
        TabStrip(
          labels: [
            'รออนุมัติ (${pending.length})',
            'รายงานปัญหา ($openIssues)',
            'พื้นที่ทั้งหมด (${store.spaces.length})',
          ],
          selected: adminTab,
          onChanged: (v) => setState(() => adminTab = v),
        ),
        if (adminTab == 0) ...[
          if (pending.isEmpty) empty('ไม่มีประกาศรอตรวจสอบ'),
          for (final s in pending)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.name, style: theme.textTheme.titleMedium),
                      ),
                      const StatusBadge('รอตรวจ', tone: BadgeTone.warning),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'เจ้าของ: ${store.user(s.ownerId).name} • โทร: ${store.user(s.ownerId).phoneLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '${s.category} • ${s.location}\n${bahtLabel(s.price)}/ชม. • ${s.capacity} คน',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(s.description, style: theme.textTheme.bodyMedium),
                  if (s.amenities.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: s.amenities
                          .map((a) => StatusBadge(a, tone: BadgeTone.neutral))
                          .toList(),
                    ),
                  ],
                  if (s.hasImage) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SpaceImage(
                        s,
                        height: 160,
                        fallback: Text(
                          'เปิดภาพไม่ได้',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton(
                        onPressed: () => perform(
                          context,
                          () => _spaceCtrl.reviewAsync(s.id, true, ''),
                        ),
                        child: const Text('อนุมัติประกาศ'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final r = await askReason(
                            context,
                            'เหตุผลไม่อนุมัติ',
                          );
                          if (r != null && mounted) {
                            perform(
                              context,
                              () => _spaceCtrl.reviewAsync(s.id, false, r),
                            );
                          }
                        },
                        child: const Text('ปฏิเสธประกาศ'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ] else if (adminTab == 1) ...[
          if (store.issues.isEmpty) empty('ยังไม่มีรายงานปัญหา'),
          for (final i in store.issues)
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          i.subject,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      StatusBadge(
                        i.closed ? 'ปิดแล้ว' : 'รอดำเนินการ',
                        tone: i.closed ? BadgeTone.success : BadgeTone.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'ผู้แจ้ง: ${store.user(i.reporterId).name}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(i.detail, style: theme.textTheme.bodyMedium),
                  if (i.closed) ...[
                    const SizedBox(height: 8),
                    Text(
                      'ผลการแก้ไข: ${i.resolution}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ] else
                    TextButton(
                      onPressed: () async {
                        final r = await askReason(context, 'ผลการแก้ไขปัญหา');
                        if (r != null && mounted) {
                          perform(
                            context,
                            () => _spaceCtrl.closeIssueAsync(i.id, r),
                          );
                        }
                      },
                      child: const Text('บันทึกผลและปิดรายงาน'),
                    ),
                ],
              ),
            ),
        ] else ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text('ทั้งหมด (${store.spaces.length})'),
                selected: allSpacesFilter == 0,
                onSelected: (_) => setState(() => allSpacesFilter = 0),
              ),
              ChoiceChip(
                label: Text(
                  'เปิดใช้งาน (${store.spaces.where((s) => s.status == SpaceStatus.approved).length})',
                ),
                selected: allSpacesFilter == 1,
                onSelected: (_) => setState(() => allSpacesFilter = 1),
              ),
              ChoiceChip(
                label: Text(
                  'ถูกระงับ (${store.spaces.where((s) => s.status == SpaceStatus.rejected).length})',
                ),
                selected: allSpacesFilter == 2,
                onSelected: (_) => setState(() => allSpacesFilter = 2),
              ),
              ChoiceChip(
                label: Text(
                  'รอตรวจ (${store.spaces.where((s) => s.status == SpaceStatus.pending).length})',
                ),
                selected: allSpacesFilter == 3,
                onSelected: (_) => setState(() => allSpacesFilter = 3),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (store.spaces.where((s) {
            if (allSpacesFilter == 1) return s.status == SpaceStatus.approved;
            if (allSpacesFilter == 2) return s.status == SpaceStatus.rejected;
            if (allSpacesFilter == 3) return s.status == SpaceStatus.pending;
            return true;
          }).isEmpty)
            empty('ไม่มีพื้นที่ในสถานะนี้'),
          for (final s in store.spaces.where((s) {
            if (allSpacesFilter == 1) return s.status == SpaceStatus.approved;
            if (allSpacesFilter == 2) return s.status == SpaceStatus.rejected;
            if (allSpacesFilter == 3) return s.status == SpaceStatus.pending;
            return true;
          }))
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(s.name, style: theme.textTheme.titleMedium),
                      ),
                      StatusBadge(s.status.label, tone: spaceTone(s.status)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'เจ้าของ: ${store.user(s.ownerId).name} • โทร: ${store.user(s.ownerId).phoneLabel}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${s.category} • ${s.location} • ${bahtLabel(s.price)}/ชม. • ${s.capacity} คน',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (s.reviewReason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'หมายเหตุ: ${s.reviewReason}',
                      style: TextStyle(
                        fontSize: 12,
                        color: toneColor(context, BadgeTone.danger),
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (s.status == SpaceStatus.approved)
                        OutlinedButton.icon(
                          onPressed: () async {
                            final r = await askReason(
                              context,
                              'ระบุเหตุผลที่ระงับประกาศ',
                            );
                            if (r != null && mounted) {
                              perform(
                                context,
                                () => _spaceCtrl.suspendSpaceAsync(s.id, r),
                              );
                            }
                          },
                          icon: const Icon(Icons.block, size: 16),
                          label: const Text('ระงับประกาศ'),
                        ),
                      if (s.status == SpaceStatus.rejected)
                        FilledButton.icon(
                          onPressed: () => perform(
                            context,
                            () =>
                                _spaceCtrl.activateSpaceAsync(s.id),
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: const Text('เปิดใช้งานใหม่'),
                        ),
                      if (s.status == SpaceStatus.pending) ...[
                        FilledButton(
                          onPressed: () => perform(
                            context,
                            () => _spaceCtrl.reviewAsync(s.id, true, ''),
                          ),
                          child: const Text('อนุมัติประกาศ'),
                        ),
                        OutlinedButton(
                          onPressed: () async {
                            final r = await askReason(
                              context,
                              'เหตุผลไม่อนุมัติ',
                            );
                            if (r != null && mounted) {
                              perform(
                                context,
                                () => _spaceCtrl.reviewAsync(s.id, false, r),
                              );
                            }
                          },
                          child: const Text('ปฏิเสธประกาศ'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget finance() {
    final slipReviewCount = store.bookings
        .where((b) => b.status == BookingStatus.slipReview)
        .length;
    final readyPayoutCount = store.bookings
        .where(
          (b) => b.status == BookingStatus.completed && b.paidOutAt == null,
        )
        .length;
    final escrowHolding = store.bookings
        .where(
          (b) =>
              b.status == BookingStatus.confirmed ||
              (b.status == BookingStatus.completed && b.paidOutAt == null),
        )
        .fold<int>(0, (sum, b) => sum + b.ownerNet);
    final platformRevenue = store.bookings
        .where(
          (b) =>
              b.status == BookingStatus.confirmed ||
              b.status == BookingStatus.completed,
        )
        .fold<int>(0, (sum, b) => sum + b.platformFee);

    final list = store.bookings
        .where(
          (b) =>
              (filter == null || b.status == filter) &&
              (!pendingPayoutOnly || b.paidOutAt == null),
        )
        .toList();
    return PageBody(
      children: [
        heading(
          'การจองและการเงิน',
          'ตรวจสอบสลิปเงินเข้า บัญชีตัวกลาง และบันทึกจ่ายเงินเจ้าของพื้นที่',
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = constraints.maxWidth < 400
                ? (constraints.maxWidth - 12) / 2
                : 220.0;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'สลิปรอตรวจ',
                    value: '$slipReviewCount รายการ',
                    icon: Icons.receipt_long_outlined,
                    tone: slipReviewCount > 0
                        ? BadgeTone.warning
                        : BadgeTone.neutral,
                    onTap: () => setState(() {
                      filter = BookingStatus.slipReview;
                      pendingPayoutOnly = false;
                    }),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'รอโอนให้เจ้าของ',
                    value: '$readyPayoutCount รายการ',
                    icon: Icons.payments_outlined,
                    tone: readyPayoutCount > 0
                        ? BadgeTone.info
                        : BadgeTone.neutral,
                    onTap: () => setState(() {
                      filter = BookingStatus.completed;
                      pendingPayoutOnly = true;
                    }),
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'เงินตัวกลางถือไว้',
                    value: bahtLabel(escrowHolding),
                    icon: Icons.account_balance_outlined,
                    tone: BadgeTone.primary,
                  ),
                ),
                SizedBox(
                  width: tileWidth,
                  child: StatTile(
                    label: 'ค่าบริการสะสม (5%)',
                    value: bahtLabel(platformRevenue),
                    icon: Icons.savings_outlined,
                    tone: BadgeTone.success,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('ทั้งหมด'),
              selected: filter == null,
              onSelected: (_) => setState(() {
                filter = null;
                pendingPayoutOnly = false;
              }),
            ),
            ChoiceChip(
              label: Text('รอตรวจสลิป ($slipReviewCount)'),
              selected: filter == BookingStatus.slipReview,
              onSelected: (_) => setState(() {
                filter = BookingStatus.slipReview;
                pendingPayoutOnly = false;
              }),
            ),
            ChoiceChip(
              label: Text('รอจ่ายเจ้าของ ($readyPayoutCount)'),
              selected: filter == BookingStatus.completed && pendingPayoutOnly,
              onSelected: (_) => setState(() {
                filter = BookingStatus.completed;
                pendingPayoutOnly = true;
              }),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (ctx) => SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'กรองตามสถานะการจอง',
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                label: const Text('ทั้งหมด'),
                                selected: filter == null,
                                onSelected: (_) {
                                  setState(() {
                                    filter = null;
                                    pendingPayoutOnly = false;
                                  });
                                  Navigator.pop(ctx);
                                },
                              ),
                              for (final s in BookingStatus.values)
                                ChoiceChip(
                                  label: Text(s.label),
                                  selected: filter == s,
                                  onSelected: (_) {
                                    setState(() {
                                      filter = s;
                                      pendingPayoutOnly = false;
                                    });
                                    Navigator.pop(ctx);
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.tune, size: 16),
              label: Text(
                filter != null &&
                        filter != BookingStatus.slipReview &&
                        filter != BookingStatus.completed
                    ? 'สถานะ: ${filter!.label}'
                    : 'สถานะอื่นๆ',
              ),
            ),
            ActionChip(
              avatar: const Icon(Icons.copy_outlined, size: 15),
              label: const Text('คัดลอกสรุปการเงิน'),
              onPressed: () async {
                final todayStr = dateLabel(DateTime.now());
                final summary =
                    '[รายงานสรุปการเงิน RentSpace]\n'
                    'วันที่: $todayStr\n'
                    '• สลิปรอตรวจ: $slipReviewCount รายการ\n'
                    '• รอโอนให้เจ้าของ: $readyPayoutCount รายการ\n'
                    '• เงินตัวกลางถือไว้ (Escrow): ${bahtLabel(escrowHolding)}\n'
                    '• รายได้ค่าบริการสะสม (5%): ${bahtLabel(platformRevenue)}\n'
                    '• จำนวนการจองทั้งหมด: ${store.bookings.length} รายการ';
                Clipboard.setData(ClipboardData(text: summary));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('คัดลอกสรุปบัญชีการเงินแล้ว'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (list.isEmpty) empty('ไม่มีรายการในสถานะนี้'),
        ...list.map(_adminFinanceCard),
      ],
    );
  }

  Widget users() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final filtered = _authCtrl.filterUsers(
      query: userQuery,
      role: userRoleFilter,
    );
    return PageBody(
      children: [
        heading('จัดการผู้ใช้', 'เปิด/ปิดการใช้งานบัญชี และตรวจสอบสิทธิ์'),
        TextField(
          key: const ValueKey('user-search-field'),
          controller: userSearchController,
          onChanged: (v) => setState(() => userQuery = v),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search, size: 19),
            suffixIcon: userQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'ล้างคำค้นหา',
                    onPressed: () async {
                      userSearchController.clear();
                      setState(() => userQuery = '');
                    },
                    icon: const Icon(Icons.close, size: 18),
                  ),
            hintText: 'ค้นหาชื่อหรืออีเมลผู้ใช้',
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final roleOption in <UserRole?>[null, ...UserRole.values])
              ChoiceChip(
                label: Text(roleOption?.label ?? 'ทุกบทบาท'),
                selected: userRoleFilter == roleOption,
                onSelected: (_) => setState(() => userRoleFilter = roleOption),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty) empty('ไม่พบบัญชีผู้ใช้ที่ตรงกับเงื่อนไข'),
        for (final u in filtered)
          SurfaceCard(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                  child: Text(
                    _initial(u.name),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            u.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          StatusBadge(
                            u.role.label,
                            tone: u.role == UserRole.admin
                                ? BadgeTone.primary
                                : BadgeTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(u.email, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 2),
                      Text(
                        'โทร: ${u.phoneLabel}',
                        style: theme.textTheme.bodySmall,
                      ),
                      if (u.bankInfo.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'บัญชีรับเงิน: ${u.bankInfo}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              borderRadius: BorderRadius.circular(4),
                              onTap: () async {
                                Clipboard.setData(
                                  ClipboardData(text: u.bankInfo),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'คัดลอกบัญชี ${u.bankInfo} แล้ว',
                                    ),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(2.0),
                                child: Icon(
                                  Icons.copy_outlined,
                                  size: 13,
                                  color: scheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),
                      StatusBadge(
                        u.active ? 'ใช้งานได้' : 'ถูกระงับ',
                        tone: u.active ? BadgeTone.success : BadgeTone.danger,
                      ),
                    ],
                  ),
                ),
                if (u.role == UserRole.admin)
                  Icon(
                    Icons.admin_panel_settings_outlined,
                    size: 20,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  )
                else
                  Switch(
                    value: u.active,
                    onChanged: (_) => perform(
                      context,
                      () => _authCtrl.toggleUserAsync(u.id),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.store,
    required this.user,
    required this.onHomeTap,
    required this.onProfileTap,
    required this.onLogout,
  });
  final AppStore store;
  final AppUser user;
  final VoidCallback onHomeTap;
  final VoidCallback onProfileTap;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 56,
      padding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
      color: scheme.surfaceContainerLow,
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onHomeTap,
              borderRadius: BorderRadius.circular(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.grid_view_rounded,
                      size: 16,
                      color: scheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'rentSPACE',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: '${user.name} (${user.role.label})',
            child: InkWell(
              onTap: onProfileTap,
              customBorder: const CircleBorder(),
              child: CircleAvatar(
                radius: 13,
                backgroundColor: scheme.primary.withValues(alpha: 0.12),
                child: Text(
                  _initial(user.name),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ThemeToggle(
            dark: store.darkMode,
            onChanged: (v) {
              if (v != store.darkMode) store.toggleTheme();
            },
          ),
          IconButton(
            tooltip: 'ออกจากระบบ',
            onPressed: onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
    );
  }
}

class ProfilePanel extends StatefulWidget {
  const ProfilePanel({super.key, required this.store, this.authController});
  final AppStore store;
  final AuthController? authController;
  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  late final TextEditingController name;
  late final TextEditingController email;
  late final TextEditingController phone;
  late final TextEditingController bankInfo;
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  bool hidePassword = true;

  @override
  void initState() {
    super.initState();
    final initialUser = widget.store.currentUser;
    name = TextEditingController(text: initialUser?.name ?? '');
    email = TextEditingController(text: initialUser?.email ?? '');
    phone = TextEditingController(text: initialUser?.phone ?? '');
    bankInfo = TextEditingController(text: initialUser?.bankInfo ?? '');
  }

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    bankInfo.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUser = widget.store.currentUser;
    if (currentUser == null) return const SizedBox.shrink();
    return PageBody(
      children: [
        heading('โปรไฟล์ของฉัน', currentUser.role.label),
        SurfaceCard(
          title: 'ข้อมูลบัญชี',
          subtitle: 'แก้ไขข้อมูลที่ใช้ติดต่อและแสดงในระบบ',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              formInput(name, 'ชื่อ-นามสกุล'),
              formInput(email, 'อีเมล'),
              formInput(
                phone,
                'เบอร์โทรศัพท์',
                keyboardType: TextInputType.phone,
              ),
              if (currentUser.role == UserRole.owner)
                formInput(
                  bankInfo,
                  'บัญชีธนาคารรับเงินโอน (เช่น กสิกรไทย 123-4-56789-0)',
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton(
                  onPressed: () => perform(
                    context,
                    () => (widget.authController ?? AuthController(widget.store))
                        .updateProfileAsync(
                      name.text,
                      email.text,
                      phone.text,
                      bankInfo.text,
                    ),
                    'บันทึกโปรไฟล์แล้ว',
                  ),
                  child: const Text('บันทึกโปรไฟล์'),
                ),
              ),
            ],
          ),
        ),
        SurfaceCard(
          title: 'เปลี่ยนรหัสผ่าน',
          subtitle: 'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร',
          action: IconButton(
            tooltip: hidePassword ? 'แสดงรหัสผ่าน' : 'ซ่อนรหัสผ่าน',
            onPressed: () => setState(() => hidePassword = !hidePassword),
            icon: Icon(
              hidePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              size: 18,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              formInput(
                currentPassword,
                'รหัสผ่านปัจจุบัน',
                obscure: hidePassword,
              ),
              formInput(
                newPassword,
                'รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)',
                obscure: hidePassword,
              ),
              formInput(
                confirmPassword,
                'ยืนยันรหัสผ่านใหม่',
                obscure: hidePassword,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final ok = await perform(
                      context,
                      () => (widget.authController ?? AuthController(widget.store))
                          .changePasswordAsync(
                        currentPassword.text,
                        newPassword.text,
                        confirmPassword.text,
                      ),
                      'เปลี่ยนรหัสผ่านเรียบร้อยแล้ว',
                    );
                    if (ok && context.mounted) {
                      currentPassword.clear();
                      newPassword.clear();
                      confirmPassword.clear();
                    }
                  },
                  icon: const Icon(Icons.lock_reset_outlined, size: 18),
                  label: const Text('บันทึกรหัสผ่านใหม่'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const SectionHeader('รายงานของฉัน'),
        if (!widget.store.issues.any(
          (i) => i.reporterId == currentUser.id,
        ))
          empty('ยังไม่มีรายงาน'),
        for (final i in widget.store.issues.where(
          (i) => i.reporterId == currentUser.id,
        ))
          SurfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(i.subject, style: theme.textTheme.titleSmall),
                    ),
                    StatusBadge(
                      i.closed ? 'ปิดแล้ว' : 'รอดำเนินการ',
                      tone: i.closed ? BadgeTone.success : BadgeTone.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(i.detail, style: theme.textTheme.bodySmall),
                if (i.closed) ...[
                  const SizedBox(height: 4),
                  Text(
                    'ผลการแก้ไข: ${i.resolution}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
