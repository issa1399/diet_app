// lib/features/auth/screens/login_screen.dart
//
// ログイン画面。
// ・Supabase.instance.client.auth.signInWithPassword を直接呼び出す
// ・ログイン成功時にミッション進捗（login_daily / login_weekly）を更新
// ・フォームバリデーション
// ・ローディング中はボタン無効化
// ・AuthException を日本語メッセージに変換してインライン表示
// ・パスワード表示切り替え
// ・ログイン成功後は context.go('/home')

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import 'package:diet_app/theme/app_theme.dart';
import '../../missions/mission_service.dart';

// ─────────────────────────────────────────────
// AuthException を日本語に変換
// ─────────────────────────────────────────────
String _toJapanese(AuthException e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('invalid login credentials') ||
      msg.contains('invalid credentials')) {
    return 'メールアドレスまたはパスワードが違います';
  }
  if (msg.contains('email not confirmed')) {
    return 'メールアドレスの確認が完了していません\n受信トレイを確認してください';
  }
  if (msg.contains('too many requests') || msg.contains('rate limit')) {
    return 'しばらく時間をおいてから再試行してください';
  }
  if (msg.contains('user not found')) {
    return 'このメールアドレスは登録されていません';
  }
  if (msg.contains('network') || msg.contains('connection')) {
    return 'ネットワークエラーが発生しました\n接続を確認してください';
  }
  return e.message;
}

// ─────────────────────────────────────────────
// 画面スコープの状態 Provider
// ─────────────────────────────────────────────
final _loginLoadingProvider = StateProvider.autoDispose<bool>((_) => false);
final _loginErrorProvider   = StateProvider.autoDispose<String?>((_) => null);

// ─────────────────────────────────────────────
// ログイン画面
// ─────────────────────────────────────────────
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure       = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ─── ログイン送信 ───────────────────────────
  Future<void> _submit() async {
    ref.read(_loginErrorProvider.notifier).state = null;
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    ref.read(_loginLoadingProvider.notifier).state = true;
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );

      // ミッション進捗を更新（ログイン daily / weekly）
      // サイレント実行：失敗してもログイン自体を止めない
      final uid = res.user?.id;
      if (uid != null) {
        MissionService.onLogin(uid).catchError((_) {});
      }

      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      if (mounted) {
        ref.read(_loginErrorProvider.notifier).state = _toJapanese(e);
      }
    } catch (_) {
      if (mounted) {
        ref.read(_loginErrorProvider.notifier).state =
            '予期しないエラーが発生しました。もう一度お試しください。';
      }
    } finally {
      if (mounted) {
        ref.read(_loginLoadingProvider.notifier).state = false;
      }
    }
  }

  // ─── build ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLoading    = ref.watch(_loginLoadingProvider);
    final errorMessage = ref.watch(_loginErrorProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Gap(64),

                  // ─── ヘッダー ────────────────────
                  _Header(),
                  const Gap(48),

                  // ─── エラーバナー ────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: errorMessage != null
                        ? Column(children: [
                            _ErrorBanner(message: errorMessage),
                            const Gap(16),
                          ])
                        : const SizedBox.shrink(),
                  ),

                  // ─── メールアドレス ──────────────
                  AppTextField(
                    controller: _emailCtrl,
                    label: 'メールアドレス',
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'メールアドレスを入力してください';
                      }
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$')
                          .hasMatch(v.trim())) {
                        return '正しいメールアドレスを入力してください';
                      }
                      return null;
                    },
                  ),

                  const Gap(16),

                  // ─── パスワード ──────────────────
                  AppTextField(
                    controller: _passwordCtrl,
                    label: 'パスワード',
                    obscureText: _obscure,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        color: Colors.grey[500],
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscure = !_obscure),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'パスワードを入力してください';
                      }
                      if (v.length < 6) return '6文字以上で入力してください';
                      return null;
                    },
                  ),

                  const Gap(32),

                  // ─── ログインボタン ──────────────
                  PrimaryButton(
                    text: 'ログイン',
                    isLoading: isLoading,
                    onPressed: isLoading ? null : _submit,
                  ),

                  const Gap(20),

                  // ─── 新規登録リンク ──────────────
                  _SignupLink(),
                  const Gap(32),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ヘッダー
// ─────────────────────────────────────────────
class _Header extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppTheme.lightGreen,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.trending_up_rounded,
            color: AppTheme.primaryGreen, size: 28),
      ),
      const Gap(20),
      Text(
        '努力が見える\nダイエット',
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppTheme.primaryGreen,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
      ),
      const Gap(8),
      Text(
        '体重ではなく、行動を記録しよう',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey[500],
            ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// エラーバナー
// ─────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.errorColor.withOpacity(0.08),
        border: Border.all(color: AppTheme.errorColor.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.error_outline_rounded,
            color: AppTheme.errorColor, size: 18),
        const Gap(10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
                color: AppTheme.errorColor, fontSize: 13, height: 1.5),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 新規登録リンク
// ─────────────────────────────────────────────
class _SignupLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Text(
        'アカウントをお持ちでない方は',
        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
      ),
      GestureDetector(
        onTap: () => context.go('/signup'),
        child: Text(
          '新規登録',
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.primaryGreen,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.underline,
            decorationColor: AppTheme.primaryGreen,
          ),
        ),
      ),
    ]);
  }
}
