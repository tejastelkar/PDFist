import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'models/history_entry.dart';
import 'providers/providers.dart';
import 'router/app_router.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Hive.initFlutter();
  Hive.registerAdapter(HistoryEntryAdapter());
  await Hive.openBox<HistoryEntry>('history');

  if (kFirebaseEnabled) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await AuthService.instance.initGoogleSignIn();
  }

  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  runApp(const ProviderScope(child: PDFistApp()));
}

class PDFistApp extends ConsumerStatefulWidget {
  const PDFistApp({super.key});
  @override
  ConsumerState<PDFistApp> createState() => _PDFistAppState();
}

class _PDFistAppState extends ConsumerState<PDFistApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = buildAppRouter(routerNotifier);
  }

  @override
  Widget build(BuildContext context) {
    // Keep routerNotifier in sync with auth state.
    ref.listen<bool>(isAuthenticatedProvider, (_, isAuth) {
      routerNotifier.value = isAuth;
    });
    return MaterialApp.router(
      title: 'PDFist',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: _router,
    );
  }
}
