part of 'home_page.dart';

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.issue, this.reporterName, this.onClose});
  final Issue issue;
  final String? reporterName;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(issue.subject, style: theme.textTheme.titleSmall),
              ),
              StatusBadge(
                issue.closed ? 'ปิดแล้ว' : 'รอดำเนินการ',
                tone: issue.closed ? BadgeTone.success : BadgeTone.warning,
              ),
            ],
          ),
          if (reporterName != null) ...[
            const SizedBox(height: 4),
            Text('ผู้แจ้ง: $reporterName', style: theme.textTheme.bodySmall),
          ],
          SizedBox(height: reporterName != null ? 8 : 4),
          Text(
            issue.detail,
            style: reporterName != null
                ? theme.textTheme.bodyMedium
                : theme.textTheme.bodySmall,
          ),
          if (issue.closed) ...[
            SizedBox(height: reporterName != null ? 8 : 4),
            Text(
              'ผลการแก้ไข: ${issue.resolution}',
              style: theme.textTheme.bodySmall,
            ),
          ] else if (onClose != null)
            TextButton(
              onPressed: onClose,
              child: const Text('บันทึกผลและปิดรายงาน'),
            ),
        ],
      ),
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
    final currentUser = widget.store.currentUser;
    if (currentUser == null) return const SizedBox.shrink();
    final myIssues = widget.store.issues
        .where((i) => i.reporterId == currentUser.id)
        .toList();
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
        if (myIssues.isEmpty) empty('ยังไม่มีรายงาน'),
        for (final i in myIssues) _IssueCard(issue: i),
      ],
    );
  }
}
