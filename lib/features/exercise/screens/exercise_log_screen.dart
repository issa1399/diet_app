// lib/features/exercise/screens/exercise_log_screen.dart
//
// 運動記録画面。
// - 運動種類選択（プール / ランニング / ウォーキング / 筋トレ）
// - 時間（分）入力
// - カロリー自動計算（rate × 分）
// - ユーザーが手動修正可能
// - exercise_logs テーブルに保存
//
// exercise_logs テーブル:
//   id uuid PK
//   user_id uuid FK
//   log_date date
//   exercise_type text
//   duration_min int
//   burned_kcal int
//   created_at timestamptz

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:diet_app/theme/app_theme.dart';

import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

// ─────────────────────────────────────────────
// 運動種別（種類・ラベル・アイコン・kcal/分）
// ─────────────────────────────────────────────
enum ExerciseType {
  pool     ('pool',     'プール',       Icons.pool_outlined,               8),
  running  ('running',  'ランニング',   Icons.directions_run_outlined,    10),
  walking  ('walking',  'ウォーキング', Icons.directions_walk_outlined,    4),
  strength ('strength', '筋トレ',       Icons.fitness_center_outlined,     6);

  const ExerciseType(this.value, this.label, this.icon, this.kcalPerMin);
  final String   value;
  final String   label;
  final IconData icon;
  final int      kcalPerMin; // kcal/分
}

// ─────────────────────────────────────────────
// ExerciseLogScreen
// ─────────────────────────────────────────────
class ExerciseLogScreen extends StatefulWidget {
  const ExerciseLogScreen({super.key, this.dateParam});
  final String? dateParam;

  @override
  State<ExerciseLogScreen> createState() => _ExerciseLogScreenState();
}

class _ExerciseLogScreenState extends State<ExerciseLogScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _minCtrl   = TextEditingController();
  final _kcalCtrl  = TextEditingController();

  ExerciseType _type        = ExerciseType.running;
  bool         _saving      = false;
  String?      _error;
  bool         _manualKcal  = false; // ユーザーが手動編集したか

  late final String _date;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _date = _resolve(widget.dateParam);
    _minCtrl.addListener(_onMinChanged);
  }

  @override
  void dispose() {
    _minCtrl.removeListener(_onMinChanged);
    _minCtrl.dispose();
    _kcalCtrl.dispose();
    super.dispose();
  }

  // ─── 日付解決 ──────────────────────────────
  String _resolve(String? p) {
    if (p == null || p.isEmpty) return _today();
    final parts = p.split('-');
    if (parts.length != 3) return _today();
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return _today();
    try { DateTime(y, m, d); return p; } catch (_) { return _today(); }
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-'
        '${n.day.toString().padLeft(2,'0')}';
  }

  // ─── 分が変わったらカロリー自動計算 ──────────
  void _onMinChanged() {
    if (_manualKcal) return;
    final min = int.tryParse(_minCtrl.text.trim());
    if (min != null && min > 0) {
      _kcalCtrl.text = '${_type.kcalPerMin * min}';
    } else {
      _kcalCtrl.clear();
    }
  }

  // ─── 運動種別変更時も再計算 ─────────────────
  void _onTypeChanged(ExerciseType t) {
    setState(() { _type = t; _manualKcal = false; });
    _onMinChanged(); // 分が入力済みなら再計算
  }

  // ─── 保存 ───────────────────────────────────
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() { _saving = true; _error = null; });

    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('未ログイン');

      final min  = int.parse(_minCtrl.text.trim());
      final kcal = int.tryParse(_kcalCtrl.text.trim())
          ?? (_type.kcalPerMin * min);

      await _db.from('exercise_logs').insert({
        'user_id':       user.id,
        'log_date':      _date,
        'exercise_type': _type.value,
        'duration_min':  min,
        'burned_kcal':   kcal,
      });

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── build ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('運動を記録'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/home'),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.translucent,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 記録日バッジ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.calendar_today_rounded, size: 13, color: AppTheme.primaryGreen),
                      const Gap(5),
                      Text('記録日: $_date', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
                    ]),
                  ),

                  const Gap(20),

                  // エラーバナー
                  if (_error != null) ...[
                    _ErrorBanner(message: _error!),
                    const Gap(16),
                  ],

                  // ─── 運動種別 ────────────────────
                  const Text('運動の種類', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Gap(10),
                  _ExerciseTypeSelector(selected: _type, onChanged: _onTypeChanged),

                  const Gap(24),

                  // ─── 目安カロリー表示 ────────────
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.lightGreen,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: AppTheme.primaryGreen),
                      const Gap(8),
                      Text('${_type.label}: ${_type.kcalPerMin} kcal/分',
                        style: TextStyle(fontSize: 13, color: AppTheme.primaryGreen,
                            fontWeight: FontWeight.w500)),
                    ]),
                  ),

                  const Gap(24),

                  // ─── 時間（分）────────────────────
                  const Text('時間（分）', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const Gap(10),
                  AppTextField(
                    controller: _minCtrl,
                    label: '例: 30',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Align(
                        widthFactor: 1, alignment: Alignment.centerRight,
                        child: Text('分', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return '時間を入力してください';
                      final n = int.tryParse(v.trim());
                      if (n == null || n <= 0 || n > 600) return '1〜600分の範囲で入力してください';
                      return null;
                    },
                  ),

                  const Gap(24),

                  // ─── 消費カロリー ────────────────
                  Row(children: [
                    const Text('消費カロリー', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () { setState(() => _manualKcal = false); _onMinChanged(); },
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: const Text('再計算', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ]),
                  const Gap(10),
                  AppTextField(
                    controller: _kcalCtrl,
                    label: '自動計算されます',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _save(),
                    onChanged: (_) => setState(() => _manualKcal = true),
                    suffixIcon: _manualKcal
                        ? Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Align(widthFactor: 1, alignment: Alignment.centerRight,
                              child: Text('手動', style: TextStyle(fontSize: 11, color: Colors.orange.shade600))),
                          )
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Align(widthFactor: 1, alignment: Alignment.centerRight,
                              child: Text('kcal', style: TextStyle(fontSize: 13, color: Colors.grey.shade500))),
                          ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'カロリーを入力してください（分を入力すると自動計算されます）';
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 0 || n > 9999) return '0〜9999の範囲で入力してください';
                      return null;
                    },
                  ),

                  const Gap(36),

                  PrimaryButton(
                    text: '記録する',
                    isLoading: _saving,
                    onPressed: _saving ? null : _save,
                  ),
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
// 運動種別セレクター（2×2グリッド）
// ─────────────────────────────────────────────
class _ExerciseTypeSelector extends StatelessWidget {
  const _ExerciseTypeSelector({required this.selected, required this.onChanged});
  final ExerciseType selected;
  final ValueChanged<ExerciseType> onChanged;

  @override
  Widget build(BuildContext context) {
    final types = ExerciseType.values;
    return Column(children: [
      Row(children: [
        _ExerciseChip(type: types[0], selected: selected, onTap: onChanged),
        const Gap(8),
        _ExerciseChip(type: types[1], selected: selected, onTap: onChanged),
      ]),
      const Gap(8),
      Row(children: [
        _ExerciseChip(type: types[2], selected: selected, onTap: onChanged),
        const Gap(8),
        _ExerciseChip(type: types[3], selected: selected, onTap: onChanged),
      ]),
    ]);
  }
}

class _ExerciseChip extends StatelessWidget {
  const _ExerciseChip({required this.type, required this.selected, required this.onTap});
  final ExerciseType type;
  final ExerciseType selected;
  final ValueChanged<ExerciseType> onTap;

  @override
  Widget build(BuildContext context) {
    final on = selected == type;
    return Expanded(child: GestureDetector(
      onTap: () => onTap(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: on ? AppTheme.primaryGreen : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: on ? AppTheme.primaryGreen : Colors.grey.shade300,
            width: on ? 2 : 1,
          ),
        ),
        child: Column(children: [
          Icon(type.icon, size: 24, color: on ? Colors.white : Colors.grey.shade500),
          const Gap(4),
          Text(type.label, style: TextStyle(
            fontSize: 12, fontWeight: on ? FontWeight.w600 : FontWeight.normal,
            color: on ? Colors.white : Colors.black87)),
          Text('${type.kcalPerMin} kcal/分', style: TextStyle(
            fontSize: 10, color: on ? Colors.white70 : Colors.grey.shade400)),
        ]),
      ),
    ));
  }
}

// ─────────────────────────────────────────────
// エラーバナー
// ─────────────────────────────────────────────
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
