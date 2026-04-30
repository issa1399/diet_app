// lib/features/meals/screens/meal_log_screen.dart
// 食事記録画面。食事保存後にミッション進捗（meal_daily / meal_weekly）を更新。

import 'dart:async';
import 'dart:typed_data';
// Web 専用: dart:html を使って input[type=file] を直接操作する
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../../missions/mission_service.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

// ─────────────────────────────────────────────
// カロリー推定マップ
// ─────────────────────────────────────────────
const Map<String, int> _calorieMap = {
  'カレー': 700, 'カレーライス': 700, 'ラーメン': 650, '醤油ラーメン': 620,
  '豚骨ラーメン': 720, '味噌ラーメン': 680, '牛丼': 750, '親子丼': 700,
  'カツ丼': 900, '天丼': 850, 'サラダ': 150, 'シーザーサラダ': 250,
  'サラダチキン': 120, 'おにぎり': 180, 'パスタ': 650, 'ペペロンチーノ': 600,
  'ナポリタン': 620, 'カルボナーラ': 750, '定食': 800, '焼き魚定食': 750,
  '唐揚げ定食': 900, '生姜焼き定食': 850, '唐揚げ': 300, 'ハンバーガー': 500,
  'チーズバーガー': 550, 'フライドポテト': 400, 'ピザ': 600, 'サンドイッチ': 350,
  'たまごサンド': 320, 'BLTサンド': 380, 'チャーハン': 700, '餃子': 250,
  'ステーキ': 600, '焼肉': 700, 'しゃぶしゃぶ': 500, 'すし': 400,
  '寿司': 400, 'うどん': 400, 'そば': 380, 'とんかつ': 700,
  'コロッケ': 250, 'グラタン': 500, 'シチュー': 450, 'カップ麺': 350,
  'ヨーグルト': 100, 'バナナ': 90, 'りんご': 80, 'ケーキ': 350,
  'アイスクリーム': 200, 'チョコレート': 250, 'コーヒー': 10, 'カフェラテ': 150,
};

List<String> _suggest(String q) {
  if (q.trim().isEmpty) return [];
  return _calorieMap.keys
      .where((k) => k.toLowerCase().contains(q.toLowerCase()))
      .take(8)
      .toList();
}

int? _estimate(String name) {
  final n = name.trim();
  if (n.isEmpty) return null;
  if (_calorieMap.containsKey(n)) return _calorieMap[n];
  for (final k in _calorieMap.keys) {
    if (k.contains(n) || n.contains(k)) return _calorieMap[k];
  }
  return null;
}

// ─────────────────────────────────────────────
// 量・食事種別
// ─────────────────────────────────────────────
enum PortionSize {
  small('少なめ', 0.8),
  normal('普通', 1.0),
  large('大盛り', 1.3);

  const PortionSize(this.label, this.mult);
  final String label;
  final double mult;
}

enum MealType {
  breakfast('breakfast', '朝食', Icons.wb_sunny_outlined),
  lunch('lunch', '昼食', Icons.wb_cloudy_outlined),
  dinner('dinner', '夕食', Icons.nights_stay_outlined),
  snack('snack', '間食', Icons.cookie_outlined);

  const MealType(this.value, this.label, this.icon);
  final String value, label;
  final IconData icon;
}

// ─────────────────────────────────────────────
// ポイント計算（時間帯 + 当日判定）
// ─────────────────────────────────────────────
int _calcMealPoint(String mealTypeValue, String targetDate) {
  final today = DateTime.now();
  final todayStr =
      '${today.year}-${today.month.toString().padLeft(2, '0')}-'
      '${today.day.toString().padLeft(2, '0')}';
  if (targetDate != todayStr) return 0;
  final h = today.hour;
  switch (mealTypeValue) {
    case 'breakfast': return (h >= 5 && h < 10) ? 5 : 3;
    case 'lunch':     return (h >= 10 && h < 15) ? 5 : 3;
    case 'dinner':    return (h >= 17 && h < 22) ? 5 : 3;
    case 'snack':     return 3;
    default: return 0;
  }
}

Future<void> _addPoints(SupabaseClient db, String userId, int pts) async {
  if (pts <= 0) return;
  final p = await db
      .from('profiles')
      .select('points, level')
      .eq('id', userId)
      .single();
  int points = (p['points'] as int? ?? 0) + pts;
  int level  = p['level']  as int? ?? 1;
  while (points >= 100) {
    points -= 100;
    level  += 1;
  }
  await db
      .from('profiles')
      .update({'points': points, 'level': level})
      .eq('id', userId);
}

// ─────────────────────────────────────────────
// MealLogScreen
// ─────────────────────────────────────────────
class MealLogScreen extends StatefulWidget {
  const MealLogScreen({super.key, this.dateParam});
  final String? dateParam;

  @override
  State<MealLogScreen> createState() => _MealLogScreenState();
}

class _MealLogScreenState extends State<MealLogScreen> {
  final _formKey   = GlobalKey<FormState>();
  final _nameCtrl  = TextEditingController();
  final _kcalCtrl  = TextEditingController();
  final _memoCtrl  = TextEditingController();
  final _nameFocus = FocusNode();

  MealType    _mealType = MealType.breakfast;
  PortionSize _portion  = PortionSize.normal;
  bool        _saving   = false;
  String?     _error;
  int?        _estKcal;
  bool        _manualKcal  = false;
  bool        _cantEst     = false;
  List<String> _suggestions = [];
  static final List<String> _recent = [];

  // 写真アップロード
  Uint8List? _imageBytes;   // 選択した画像のバイト列
  String?    _imageExt;     // 拡張子 (.jpg / .png 等)
  bool       _uploading = false;

  late final String _date;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _date = _resolve(widget.dateParam);
    _nameCtrl.addListener(_onName);
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_onName);
    _nameCtrl.dispose();
    _kcalCtrl.dispose();
    _memoCtrl.dispose();
    _nameFocus.dispose();
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

  void _onName() {
    final name = _nameCtrl.text;
    setState(() {
      _suggestions = _suggest(name);
      if (!_manualKcal) _recalc(name: name);
    });
  }

  void _recalc({String? name, PortionSize? portion}) {
    final n = name ?? _nameCtrl.text;
    final p = portion ?? _portion;
    final base = _estimate(n);
    if (base != null) {
      _estKcal    = (base * p.mult).round();
      _cantEst    = false;
      _manualKcal = false;
      _kcalCtrl.text = '$_estKcal';
    } else {
      _estKcal  = null;
      _cantEst  = n.trim().isNotEmpty;
      if (_cantEst && !_manualKcal) _kcalCtrl.clear();
    }
  }

  void _onSuggest(String name) {
    _nameCtrl.text = name;
    _nameCtrl.selection =
        TextSelection.collapsed(offset: name.length);
    setState(() {
      _suggestions = [];
      _manualKcal  = false;
    });
    _recalc(name: name);
    _nameFocus.unfocus();
  }

  // ─── 画像選択（Web: input[type=file] を dart:html で操作） ───────
  //
  // image_picker を使わず、ブラウザ標準の FileReader API で
  // Uint8List を取得する。
  // Flutter Web では dart:html が使えるため外部パッケージ不要。
  Future<void> _pickImage() async {
    // input[type=file] 要素を動的に生成してクリック
    final input = html.FileUploadInputElement()
      ..accept = 'image/*'
      ..click();

    // ユーザーがファイルを選択するまで待つ
    await input.onChange.first;

    final file = input.files?.first;
    if (file == null) return;

    // FileReader で Uint8List に変換
    final reader  = html.FileReader();
    final completer = Completer<Uint8List>();

    reader.onLoadEnd.listen((_) {
      final result = reader.result;
      if (result is List<int>) {
        completer.complete(Uint8List.fromList(result));
      } else if (result is String) {
        // 念のため文字列ケースも処理
        completer.completeError('Unexpected string result');
      }
    });
    reader.onError.listen((e) => completer.completeError(e));
    reader.readAsArrayBuffer(file);

    final bytes = await completer.future;

    // 拡張子を取り出す（デフォルト .jpg）
    final name = file.name;
    final ext  = name.contains('.')
        ? '.${name.split('.').last.toLowerCase()}'
        : '.jpg';

    if (mounted) {
      setState(() {
        _imageBytes = bytes;
        _imageExt   = ext;
      });
    }
  }

  // ─── Storage にアップロード → public URL を返す ──
  Future<String?> _uploadImage(String userId) async {
    if (_imageBytes == null) return null;
    final ts   = DateTime.now().millisecondsSinceEpoch;
    final path = '$userId/$ts${_imageExt ?? '.jpg'}';
    await _db.storage
        .from('meal-images')
        .uploadBinary(
          path,
          _imageBytes!,
          fileOptions: const FileOptions(upsert: true),
        );
    return _db.storage.from('meal-images').getPublicUrl(path);
  }

  // ─── 保存 ───────────────────────────────────
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

      final kcal = int.tryParse(_kcalCtrl.text.trim());
      if (kcal == null) throw Exception('カロリーが不正です');

      // daily_logs を upsert して id を取得
      final logR = await _db
          .from('daily_logs')
          .upsert(
            {'user_id': user.id, 'log_date': _date},
            onConflict: 'user_id,log_date',
          )
          .select('id')
          .single();

      // memo 組み立て
      final namePart = _nameCtrl.text.trim();
      final memoStr = [
        if (namePart.isNotEmpty) '$namePart (${_portion.label})',
        if (_memoCtrl.text.trim().isNotEmpty) _memoCtrl.text.trim(),
      ].join(' / ');

      // 画像を Storage にアップロード（ある場合のみ）
      setState(() => _uploading = true);
      String? imageUrl;
      try {
        imageUrl = await _uploadImage(user.id);
      } catch (_) {
        // アップロード失敗は無視して保存継続
      } finally {
        if (mounted) setState(() => _uploading = false);
      }

      // meal_records に insert
      await _db.from('meal_records').insert({
        'user_id':            user.id,
        'daily_log_id':       logR['id'],
        'meal_type':          _mealType.value,
        'user_kcal_override': kcal,
        'analysis_status':    'pending',
        if (memoStr.isNotEmpty) 'ai_dish_names': [memoStr],
        if (imageUrl != null) 'image_url': imageUrl,
      });

      // 時間帯ポイントを付与
      final pts = _calcMealPoint(_mealType.value, _date);
      if (pts > 0) await _addPoints(_db, user.id, pts);

      // ミッション進捗を更新（meal_daily / meal_weekly）
      // サイレント実行：失敗しても保存自体を止めない
      await MissionService.onMealSaved(user.id).catchError((_) {});

      // 最近使った食事名を記録
      if (namePart.isNotEmpty) {
        _recent.remove(namePart);
        _recent.insert(0, namePart);
        if (_recent.length > 10) _recent.removeLast();
      }

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
        title: const Text('食事を記録'),
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
          onTap: () {
            FocusScope.of(context).unfocus();
            setState(() => _suggestions = []);
          },
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

                  const Gap(20),

                  // エラーバナー
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
                        ],
                      ),
                    ),
                    const Gap(16),
                  ],

                  // 食事種別
                  const _Label('食事の種類'),
                  const Gap(10),
                  _MealTypeSelector(
                    selected:  _mealType,
                    onChanged: (t) => setState(() => _mealType = t),
                  ),

                  const Gap(24),

                  // 食事名
                  const _Label('食事名'),
                  const Gap(10),
                  AppTextField(
                    controller: _nameCtrl,
                    label: '例: カレー、ラーメン',
                    focusNode: _nameFocus,
                    textInputAction: TextInputAction.next,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? '食事名を入力してください'
                        : null,
                  ),

                  if (_suggestions.isNotEmpty) ...[
                    const Gap(6),
                    _SuggestList(
                        items: _suggestions, onTap: _onSuggest),
                  ],

                  if (_suggestions.isEmpty &&
                      _nameCtrl.text.trim().isEmpty &&
                      _recent.isNotEmpty) ...[
                    const Gap(8),
                    _RecentList(names: _recent, onTap: _onSuggest),
                  ],

                  const Gap(24),

                  // 量
                  const _Label('量'),
                  const Gap(10),
                  _PortionSelector(
                    selected: _portion,
                    onChanged: (p) {
                      setState(() {
                        _portion    = p;
                        _manualKcal = false;
                      });
                      _recalc(portion: p);
                    },
                  ),

                  const Gap(24),

                  // カロリー
                  Row(children: [
                    const _Label('カロリー'),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => _manualKcal = false);
                        _recalc();
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 15),
                      label: const Text('再計算',
                          style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.primaryGreen,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ]),

                  if (_cantEst) ...[
                    const Gap(4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        border:
                            Border.all(color: Colors.orange.shade200),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '推定できません。カロリーを直接入力してください。',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800),
                      ),
                    ),
                  ],

                  if (_estKcal != null && !_manualKcal) ...[
                    const Gap(4),
                    Row(children: [
                      Icon(Icons.auto_awesome_rounded,
                          size: 13, color: AppTheme.midGreen),
                      const Gap(4),
                      Text(
                        '${_nameCtrl.text.trim()} (${_portion.label}) '
                        '→ $_estKcal kcal',
                        style: TextStyle(
                            fontSize: 11, color: AppTheme.midGreen),
                      ),
                    ]),
                  ],

                  const Gap(8),
                  AppTextField(
                    controller: _kcalCtrl,
                    label: 'kcal',
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly
                    ],
                    onChanged: (_) =>
                        setState(() => _manualKcal = true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'カロリーを入力してください';
                      }
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 0 || n > 9999) {
                        return '0〜9999の範囲で入力してください';
                      }
                      return null;
                    },
                  ),

                  const Gap(24),

                  // メモ（任意）
                  const _Label('メモ', required: false),
                  const Gap(10),
                  AppTextField(
                    controller: _memoCtrl,
                    label: '追記メモ（任意）',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),

                  const Gap(24),

                  // ─── 写真（任意） ────────────────
                  const _Label('写真', required: false),
                  const Gap(10),
                  _ImagePicker(
                    imageBytes: _imageBytes,
                    onPick:     _pickImage,
                    onClear:    () => setState(() { _imageBytes = null; _imageExt = null; }),
                  ),

                  const Gap(36),

                  PrimaryButton(
                    text: _uploading ? '写真をアップロード中...' : '記録する',
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

// ─── 小部品 ───────────────────────────────────
class _Label extends StatelessWidget {
  const _Label(this.text, {this.required = true});
  final String text;
  final bool required;

  @override
  Widget build(BuildContext context) => Row(children: [
    Text(text,
        style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black87)),
    if (!required) ...[
      const Gap(6),
      Text('任意',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
    ],
  ]);
}

class _MealTypeSelector extends StatelessWidget {
  const _MealTypeSelector(
      {required this.selected, required this.onChanged});
  final MealType selected;
  final ValueChanged<MealType> onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(children: MealType.values.map((t) {
        final on = selected == t;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onChanged(t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: on ? AppTheme.primaryGreen : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: on
                        ? AppTheme.primaryGreen
                        : Colors.grey.shade300,
                    width: on ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  Icon(t.icon,
                      size: 18,
                      color: on ? Colors.white : Colors.grey.shade500),
                  const Gap(3),
                  Text(t.label,
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: on
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: on
                              ? Colors.white
                              : Colors.grey.shade600)),
                ]),
              ),
            ),
          ),
        );
      }).toList());
}

class _PortionSelector extends StatelessWidget {
  const _PortionSelector(
      {required this.selected, required this.onChanged});
  final PortionSize selected;
  final ValueChanged<PortionSize> onChanged;

  @override
  Widget build(BuildContext context) =>
      Row(children: PortionSize.values.map((p) {
        final on = selected == p;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: GestureDetector(
              onTap: () => onChanged(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: on ? AppTheme.primaryGreen : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: on
                        ? AppTheme.primaryGreen
                        : Colors.grey.shade300,
                    width: on ? 2 : 1,
                  ),
                ),
                child: Column(children: [
                  Text(p.label,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: on
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: on ? Colors.white : Colors.black87)),
                  Text('×${p.mult}',
                      style: TextStyle(
                          fontSize: 10,
                          color: on
                              ? Colors.white70
                              : Colors.grey.shade500)),
                ]),
              ),
            ),
          ),
        );
      }).toList());
}

class _SuggestList extends StatelessWidget {
  const _SuggestList({required this.items, required this.onTap});
  final List<String> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: items.asMap().entries.map((e) {
        final isLast = e.key == items.length - 1;
        return InkWell(
          onTap: () => onTap(e.value),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              border: isLast
                  ? null
                  : Border(
                      bottom:
                          BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(children: [
              Icon(Icons.restaurant_outlined,
                  size: 15, color: Colors.grey.shade400),
              const Gap(10),
              Text(e.value, style: const TextStyle(fontSize: 13)),
              const Spacer(),
              Text(
                '${_calorieMap[e.value] ?? "?"}kcal',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
          ),
        );
      }).toList(),
    ),
  );
}

class _RecentList extends StatelessWidget {
  const _RecentList({required this.names, required this.onTap});
  final List<String> names;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('最近の記録',
          style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade500,
              fontWeight: FontWeight.w500)),
      const Gap(6),
      Wrap(
        spacing: 8,
        runSpacing: 6,
        children: names
            .map((n) => GestureDetector(
                  onTap: () => onTap(n),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border:
                          Border.all(color: Colors.grey.shade200),
                    ),
                    child: Text(n,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700)),
                  ),
                ))
            .toList(),
      ),
    ],
  );
}

// ─────────────────────────────────────────────
// 写真選択ウィジェット
// ─────────────────────────────────────────────
class _ImagePicker extends StatelessWidget {
  const _ImagePicker({
    required this.imageBytes,
    required this.onPick,
    required this.onClear,
  });

  final Uint8List?    imageBytes;
  final VoidCallback  onPick;
  final VoidCallback  onClear;

  @override
  Widget build(BuildContext context) {
    // 未選択時 → 点線ボタン
    if (imageBytes == null) {
      return GestureDetector(
        onTap: onPick,
        child: Container(
          height: 140,
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey.shade300,
              style: BorderStyle.solid,
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add_photo_alternate_outlined,
                  size: 36, color: Colors.grey.shade400),
              const Gap(8),
              Text('タップして写真を選択',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const Gap(4),
              Text('（任意）',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ],
          ),
        ),
      );
    }

    // 選択済み → プレビュー + 削除ボタン + 変更ボタン
    return Stack(
      children: [
        // プレビュー画像
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: 200,
            child: Image.memory(
              imageBytes!,
              fit: BoxFit.cover,
            ),
          ),
        ),
        // 右上: 削除ボタン
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: onClear,
            child: Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
        // 左下: 変更ボタン
        Positioned(
          bottom: 8,
          left: 8,
          child: GestureDetector(
            onTap: onPick,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.edit_outlined,
                    color: Colors.white, size: 14),
                const Gap(4),
                const Text('変更',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}
