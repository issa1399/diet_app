// lib/main.dart
//
// アプリのエントリーポイント。
// Supabase を初期化してから ProviderScope で包む。
//
// 実行前に以下を設定すること:
//   1. .env.example を .env にコピーして値を入力
//   2. または下の const を直接書き換える（本番環境では環境変数を使うこと）

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/router/app_router.dart';
import 'shared/theme/app_theme.dart';

// ──────────────────────────────────────────────
// ⚠️ 本番環境ではハードコードしないこと。
//    flutter_dotenv 等を使って .env から読み込む。
// ──────────────────────────────────────────────
const _supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'https://your-project.supabase.co',
);
const _supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: 'your-anon-key',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
    // デバッグ時は debug: true にするとログが出る
    debug: false,
  );

  runApp(
    const ProviderScope(
      child: DietApp(),
    ),
  );
}

class DietApp extends ConsumerWidget {
  const DietApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Diet App',
      theme: AppTheme.theme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
