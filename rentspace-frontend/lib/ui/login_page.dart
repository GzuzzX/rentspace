import 'package:flutter/material.dart';

import '../controllers/auth_controller.dart';
import '../data/app_store.dart';
import '../models/domain.dart';
import 'common.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.store, this.authController});
  final AppStore store;
  final AuthController? authController;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController(),
      password = TextEditingController(),
      confirmPassword = TextEditingController(),
      name = TextEditingController(),
      phone = TextEditingController();
  bool register = false, showPassword = false, showConfirmPassword = false;
  UserRole role = UserRole.renter;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  void submit() => perform(context, () async {
    final auth = widget.authController ?? AuthController(widget.store);
    if (register) {
      await auth.registerAsync(
        name.text,
        email.text,
        password.text,
        role,
        phone.text,
        confirmPassword.text,
      );
    } else {
      await auth.loginAsync(email.text, password.text);
    }
  });

  Widget _visibilityToggle(
    bool visible,
    String showLabel,
    String hideLabel,
    VoidCallback onToggle,
  ) => IconButton(
    tooltip: visible ? hideLabel : showLabel,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 44, height: 44),
    onPressed: onToggle,
    icon: Icon(
      visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      size: 18,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [scheme.surfaceContainerLow, scheme.surface]
                : [
                    scheme.primary.withValues(alpha: 0.045),
                    scheme.surfaceContainerLow,
                  ],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: dark ? 0.9 : 0.8),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: dark ? 0.35 : 0.06),
                            blurRadius: 28,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        alignment: Alignment.topCenter,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.store.syncError != null)
                              NoticeBanner(
                                icon: Icons.error_outline_rounded,
                                message: widget.store.syncError!,
                                tone: BadgeTone.danger,
                                iconColor: scheme.error,
                                bgAlpha: 0.08,
                                borderAlpha: 0.3,
                                radius: 10,
                                margin: const EdgeInsets.only(bottom: 18),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                textStyle: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.error,
                                ),
                              ),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        scheme.primary,
                                        scheme.primary.withValues(alpha: 0.82),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: scheme.primary.withValues(alpha: 0.24),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.grid_view_rounded,
                                    size: 22,
                                    color: scheme.onPrimary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'rentSPACE',
                                        style: theme.textTheme.titleLarge?.copyWith(
                                          fontSize: 20,
                                          letterSpacing: -0.4,
                                          height: 1.15,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'พื้นที่ที่ใช่ เริ่มต้นไอเดียดี ๆ',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ThemeToggle(
                                  dark: widget.store.darkMode,
                                  onChanged: (v) {
                                    if (v != widget.store.darkMode) {
                                      widget.store.toggleTheme();
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            TabStrip(
                              labels: const ['เข้าสู่ระบบ', 'สมัครสมาชิก'],
                              selected: register ? 1 : 0,
                              expand: true,
                              onChanged: (v) => setState(() => register = v == 1),
                              margin: const EdgeInsets.only(bottom: 20),
                            ),
                            if (register)
                              formInput(
                                name,
                                'ชื่อ-นามสกุล',
                                prefix: const Icon(Icons.person_outline_rounded, size: 18),
                                autofillHints: const [AutofillHints.name],
                                textInputAction: TextInputAction.next,
                              ),
                            formInput(
                              email,
                              'อีเมล',
                              prefix: const Icon(Icons.mail_outline_rounded, size: 18),
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                            ),
                            if (register)
                              formInput(
                                phone,
                                'เบอร์โทรศัพท์ติดต่อ (เช่น 081-234-5678)',
                                prefix: const Icon(Icons.phone_outlined, size: 18),
                                keyboardType: TextInputType.phone,
                                autofillHints: const [AutofillHints.telephoneNumber],
                                textInputAction: TextInputAction.next,
                              ),
                            formInput(
                              password,
                              'รหัสผ่าน (อย่างน้อย 8 ตัวอักษร)',
                              prefix: const Icon(Icons.lock_outline_rounded, size: 18),
                              obscure: !showPassword,
                              autofillHints: [
                                register
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              textInputAction: register
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onSubmitted: register ? null : (_) => submit(),
                              autocorrect: false,
                              suffix: _visibilityToggle(
                                showPassword,
                                'แสดงรหัสผ่าน',
                                'ซ่อนรหัสผ่าน',
                                () => setState(
                                  () => showPassword = !showPassword,
                                ),
                              ),
                            ),
                            if (register)
                              formInput(
                                confirmPassword,
                                'ยืนยันรหัสผ่าน',
                                prefix: const Icon(Icons.verified_user_outlined, size: 18),
                                obscure: !showConfirmPassword,
                                autofillHints: const [AutofillHints.newPassword],
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => submit(),
                                autocorrect: false,
                                suffix: _visibilityToggle(
                                  showConfirmPassword,
                                  'แสดงยืนยันรหัสผ่าน',
                                  'ซ่อนยืนยันรหัสผ่าน',
                                  () => setState(
                                    () => showConfirmPassword =
                                        !showConfirmPassword,
                                  ),
                                ),
                              ),
                            if (register)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: DropdownButtonFormField<UserRole>(
                                  initialValue: role,
                                  decoration: const InputDecoration(
                                    labelText: 'ประเภทบัญชี',
                                    prefixIcon: Icon(Icons.badge_outlined, size: 18),
                                  ),
                                  items: [UserRole.renter, UserRole.owner]
                                      .map(
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(r.label),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (v) => setState(() => role = v!),
                                ),
                              ),
                            const SizedBox(height: 6),
                            FilledButton(
                              onPressed: submit,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(48),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Text(register ? 'สร้างบัญชี' : 'เข้าสู่ระบบ'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
