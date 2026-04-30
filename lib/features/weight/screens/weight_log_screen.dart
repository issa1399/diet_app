// lib/features/weight/screens/weight_log_screen.dart
// 体重記録画面。weight_logs に upsert し、ミッション進捗を更新する。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../../missions/mission_service.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class WeightLogScreen extends StatefulWidget {
  const WeightLogScreen({super.key, this.dateParam});
  final String? dateParam;

  @override
  State<WeightLogScreen> createState() => _WeightLogScreenState();
}

class _WeightLogScreenState extends State<WeightLogScreen> {
  final _formKey    = GlobalKey<FormState>();
  final _weightCtrl = TextEditingController();
  bool    _saving   = false;
  String? _error;

  late final String _date;

  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _date = _resolve(widget.dateParam);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    super.dispose();
  }

  String _resolve(String? p) {
    if (p == null || p.isEmpty) return _today();
    final parts = p.split('-');
    if (parts.length != 3) return _today();
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return _today();
    try {
      DateTime(y, m, d);
      return p;
    } catch (_) {
      return _today();
    }
  }

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _saving = true;
      _error  = null;
    });

    try {
      final user = _db.auth.currentUser;
      if (user == null) throw Exception('未ログイン');

      final weightKg = double.parse(_weightCtrl.text.trim());

      // weight_logs に upsert
      await _db.from('weight_logs').upsert({
        'user_id':  user.id,
        'log_date': _date,
        'weight_kg': weightKg,
      }, onConflict: 'user_id,log_date');

      // daily_logs にも体重を反映
      await _db.from('daily_logs').upsert({
        'user_id':   user.id,
        'log_date':  _date,
        'weight_kg': weightKg,
      }, onConflict: 'user_id,log_date');

      // ミッション進捗を更新（weight_daily / weight_weekly）
      // サイレント実行：失敗しても保存自体を止めない
      await MissionService.onWeightSaved(user.id).catchError((_) {});

      if (mounted) context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = '保存に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('体重を記録'),
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
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ─── 記録日バッジ ────────────────
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryGreen.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 13, color: AppTheme.primaryGreen),
                      const Gap(5),
                      Text(
                        '記録日: $_date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.primaryGreen,
                        ),
                      ),
                    ]),
                  ),

                  const Gap(24),

                  // ─── エラーバナー ────────────────
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppTheme.errorColor.withOpacity(0.08),
                        border: Border.all(
                            color: AppTheme.errorColor.withOpacity(0.4)),
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
                            _error!,
                            style: TextStyle(
                                fontSize: 12, color: AppTheme.errorColor),
                          ),
                        ),
                      ]),
                    ),
                    const Gap(16),
                  ],

                  // ─── 体重入力 ────────────────────
                  const Text(
                    '体重',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const Gap(10),
                  AppTextField(
                    controller: _weightCtrl,
                    label: '例: 65.5',
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    textInputAction: TextInputAction.done,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[0-9.]')),
                    ],
                    onSubmitted: (_) => _save(),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: Align(
                        widthFactor: 1,
                        alignment: Alignment.centerRight,
                        child: Text(
                          'kg',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500),
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return '体重を入力してください';
                      }
                      final n = double.tryParse(v.trim());
                      if (n == null || n < 20 || n > 500) {
                        return '20〜500の範囲で入力してください';
                      }
                      return null;
                    },
                  ),

                  const Gap(36),

                  // ─── 保存ボタン ──────────────────
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
