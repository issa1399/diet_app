// lib/core/router/app_router.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/signup_screen.dart';
import '../../features/friends/screens/friends_screen.dart';
import '../../features/missions/screens/missions_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/meals/screens/meal_log_screen.dart';
import '../../features/profile/screens/onboarding_screen.dart';
import '../../features/exercise/screens/exercise_log_screen.dart';
import '../../features/weight/screens/weight_log_screen.dart';

// 認証済みで自由に遷移できるパス
const _authPaths = {'/home', '/meals/new', '/weight/new', '/friends', '/missions', '/exercise/new'};

final appRouterProvider = Provider<GoRouter>((ref) {
  final notifier = _AppRouterNotifier();
  ref.onDispose(notifier.dispose);

  return GoRouter(
    initialLocation: '/login',
    refreshListenable: notifier,
    redirect: (_, s) => notifier.redirect(s),
    routes: [
      GoRoute(path: '/login',  builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/home',   builder: (_, __) => const HomeScreen()),
      GoRoute(
        path: '/meals/new',
        builder: (_, s) => MealLogScreen(dateParam: s.uri.queryParameters['date']),
      ),
      GoRoute(
        path: '/weight/new',
        builder: (_, s) => WeightLogScreen(dateParam: s.uri.queryParameters['date']),
      ),
      GoRoute(path: '/friends', builder: (_, __) => const FriendsScreen()),
      GoRoute(path: '/missions', builder: (_, __) => const MissionsScreen()),
      GoRoute(
        path: '/exercise/new',
        builder: (_, s) => ExerciseLogScreen(dateParam: s.uri.queryParameters['date']),
      ),
    ],
  );
});

class _AppRouterNotifier extends ChangeNotifier {
  _AppRouterNotifier() {
    _sub = Supabase.instance.client.auth.onAuthStateChange.listen(_onChange);
    final u = Supabase.instance.client.auth.currentUser;
    if (u != null) { _loggedIn = true; _load(u.id); }
  }

  bool _loggedIn = false;
  bool _done     = false;
  bool _loading  = false;
  late final StreamSubscription<AuthState> _sub;

  void _onChange(AuthState s) {
    final u = s.session?.user;
    if (u == null) { _loggedIn = false; _done = false; _loading = false; notifyListeners(); }
    else           { _loggedIn = true; _load(u.id); }
  }

  Future<void> _load(String uid) async {
    _loading = true; notifyListeners();
    try {
      final d = await Supabase.instance.client
          .from('profiles').select('onboarding_completed').eq('id', uid).maybeSingle();
      _done = d?['onboarding_completed'] as bool? ?? false;
    } catch (_) { _done = false; }
    finally { _loading = false; notifyListeners(); }
  }

  String? redirect(GoRouterState s) {
    final loc = s.matchedLocation;
    if (!_loggedIn) { return (loc == '/login' || loc == '/signup') ? null : '/login'; }
    if (_loading)   return null;
    if (!_done)     return loc == '/onboarding' ? null : '/onboarding';
    if (_authPaths.contains(loc)) return null;
    if (loc == '/login' || loc == '/signup' || loc == '/onboarding') return '/home';
    return null;
  }

  @override void dispose() { _sub.cancel(); super.dispose(); }
}