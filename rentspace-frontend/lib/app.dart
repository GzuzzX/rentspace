import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'controllers/auth_controller.dart';
import 'data/app_store.dart';
import 'ui/home_page.dart';
import 'ui/login_page.dart';
import 'ui/theme.dart';

const double kMobileMaxWidth = 430;
const double kMobileMaxHeight = 932;

class RentSpaceApp extends StatefulWidget {
  RentSpaceApp({super.key, AppStore? store}) : store = store ?? AppStore();
  final AppStore store;

  @override
  State<RentSpaceApp> createState() => _RentSpaceAppState();
}

class _RentSpaceAppState extends State<RentSpaceApp> {
  @override
  void initState() {
    super.initState();
    // แบบตัวอย่างอาจารย์: อ่าน token ที่เก็บไว้ในเครื่อง (flutter_secure_storage)
    // ถ้ามีและยังใช้ได้ จะล็อกอินกลับให้เอง
    AuthController(widget.store).restoreSession();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => MaterialApp(
      title: 'RentSpace',
      debugShowCheckedModeBanner: false,
      locale: const Locale('th'),
      supportedLocales: const [Locale('th'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: widget.store.darkMode ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) =>
          _MobileFrame(child: child ?? const SizedBox.shrink()),
      home: widget.store.currentUser == null
          ? LoginPage(store: widget.store)
          : HomePage(
              key: ValueKey(widget.store.currentUser!.id),
              store: widget.store,
            ),
    ),
  );
}

class _MobileFrame extends StatelessWidget {
  const _MobileFrame({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final outerSize = media.size;
    if (outerSize.width <= kMobileMaxWidth) {
      return child;
    }
    final scheme = Theme.of(context).colorScheme;
    final frameHeight = outerSize.height > kMobileMaxHeight + 48
        ? kMobileMaxHeight
        : outerSize.height;
    final framedSize = Size(kMobileMaxWidth, frameHeight);
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Container(
          width: framedSize.width,
          height: framedSize.height,
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: frameHeight < outerSize.height
                ? BorderRadius.circular(28)
                : BorderRadius.zero,
            border: Border.symmetric(
              vertical: BorderSide(color: scheme.outline),
              horizontal: frameHeight < outerSize.height
                  ? BorderSide(color: scheme.outline)
                  : BorderSide.none,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.14),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: MediaQuery(
            data: media.copyWith(size: framedSize),
            child: child,
          ),
        ),
      ),
    );
  }
}
