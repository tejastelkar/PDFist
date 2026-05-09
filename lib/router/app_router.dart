import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/providers.dart';
import '../screens/all_tools_screen.dart';
import '../screens/auth_screen.dart';
import '../screens/history_screen.dart';
import '../screens/home_screen.dart';
import '../screens/processing_screen.dart';
import '../screens/result_screen.dart';
import '../screens/search_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/tool_screen.dart';

// A navigable key so the router can be notified when auth state changes.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildAppRouter(WidgetRef ref) {
  final isAuth = ref.watch(isAuthenticatedProvider);
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    redirect: (context, state) {
      final onPublic = state.matchedLocation == '/' ||
          state.matchedLocation == '/auth';
      if (!isAuth && !onPublic) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (ctx, state) => const SplashScreen()),
      GoRoute(path: '/auth', builder: (ctx, state) => const AuthScreen()),
      GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
      GoRoute(path: '/search', builder: (ctx, state) => const SearchScreen()),
      GoRoute(path: '/all-tools', builder: (ctx, state) => const AllToolsScreen()),
      GoRoute(
        path: '/tool/:toolId',
        builder: (ctx, state) =>
            ToolScreen(toolId: state.pathParameters['toolId']!),
      ),
      GoRoute(
        path: '/processing/:toolId/:filename',
        builder: (ctx, state) => ProcessingScreen(
          toolId: state.pathParameters['toolId']!,
          filename: Uri.decodeComponent(state.pathParameters['filename']!),
        ),
      ),
      GoRoute(
        path: '/result/:toolId/:filename',
        builder: (ctx, state) => ResultScreen(
          toolId: state.pathParameters['toolId']!,
          filename: Uri.decodeComponent(state.pathParameters['filename']!),
        ),
      ),
      GoRoute(path: '/history', builder: (ctx, state) => const HistoryScreen()),
      GoRoute(path: '/settings', builder: (ctx, state) => const SettingsScreen()),
    ],
  );
}

// Simple non-guarded router used before ProviderScope is available.
final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/', builder: (ctx, state) => const SplashScreen()),
    GoRoute(path: '/auth', builder: (ctx, state) => const AuthScreen()),
    GoRoute(path: '/home', builder: (ctx, state) => const HomeScreen()),
    GoRoute(path: '/search', builder: (ctx, state) => const SearchScreen()),
    GoRoute(path: '/all-tools', builder: (ctx, state) => const AllToolsScreen()),
    GoRoute(
      path: '/tool/:toolId',
      builder: (ctx, state) =>
          ToolScreen(toolId: state.pathParameters['toolId']!),
    ),
    GoRoute(
      path: '/processing/:toolId/:filename',
      builder: (ctx, state) => ProcessingScreen(
        toolId: state.pathParameters['toolId']!,
        filename: Uri.decodeComponent(state.pathParameters['filename']!),
      ),
    ),
    GoRoute(
      path: '/result/:toolId/:filename',
      builder: (ctx, state) => ResultScreen(
        toolId: state.pathParameters['toolId']!,
        filename: Uri.decodeComponent(state.pathParameters['filename']!),
      ),
    ),
    GoRoute(path: '/history', builder: (ctx, state) => const HistoryScreen()),
    GoRoute(path: '/settings', builder: (ctx, state) => const SettingsScreen()),
  ],
);
