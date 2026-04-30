// lib/features/auth/screens/signup_screen.dart
//
// 新規登録画面。
// ・Supabase.instance.client.auth.signUp を直接呼び出す
// ・メール / パスワード / パスワード確認
// ・パスワード表示切り替え（各フィールド独立）
// ・登録成功 → 「確認メールを送信しました」バナー表示 → /login へ遷移
// ・AuthException を日本語に変換してインライン表示

import 'package:diet_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

// ─────────────────────────────────────────────
// AuthException を日本語に変換
// ─────────────────────────────────────────────
String _toJapanese(AuthException e) {
  final msg = e.message.toLowerCase();
  if (msg.contains('user already registered') ||
      msg.contains('already exists')) {
    return 'このメールアドレスはすでに登録されています\nログイン画面からサインインしてください';
  }
  if (msg.contains('password should be at least')) {
    return 'パスワードは6文字以上で入力してください';
  }
  if (msg.contains('invalid email') || msg.contains('unable to validate')) {
    return '正しいメールアドレスの形式で入力してください';
  }
  if (msg.contains('too many requests') || msg.contains('rate limit')) {
    return 'しばらく時間をおいてから再試行してください';
  }
  if (msg.contains('network') || msg.contains('connection')) {
    return 'ネットワークエラーが発生しました\n接続を確認してください';
  }
  return e.message;
}

// ─────────────────────────────────────────────
// 画面スコープの状態 Provider
// ─────────────────────────────────────────────
final _signupLoadingProvider = StateProvider.autoDispose<bool>((_) => false);
final _signupErrorProvider   = StateProvider.autoDispose<String?>((_) => null);
final _signupSuccessProvider = StateProvider.autoDispose<bool>((_) => false);

// ─────────────────────────────────────────────
// 新規登録画面
// ─────────────────────────────────────────────
class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey      = GlobalKey<FormState>();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl  = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirm  = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ─── 登録送信 ───────────────────────────────
  Future<void> _submit() async {
    ref.read(_signupErrorProvider.notifier).state   = null;
    ref.read(_signupSuccessProvider.notifier).state = false;

    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    ref.read(_signupLoadingProvider.notifier).state = true;
    try {
      // Supabase.instance.client.auth.signUp を直接呼び出す
      await Supabase.instance.client.auth.signUp(
        email:    _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      // 成功 → DB トリガーが profiles を自動作成する

      if (mounted) {
        ref.read(_signupSuccessProvider.notifier).state = true;
        // 2秒後にログイン画面へ
        await Future.delayed(const Duration(seconds: 2));
        if (mounted) context.go('/login');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ref.read(_signupErrorProvider.notifier).state = _toJapanese(e);
      }
    } catch (_) {
      if (mounted) {
        ref.read(_signupErrorProvider.notifier).state =
            '予期しないエラーが発生しました。もう一度お試しください。';
      }
    } finally {
      if (mounted) {
        ref.read(_signupLoadingProvider.notifier).state = false;
      }
    }
  }

  // ─── build ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isLoading    = ref.watch(_signupLoadingProvider);
    final errorMessage = ref.watch(_signupErrorProvider);
    final isSuccess    = ref.watch(_signupSuccessProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/login'),
        ),
        title: const Text('新規登録'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
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
                  const Gap(32),

                  // ─── タイトル ────────────────────
                  Text(
                    'アカウントを作成',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                  ),
                  const Gap(6),
                  Text(
                    'メールアドレスとパスワードを入力してください',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                  const Gap(32),

                  // ─── 成功バナー ──────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: isSuccess
                        ? Column(
                            children: [
                              _SuccessBanner(),
                              const Gap(16),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),

                  // ─── エラーバナー ────────────────
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: errorMessage != null
                        ? Column(
                            children: [
                              _ErrorBanner(message: errorMessage),
                              const Gap(16),
                            ],
                          )
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
                      if (!RegExp(r'^[^@]+@[^@]+\.[^@]+$').hasMatch(v.trim())) {
                        return '正しいメールアドレスを入力してください';
                      }
                      return null;
                    },
                  ),
                  const Gap(16),

                  // ─── パスワード ──────────────────
                  AppTextField(
                    controller: _passwordCtrl,
                    label: 'パスワード（6文字以上）',
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.next,
                    suffixIcon: _VisibilityButton(
                      obscure: _obscurePassword,
                      onToggle: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'パスワードを入力してください';
                      if (v.length < 6) return '6文字以上で入力してください';
                      return null;
                    },
                  ),
                  const Gap(16),

                  // ─── パスワード確認 ──────────────
                  AppTextField(
                    controller: _confirmCtrl,
                    label: 'パスワード（確認）',
                    obscureText: _obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    suffixIcon: _VisibilityButton(
                      obscure: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) {
                        return 'パスワード（確認）を入力してください';
                      }
                      if (v != _passwordCtrl.text) {
                        return 'パスワードが一致しません';
                      }
                      return null;
                    },
                  ),
                  const Gap(32),

                  // ─── 登録ボタン ──────────────────
                  PrimaryButton(
                    text: 'アカウントを作成',
                    isLoading: isLoading,
                    onPressed: (isLoading || isSuccess) ? null : _submit,
                  ),
                  const Gap(20),

                  // ─── ログインへのリンク ───────────
                  _LoginLink(),
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
// パスワード表示切り替えボタン
// ─────────────────────────────────────────────
class _VisibilityButton extends StatelessWidget {
  const _VisibilityButton({required this.obscure, required this.onToggle});
  final bool obscure;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        color: Colors.grey[500],
        size: 20,
      ),
      onPressed: onToggle,
    );
  }
}

// ─────────────────────────────────────────────
// 成功バナー
// ─────────────────────────────────────────────
class _SuccessBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.08),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              color: AppTheme.primaryGreen, size: 18),
          const Gap(10),
          Expanded(
            child: Text(
              '確認メールを送信しました\nメールのリンクをタップして登録を完了してください',
              style: TextStyle(
                color: AppTheme.primaryGreen,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppTheme.errorColor, size: 18),
          const Gap(10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: AppTheme.errorColor,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ログイン画面へのリンク
// ─────────────────────────────────────────────
class _LoginLink extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'すでにアカウントをお持ちの方は',
          style: TextStyle(fontSize: 13, color: Colors.grey[500]),
        ),
        GestureDetector(
          onTap: () => context.go('/login'),
          child: Text(
            'ログイン',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.primaryGreen,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
              decorationColor: AppTheme.primaryGreen,
            ),
          ),
        ),
      ],
    );
  }
}
