// lib/features/profile/screens/onboarding_screen.dart
// Step 0: ニックネーム
// Step 1: 年齢・性別
// Step 2: 身長・体重・目標体重
// Step 3: 活動レベル

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl   = PageController();
  int   _page       = 0;
  static const _total = 4;
  final _keys = List.generate(_total, (_) => GlobalKey<FormState>());

  final _nicknameCtrl = TextEditingController();
  final _ageCtrl      = TextEditingController();
  final _heightCtrl   = TextEditingController();
  final _weightCtrl   = TextEditingController();
  final _goalCtrl     = TextEditingController();

  String? _gender;
  String? _activityLevel;
  bool    _saving = false;
  String? _error;

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nicknameCtrl.dispose();
    _ageCtrl.dispose();
    _heightCtrl.dispose();
    _weightCtrl.dispose();
    _goalCtrl.dispose();
    super.dispose();
  }

  void _next() {
    if (!_keys[_page].currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  Future<void> _save() async {
    if (!_keys[_page].currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() { _saving = true; _error = null; });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('未ログイン');
      await Supabase.instance.client.from('profiles').update({
        'nickname':            _nicknameCtrl.text.trim().isEmpty ? null : _nicknameCtrl.text.trim(),
        'age':                 int.parse(_ageCtrl.text.trim()),
        'gender':              _gender,
        'height_cm':           double.parse(_heightCtrl.text.trim()),
        'initial_weight_kg':   double.parse(_weightCtrl.text.trim()),
        'goal_weight_kg':      _goalCtrl.text.trim().isEmpty ? null : double.parse(_goalCtrl.text.trim()),
        'activity_level':      _activityLevel,
        'onboarding_completed': true,
      }).eq('id', user.id);
      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _total - 1;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: Column(children: [
            _ProgressBar(current: _page, total: _total),
            if (_error != null) _ErrorBanner(message: _error!),
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _PageNickname(formKey: _keys[0], ctrl: _nicknameCtrl),
                  _PageAgeGender(formKey: _keys[1], ageCtrl: _ageCtrl,
                    gender: _gender, onGender: (v) => setState(() => _gender = v)),
                  _PageBody(formKey: _keys[2], heightCtrl: _heightCtrl,
                    weightCtrl: _weightCtrl, goalCtrl: _goalCtrl),
                  _PageActivity(formKey: _keys[3], selected: _activityLevel,
                    onChanged: (v) => setState(() => _activityLevel = v)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: PrimaryButton(
                text: isLast ? '始める' : '次へ',
                isLoading: _saving,
                onPressed: _saving ? null : (isLast ? _save : _next),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ─── ProgressBar ─────────────────────────────
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.current, required this.total});
  final int current, total;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
    child: Row(children: List.generate(total, (i) => Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 3),
        height: 4,
        decoration: BoxDecoration(
          color: i <= current ? AppTheme.primaryGreen : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ))),
  );
}

// ─── 共通ラッパー ─────────────────────────────
class _Wrap extends StatelessWidget {
  const _Wrap({required this.title, this.sub, required this.child});
  final String title;
  final String? sub;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
      if (sub != null) ...[const Gap(6),
        Text(sub!, style: TextStyle(fontSize: 13, color: Colors.grey.shade500))],
      const Gap(28),
      child,
    ]),
  );
}

// ─── Step 0: ニックネーム ─────────────────────
class _PageNickname extends StatelessWidget {
  const _PageNickname({required this.formKey, required this.ctrl});
  final GlobalKey<FormState> formKey;
  final TextEditingController ctrl;
  @override
  Widget build(BuildContext context) => _Wrap(
    title: 'ニックネームを\n決めてください',
    sub: '後から変更できます（任意）',
    child: Form(key: formKey, child: AppTextField(
      controller: ctrl,
      label: 'ニックネーム（任意）',
      textInputAction: TextInputAction.done,
      validator: (v) {
        if (v != null && v.trim().length > 20) return '20文字以内で入力してください';
        return null;
      },
    )),
  );
}

// ─── Step 1: 年齢・性別 ───────────────────────
class _PageAgeGender extends StatelessWidget {
  const _PageAgeGender({required this.formKey, required this.ageCtrl,
    required this.gender, required this.onGender});
  final GlobalKey<FormState> formKey;
  final TextEditingController ageCtrl;
  final String? gender;
  final ValueChanged<String> onGender;

  @override
  Widget build(BuildContext context) => _Wrap(
    title: '年齢と性別を\n教えてください',
    child: Form(key: formKey, child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      AppTextField(
        controller: ageCtrl, label: '年齢（歳）',
        keyboardType: TextInputType.number, textInputAction: TextInputAction.done,
        validator: (v) {
          if (v == null || v.trim().isEmpty) return '年齢を入力してください';
          final n = int.tryParse(v.trim());
          if (n == null || n < 10 || n > 120) return '10〜120の間で入力してください';
          return null;
        },
      ),
      const Gap(24),
      const Text('性別', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const Gap(8),
      FormField<String>(
        initialValue: gender,
        validator: (v) => v == null ? '性別を選択してください' : null,
        builder: (f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (final opt in [('male','男性'),('female','女性'),('other','その他')])
              Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () { onGender(opt.$1); f.didChange(opt.$1); },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: gender == opt.$1 ? AppTheme.primaryGreen.withOpacity(0.1) : Colors.grey.shade50,
                      border: Border.all(
                        color: gender == opt.$1 ? AppTheme.primaryGreen : Colors.grey.shade300,
                        width: gender == opt.$1 ? 2 : 1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text(opt.$2, style: TextStyle(
                      fontSize: 14,
                      fontWeight: gender == opt.$1 ? FontWeight.w600 : FontWeight.normal,
                      color: gender == opt.$1 ? AppTheme.primaryGreen : Colors.black87,
                    ))),
                  ),
                ),
              )),
          ]),
          if (f.hasError) ...[const Gap(8),
            Text(f.errorText!, style: TextStyle(color: AppTheme.errorColor, fontSize: 12))],
        ]),
      ),
    ])),
  );
}

// ─── Step 2: 身体情報 ─────────────────────────
class _PageBody extends StatelessWidget {
  const _PageBody({required this.formKey, required this.heightCtrl,
    required this.weightCtrl, required this.goalCtrl});
  final GlobalKey<FormState> formKey;
  final TextEditingController heightCtrl, weightCtrl, goalCtrl;

  Widget _field(TextEditingController c, String lbl, double min, double max,
      {bool req = true, TextInputAction act = TextInputAction.next}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(lbl, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        if (!req) ...[const Gap(6), Text('任意', style: TextStyle(fontSize: 11, color: Colors.grey.shade400))],
      ]),
      const Gap(6),
      AppTextField(
        controller: c, label: '数値を入力',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: act,
        validator: (v) {
          if (!req && (v == null || v.trim().isEmpty)) return null;
          final n = double.tryParse(v ?? '');
          if (n == null || n < min || n > max) return '$min〜${max.toInt()}の間で入力してください';
          return null;
        },
      ),
    ]);

  @override
  Widget build(BuildContext context) => _Wrap(
    title: '身体情報を\n入力してください',
    child: Form(key: formKey, child: Column(children: [
      _field(heightCtrl, '身長 (cm)', 50, 300),
      const Gap(20),
      _field(weightCtrl, '現在の体重 (kg)', 20, 500),
      const Gap(20),
      _field(goalCtrl, '目標体重 (kg)', 20, 500, req: false, act: TextInputAction.done),
    ])),
  );
}

// ─── Step 3: 活動レベル ───────────────────────
class _PageActivity extends StatelessWidget {
  const _PageActivity({required this.formKey, required this.selected, required this.onChanged});
  final GlobalKey<FormState> formKey;
  final String? selected;
  final ValueChanged<String> onChanged;

  static const _opts = [
    ('sedentary','ほぼ座って過ごす','デスクワーク中心'),
    ('light',    '軽い運動をする', '週1〜3回の軽い運動'),
    ('moderate', '適度に運動する', '週3〜5回の運動'),
    ('active',   'よく動く',      '週6〜7回の激しい運動'),
  ];

  @override
  Widget build(BuildContext context) => _Wrap(
    title: '普段の活動量は\nどのくらいですか？',
    child: Form(key: formKey, child: FormField<String>(
      initialValue: selected,
      validator: (v) => v == null ? '活動レベルを選択してください' : null,
      builder: (f) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ..._opts.map((o) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onTap: () { onChanged(o.$1); f.didChange(o.$1); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: selected == o.$1 ? AppTheme.primaryGreen.withOpacity(0.08) : Colors.grey.shade50,
                border: Border.all(
                  color: selected == o.$1 ? AppTheme.primaryGreen : Colors.grey.shade300,
                  width: selected == o.$1 ? 2 : 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.$2, style: TextStyle(
                    fontWeight: selected == o.$1 ? FontWeight.w600 : FontWeight.normal,
                    color: selected == o.$1 ? AppTheme.primaryGreen : Colors.black87)),
                  Text(o.$3, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
                if (selected == o.$1) Icon(Icons.check_circle_rounded, color: AppTheme.primaryGreen, size: 20),
              ]),
            ),
          ),
        )),
        if (f.hasError) Text(f.errorText!, style: TextStyle(color: AppTheme.errorColor, fontSize: 12)),
      ]),
    )),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: AppTheme.errorColor.withOpacity(0.08),
      border: Border.all(color: AppTheme.errorColor.withOpacity(0.4)),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.error_outline_rounded, color: AppTheme.errorColor, size: 18),
      const Gap(10),
      Expanded(child: Text(message, style: TextStyle(fontSize: 12, color: AppTheme.errorColor, height: 1.5))),
    ]),
  );
}
