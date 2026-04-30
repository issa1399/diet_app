// lib/features/home/screens/home_screen.dart
// ホーム画面 + プロフィール / 体重 / フレンド / ポイント / カレンダー / 食事一覧

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../../../features/missions/mission_service.dart';
import '../../../shared/widgets/primary_button.dart';

SupabaseClient get _db => Supabase.instance.client;

String _ds(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
bool _same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String _mealLabel(String? v) => switch(v) {
  'breakfast'=>'朝食','lunch'=>'昼食','dinner'=>'夕食','snack'=>'間食',_=>v??''};
IconData _mealIcon(String? v) => switch(v) {
  'breakfast'=>Icons.wb_sunny_outlined,'lunch'=>Icons.wb_cloudy_outlined,
  'dinner'=>Icons.nights_stay_outlined,'snack'=>Icons.cookie_outlined,
  _=>Icons.restaurant_outlined};

// ─────────────────────────────────────────────
// ログインボーナス処理
// ─────────────────────────────────────────────
Future<void> _processLoginBonus(String userId) async {
  final today = _ds(DateTime.now());
  final p = await _db.from('profiles')
      .select('last_login_date, login_streak, points, level')
      .eq('id', userId).single();

  final lastLogin = p['last_login_date'] as String?;
  if (lastLogin == today) return; // 今日すでに処理済み

  int streak = p['login_streak'] as int? ?? 0;
  final yesterday = _ds(DateTime.now().subtract(const Duration(days: 1)));
  streak = (lastLogin == yesterday) ? streak + 1 : 1;

  // ボーナスポイント: 基本1 + 連続ボーナス最大+5
  final bonus = 1 + (streak - 1).clamp(0, 5);

  int points = (p['points'] as int? ?? 0) + bonus;
  int level  = p['level']  as int? ?? 1;
  while (points >= 100) { points -= 100; level += 1; }

  // ミッション進捗更新（ログイン）
  await MissionService.onLogin(userId).catchError((_) {});

  await _db.from('profiles').update({
    'last_login_date': today,
    'login_streak':    streak,
    'points':          points,
    'level':           level,
  }).eq('id', userId);
}

// ─────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final Future<Map<String, dynamic>?> _profileFuture;
  late final Future<Map<String, dynamic>?> _latestWeightFuture;
  late final Future<List<Map<String,dynamic>>> _weightLogsFuture;

  final DateTime _today = DateTime.now();
  late DateTime _month;
  late DateTime _selected;
  late Future<List<Map<String,dynamic>>> _mealsFuture;
  late Future<Set<String>> _marksFuture;
  late Future<_CalorieData?> _calorieFuture;
  late Future<List<Map<String,dynamic>>> _exerciseFuture;

  @override
  void initState() {
    super.initState();
    _month    = DateTime(_today.year, _today.month);
    _selected = _today;
    _profileFuture      = _fetchProfile();
    _latestWeightFuture = _fetchLatestWeight();
    _weightLogsFuture   = _fetchWeightLogs();
    _mealsFuture   = _fetchMeals(_selected);
    _marksFuture   = _fetchMarks(_month);
    _calorieFuture  = _fetchCalorieData(_selected);
    _exerciseFuture = _fetchExercise(_selected);

    // ログインボーナス（非同期・エラーは無視）
    final uid = _db.auth.currentUser?.id;
    if (uid != null) _processLoginBonus(uid).catchError((_) {});
  }

  Future<Map<String, dynamic>?> _fetchProfile() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    return _db.from('profiles')
        .select('nickname, level, points, age, gender, height_cm, '
            'initial_weight_kg, goal_weight_kg, activity_level, onboarding_completed')
        .eq('id', user.id).maybeSingle();
  }

  Future<Map<String, dynamic>?> _fetchLatestWeight() async {
    final user = _db.auth.currentUser;
    if (user == null) return null;
    return _db.from('weight_logs')
        .select('weight_kg, log_date')
        .eq('user_id', user.id)
        .order('log_date', ascending: false)
        .limit(1)
        .maybeSingle();
  }


  Future<List<Map<String,dynamic>>> _fetchWeightLogs() async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final since = DateTime.now().subtract(const Duration(days: 30));
    final sinceStr = '${since.year}-${since.month.toString().padLeft(2,'0')}-${since.day.toString().padLeft(2,'0')}';
    final rows = await _db
        .from('weight_logs')
        .select('log_date, weight_kg')
        .eq('user_id', user.id)
        .gte('log_date', sinceStr)
        .order('log_date', ascending: true);
    return List<Map<String,dynamic>>.from(rows as List);
  }

  Future<List<Map<String,dynamic>>> _fetchMeals(DateTime date) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final log = await _db.from('daily_logs').select('id')
        .eq('user_id', user.id).eq('log_date', _ds(date)).maybeSingle();
    if (log == null) return [];
    final recs = await _db.from('meal_records')
        .select('id, meal_type, ai_dish_names, user_kcal_override, created_at')
        .eq('daily_log_id', log['id'] as String)
        .eq('user_id', user.id)
        .order('created_at', ascending: true);
    return List<Map<String,dynamic>>.from(recs as List);
  }

  Future<Set<String>> _fetchMarks(DateTime month) async {
    final user = _db.auth.currentUser;
    if (user == null) return {};
    final first = _ds(DateTime(month.year, month.month, 1));
    final last  = _ds(DateTime(month.year, month.month + 1, 0));
    final rows = await _db.from('daily_logs')
        .select('log_date, meal_records!inner(id)')
        .eq('user_id', user.id)
        .gte('log_date', first).lte('log_date', last);
    return {for (final r in rows as List) if (r['log_date'] != null) r['log_date'] as String};
  }



  // ─── 運動ログ取得 ─────────────────────────────
  Future<List<Map<String,dynamic>>> _fetchExercise(DateTime date) async {
    final user = _db.auth.currentUser;
    if (user == null) return [];
    final rows = await _db.from('exercise_logs')
        .select('exercise_type, duration_min, burned_kcal')
        .eq('user_id', user.id)
        .eq('log_date', _ds(date))
        .order('created_at', ascending: true);
    return List<Map<String,dynamic>>.from(rows as List);
  }

  // ─── カロリー損益データ取得 ─────────────────
  // 摂取カロリー: 選択日の meal_records.user_kcal_override 合計
  // 消費カロリー: BMR × 活動係数（Mifflin-St Jeor 式）
  Future<_CalorieData?> _fetchCalorieData(DateTime date) async {
    final user = _db.auth.currentUser;
    if (user == null) return null;

    // プロフィールと最新体重を並行取得
    final profileRes = await _db.from('profiles')
        .select('age, gender, height_cm, initial_weight_kg, activity_level')
        .eq('id', user.id)
        .maybeSingle();

    if (profileRes == null) return null;

    // 体重は weight_logs の最新値を優先、なければ initial_weight_kg を使う
    final wLog = await _db.from('weight_logs')
        .select('weight_kg')
        .eq('user_id', user.id)
        .order('log_date', ascending: false)
        .limit(1)
        .maybeSingle();

    final weightKg = (wLog?['weight_kg'] as num?)?.toDouble()
        ?? (profileRes['initial_weight_kg'] as num?)?.toDouble()
        ?? 60.0;

    final age      = (profileRes['age']       as num?)?.toDouble() ?? 30;
    final heightCm = (profileRes['height_cm'] as num?)?.toDouble() ?? 165;
    final gender   = profileRes['gender'] as String? ?? 'other';
    final activity = profileRes['activity_level'] as String? ?? 'sedentary';

    // BMR（Mifflin-St Jeor 式）
    final bmr = gender == 'male'
        ? 10 * weightKg + 6.25 * heightCm - 5 * age + 5
        : 10 * weightKg + 6.25 * heightCm - 5 * age - 161;

    // TDEE（活動係数をかける）
    final activityFactor = switch (activity) {
      'sedentary' => 1.2,
      'light'     => 1.375,
      'moderate'  => 1.55,
      'active'    => 1.725,
      _           => 1.2,
    };
    final tdee = (bmr * activityFactor).round();

    // 摂取カロリーを daily_logs → meal_records から集計
    final log = await _db.from('daily_logs').select('id')
        .eq('user_id', user.id).eq('log_date', _ds(date)).maybeSingle();

    int intakeKcal = 0;
    if (log != null) {
      final meals = await _db.from('meal_records')
          .select('user_kcal_override')
          .eq('daily_log_id', log['id'] as String)
          .eq('user_id', user.id);
      intakeKcal = (meals as List).fold(0,
          (sum, m) => sum + ((m['user_kcal_override'] as int?) ?? 0));
    }

    // 運動消費カロリーを exercise_logs から取得
    int exerciseKcal = 0;
    try {
      final exRows = await _db.from('exercise_logs')
          .select('burned_kcal')
          .eq('user_id', user.id)
          .eq('log_date', _ds(date));
      exerciseKcal = (exRows as List).fold(0,
          (sum, e) => sum + ((e['burned_kcal'] as int?) ?? 0));
    } catch (_) {}

    return _CalorieData(intake: intakeKcal, bmr: bmr.round(), exercise: exerciseKcal, tdee: tdee);
  }

  void _onDay(DateTime d) => setState(() {
    _selected       = d;
    _mealsFuture    = _fetchMeals(d);
    _calorieFuture  = _fetchCalorieData(d);
    _exerciseFuture = _fetchExercise(d);
  });
  void _prev() => setState(() { _month = DateTime(_month.year, _month.month - 1); _marksFuture = _fetchMarks(_month); });
  void _next() => setState(() { _month = DateTime(_month.year, _month.month + 1); _marksFuture = _fetchMarks(_month); });
  void _refresh() => setState(() {
    _mealsFuture   = _fetchMeals(_selected);
    _marksFuture   = _fetchMarks(_month);
    _calorieFuture  = _fetchCalorieData(_selected);
    _exerciseFuture = _fetchExercise(_selected);
  });
  Future<void> _signOut() async => _db.auth.signOut();

  void _showProfile(Map<String,dynamic> p) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ProfileSheet(profile: p),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ホーム'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), tooltip: '更新', onPressed: _refresh),
          IconButton(icon: const Icon(Icons.people), tooltip: 'フレンド', onPressed: () => context.go('/friends')),
          // プロフィールアイコン
          FutureBuilder<Map<String,dynamic>?>(
            future: _profileFuture,
            builder: (_, snap) {
              final p = snap.data;
              final nick = (p?['nickname'] as String?)?.trim();
              final initial = (nick != null && nick.isNotEmpty) ? nick[0].toUpperCase() : '?';
              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: p != null ? () => _showProfile(p) : null,
                  child: Stack(clipBehavior: Clip.none, children: [
                    CircleAvatar(
                      radius: 17,
                      backgroundColor: AppTheme.lightGreen,
                      child: Text(initial, style: TextStyle(color: AppTheme.primaryGreen, fontWeight: FontWeight.w700, fontSize: 14)),
                    ),
                    // ポイント表示バッジ
                    if (p != null)
                      Positioned(
                        right: -4, bottom: -4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryGreen,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${(p['points'] as int? ?? 0)}',
                            style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.w700)),
                        ),
                      ),
                  ]),
                ),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'ログアウト', onPressed: _signOut),
        ],
      ),
      body: FutureBuilder<Map<String,dynamic>?>(
        future: _profileFuture,
        builder: (_, profSnap) {
          if (profSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = profSnap.data;
          final onboarded = profile?['onboarding_completed'] as bool? ?? false;

          return SafeArea(child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16,16,16,32),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

              // ─── ニックネーム / レベル / ポイント ──
              if (profile != null) ...[
                _UserStatusBar(profile: profile),
                const Gap(16),
              ],

              // ─── 最新体重 ────────────────────────
              _LatestWeightCard(future: _latestWeightFuture),

              // ─── 体重推移グラフ ───────────────────
              _WeightChartCard(future: _weightLogsFuture),
              const Gap(16),
              FutureBuilder<Set<String>>(
                future: _marksFuture,
                builder: (_, snap) => _Calendar(
                  month: _month, selected: _selected, today: _today,
                  marks: snap.data ?? {},
                  onPrev: _prev, onNext: _next, onTap: _onDay,
                ),
              ),
              const Gap(16),

              // ─── カロリー損益カード ──────────────
              _CalorieBalanceCard(future: _calorieFuture),
              const Gap(16),

              // ─── 運動目安カード ───────────────────
              _ExerciseSuggestionCard(future: _calorieFuture),
              const Gap(16),

              // ─── 運動一覧 ──────────────────────────
              _ExerciseSection(future: _exerciseFuture, selected: _selected),
              const Gap(16),

              // ─── 選択日セクション ────────────────
              _DaySection(selected: _selected, today: _today, mealsFuture: _mealsFuture),
              const Gap(16),

              // ─── アクションボタン群 ──────────────
              Row(children: [
                Expanded(child: _ActionBtn(
                  icon: Icons.monitor_weight_outlined,
                  label: '体重記録',
                  onTap: () => context.go('/weight/new?date=${_ds(_selected)}'),
                )),
                const Gap(8),
                Expanded(child: _ActionBtn(
                  icon: Icons.directions_run_rounded,
                  label: '運動記録',
                  onTap: () => context.go('/exercise/new?date=${_ds(_selected)}'),
                )),
                const Gap(8),
                Expanded(child: _ActionBtn(
                  icon: Icons.emoji_events_rounded,
                  label: 'ミッション',
                  onTap: () => context.go('/missions'),
                )),
                const Gap(8),
                Expanded(child: _ActionBtn(
                  icon: Icons.people_outline_rounded,
                  label: 'フレンド',
                  onTap: () => context.go('/friends'),
                )),
              ]),
              const Gap(24),

              // ─── プロフィール（未登録時） ─────────
              if (profile == null || !onboarded) ...[
                Text('プロフィールを登録して\n努力を記録しよう',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
                const Gap(8),
                Text('まずはあなたの基本情報を入力してください',
                  style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const Gap(24),
                PrimaryButton(text: 'プロフィールを登録する', onPressed: () => context.go('/onboarding')),
              ],
            ]),
          ));
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// ユーザーステータスバー
// ─────────────────────────────────────────────
class _UserStatusBar extends StatelessWidget {
  const _UserStatusBar({required this.profile});
  final Map<String,dynamic> profile;
  @override
  Widget build(BuildContext context) {
    final nick    = (profile['nickname'] as String?)?.trim();
    final level   = profile['level']  as int? ?? 1;
    final points  = profile['points'] as int? ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [AppTheme.primaryGreen, AppTheme.midGreen]),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nick?.isNotEmpty == true ? nick! : '名前未設定',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
          const Gap(2),
          Text('Lv.$level', style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ])),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('$points pt', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          const Gap(2),
          SizedBox(
            width: 100, height: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: points / 100.0,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ),
          const Gap(2),
          Text('次のレベルまで ${100 - points} pt', style: const TextStyle(fontSize: 10, color: Colors.white70)),
        ]),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// プロフィールシート
// ─────────────────────────────────────────────
class _ProfileSheet extends StatelessWidget {
  const _ProfileSheet({required this.profile});
  final Map<String,dynamic> profile;

  String _activity(String? v) => switch(v) {
    'sedentary'=>'ほぼ座って過ごす','light'=>'軽い運動','moderate'=>'適度に運動','active'=>'よく動く',_=>'未設定'};
  String _gender(String? v) => switch(v) {'male'=>'男性','female'=>'女性','other'=>'その他',_=>'未設定'};

  @override
  Widget build(BuildContext context) {
    String val(String k, {String s=''}) { final v = profile[k]; return v==null?'未設定':'$v$s'; }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)))),
        const Gap(16),
        Text('プロフィール', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        const Gap(16),
        _PRow('ニックネーム', val('nickname')),
        _PRow('レベル', 'Lv.${profile['level'] ?? 1}'),
        _PRow('ポイント', '${profile['points'] ?? 0} pt'),
        _PRow('年齢', val('age', s: '歳')),
        _PRow('性別', _gender(profile['gender'] as String?)),
        _PRow('身長', val('height_cm', s: ' cm')),
        _PRow('体重', val('initial_weight_kg', s: ' kg')),
        _PRow('目標体重', val('goal_weight_kg', s: ' kg')),
        _PRow('活動レベル', _activity(profile['activity_level'] as String?)),
      ]),
    );
  }
}

class _PRow extends StatelessWidget {
  const _PRow(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
      Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
    ]),
  );
}

// ─────────────────────────────────────────────
// アクションボタン
// ─────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  const _ActionBtn({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.primaryGreen.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.25)),
      ),
      child: Column(children: [
        Icon(icon, size: 22, color: AppTheme.primaryGreen),
        const Gap(4),
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
      ]),
    ),
  );
}

// ─────────────────────────────────────────────
// 選択日セクション（ボタン + 食事一覧）
// ─────────────────────────────────────────────
class _DaySection extends StatelessWidget {
  const _DaySection({required this.selected, required this.today, required this.mealsFuture});
  final DateTime selected, today;
  final Future<List<Map<String,dynamic>>> mealsFuture;

  @override
  Widget build(BuildContext context) {
    final dateStr = _ds(selected);
    final isToday = _same(selected, today);
    final isFuture = selected.isAfter(DateTime(today.year, today.month, today.day));

    return Column(children: [
      // ヘッダー
      Container(
        padding: const EdgeInsets.fromLTRB(14,12,14,12),
        decoration: BoxDecoration(
          color: AppTheme.primaryGreen.withOpacity(0.06),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_rounded, size: 15, color: AppTheme.primaryGreen),
          const Gap(7),
          Text(isToday ? '今日 ($dateStr)' : dateStr,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
          const Spacer(),
          if (!isFuture) GestureDetector(
            onTap: () => context.go('/meals/new?date=$dateStr'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: AppTheme.primaryGreen, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 14, color: Colors.white),
                Gap(4),
                Text('食事を記録', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
          if (isFuture) Text('未来の日付', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
        ]),
      ),
      // 食事一覧
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
          border: Border(
            left: BorderSide(color: AppTheme.primaryGreen.withOpacity(0.2)),
            right: BorderSide(color: AppTheme.primaryGreen.withOpacity(0.2)),
            bottom: BorderSide(color: AppTheme.primaryGreen.withOpacity(0.2)),
          ),
        ),
        child: FutureBuilder<List<Map<String,dynamic>>>(
          future: mealsFuture,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))));
            }
            if (snap.hasError) return Padding(
              padding: const EdgeInsets.all(16),
              child: Text('取得に失敗しました', style: TextStyle(fontSize: 12, color: AppTheme.errorColor)));

            final meals = snap.data ?? [];
            if (meals.isEmpty) return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Center(child: Column(children: [
                Icon(Icons.restaurant_outlined, size: 28, color: Colors.grey.shade300),
                const Gap(8),
                Text('まだ記録がありません', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
              ])),
            );

            final total = meals.fold<int>(0, (s, m) => s + ((m['user_kcal_override'] as int?) ?? 0));
            return Column(children: [
              ...meals.map((m) {
                final type     = m['meal_type'] as String?;
                final kcal     = m['user_kcal_override'] as int?;
                final names    = m['ai_dish_names'];
                final memo     = names is List && names.isNotEmpty ? names.first as String : null;
                return Column(children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11), child: Row(children: [
                    Container(width:34, height:34,
                      decoration: BoxDecoration(color: AppTheme.primaryGreen.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                      child: Icon(_mealIcon(type), size: 17, color: AppTheme.primaryGreen)),
                    const Gap(12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(memo ?? '（メモなし）', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                        color: memo != null ? Colors.black87 : Colors.grey.shade400), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const Gap(2),
                      Text(_mealLabel(type), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ])),
                    const Gap(8),
                    Text(kcal != null ? '$kcal kcal' : '- kcal',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                        color: kcal != null ? Colors.black87 : Colors.grey.shade400)),
                  ])),
                  Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
                ]);
              }),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreen.withOpacity(0.06),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('合計カロリー', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
                  Text('$total kcal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppTheme.primaryGreen)),
                ]),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// カレンダー
// ─────────────────────────────────────────────
class _Calendar extends StatelessWidget {
  const _Calendar({required this.month, required this.selected, required this.today,
    required this.marks, required this.onPrev, required this.onNext, required this.onTap});
  final DateTime month, selected, today;
  final Set<String> marks;
  final VoidCallback onPrev, onNext;
  final ValueChanged<DateTime> onTap;

  int _dim(DateTime m) => DateTime(m.year, m.month + 1, 0).day;
  int _fw(DateTime m)  => DateTime(m.year, m.month, 1).weekday % 7;
  static const _days = ['日','月','火','水','木','金','土'];

  @override
  Widget build(BuildContext context) {
    final dim = _dim(month); final fw = _fw(month);
    final rows = ((fw + dim) / 7).ceil();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0,2))],
      ),
      child: Column(children: [
        // ヘッダー
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10), child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: onPrev, visualDensity: VisualDensity.compact),
            Text('${month.year}年${month.month}月', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: onNext, visualDensity: VisualDensity.compact),
          ],
        )),
        // 曜日
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Row(
          children: _days.asMap().entries.map((e) => Expanded(child: Center(child: Text(e.value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
              color: e.key == 0 ? Colors.red.shade400 : e.key == 6 ? Colors.blue.shade400 : Colors.grey.shade500))))).toList(),
        )),
        const Gap(4),
        // グリッド
        Padding(padding: const EdgeInsets.fromLTRB(8,0,8,12), child: Column(
          children: List.generate(rows, (row) => Row(
            children: List.generate(7, (col) {
              final idx = row * 7 + col;
              final dn  = idx - fw + 1;
              if (dn < 1 || dn > dim) return const Expanded(child: SizedBox(height: 48));
              final date  = DateTime(month.year, month.month, dn);
              final ds    = _ds(date);
              final isTod = _same(date, today);
              final isSel = _same(date, selected);
              final isFut = date.isAfter(DateTime(today.year, today.month, today.day));
              final hasMk = marks.contains(ds);
              final isSun = col == 0; final isSat = col == 6;
              final txtCol = isSel ? Colors.white
                : isFut ? Colors.grey.shade300
                : isTod ? AppTheme.primaryGreen
                : isSun ? Colors.red.shade400 : isSat ? Colors.blue.shade400 : Colors.black87;
              return Expanded(child: GestureDetector(
                onTap: () => onTap(date),
                child: Container(
                  height: 48, margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSel ? AppTheme.primaryGreen : isTod ? AppTheme.primaryGreen.withOpacity(0.12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: isTod && !isSel ? Border.all(color: AppTheme.primaryGreen, width: 1.5) : null,
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('$dn', style: TextStyle(fontSize: 13, fontWeight: isTod || isSel ? FontWeight.w700 : FontWeight.normal, color: txtCol)),
                    SizedBox(height: 7, child: hasMk ? Center(child: Container(width: 5, height: 5,
                      decoration: BoxDecoration(
                        color: isSel ? Colors.white.withOpacity(0.85) : AppTheme.midGreen,
                        shape: BoxShape.circle))) : null),
                  ]),
                ),
              ));
            }),
          )),
        )),
      ]),
    );
  }
}


// ─────────────────────────────────────────────
// 最新体重カード
// ─────────────────────────────────────────────
class _LatestWeightCard extends StatelessWidget {
  const _LatestWeightCard({required this.future});
  final Future<Map<String, dynamic>?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: future,
      builder: (context, snap) {
        // ─── ローディング ──────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Icon(Icons.monitor_weight_outlined,
                    size: 18, color: Colors.grey.shade400),
                const Gap(8),
                Text('現在の体重',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                const Spacer(),
                SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.grey.shade400),
                ),
              ]),
            ),
          );
        }

        // ─── エラー ────────────────────────────
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.3)),
              ),
              child: Row(children: [
                Icon(Icons.warning_amber_rounded,
                    size: 18, color: AppTheme.errorColor),
                const Gap(8),
                Text('体重データの取得に失敗しました',
                    style: TextStyle(fontSize: 13, color: AppTheme.errorColor)),
              ]),
            ),
          );
        }

        // ─── データなし ────────────────────────
        final w = snap.data;
        if (w == null) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(children: [
                Icon(Icons.monitor_weight_outlined,
                    size: 18, color: Colors.grey.shade400),
                const Gap(8),
                Text('現在の体重: 体重未登録',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              ]),
            ),
          );
        }

        // ─── データあり ────────────────────────
        final kg  = w['weight_kg'];
        final date = w['log_date'] as String? ?? '';
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
            ),
            child: Row(children: [
              Icon(Icons.monitor_weight_outlined,
                  size: 18, color: AppTheme.primaryGreen),
              const Gap(8),
              Text('現在の体重',
                  style: TextStyle(fontSize: 13, color: AppTheme.primaryGreen)),
              const Spacer(),
              Text('$kg kg',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primaryGreen)),
              const Gap(8),
              Text(date,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          ),
        );
      },
    );
  }
}



// ─────────────────────────────────────────────
// カロリーデータクラス（拡張版）
// ─────────────────────────────────────────────
class _CalorieData {
  const _CalorieData({
    required this.intake,
    required this.bmr,
    required this.exercise,
    required this.tdee,
  });
  final int intake;    // 摂取カロリー
  final int bmr;       // 基礎代謝（BMR 切り捨て）
  final int exercise;  // 運動消費カロリー
  final int tdee;      // TDEE（基礎代謝 × 活動係数）

  int get totalBurn => tdee + exercise;   // 合計消費
  int get balance   => intake - totalBurn; // 差分（+ = オーバー / - = 余裕）
}

// ─────────────────────────────────────────────
// 運動一覧セクション
// ─────────────────────────────────────────────
class _ExerciseSection extends StatelessWidget {
  const _ExerciseSection({required this.future, required this.selected});
  final Future<List<Map<String,dynamic>>> future;
  final DateTime selected;

  static String _typeLabel(String? v) => switch (v) {
    'pool'     => 'プール',
    'running'  => 'ランニング',
    'walking'  => 'ウォーキング',
    'strength' => '筋トレ',
    _          => v ?? '',
  };

  static IconData _typeIcon(String? v) => switch (v) {
    'pool'     => Icons.pool_outlined,
    'running'  => Icons.directions_run_outlined,
    'walking'  => Icons.directions_walk_outlined,
    'strength' => Icons.fitness_center_outlined,
    _          => Icons.sports_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final dateStr = '${selected.year}-${selected.month.toString().padLeft(2,'0')}-${selected.day.toString().padLeft(2,'0')}';

    return Column(children: [
      // ヘッダー
      Container(
        padding: const EdgeInsets.fromLTRB(14,12,14,12),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(children: [
          Icon(Icons.directions_run_rounded, size: 15, color: Colors.blue.shade600),
          const Gap(7),
          Text('運動記録', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade600)),
          const Spacer(),
          GestureDetector(
            onTap: () => context.go('/exercise/new?date=$dateStr'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(color: Colors.blue.shade600, borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.add_rounded, size: 14, color: Colors.white),
                Gap(4),
                Text('運動を記録', style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ]),
      ),
      // 一覧
      Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
          border: Border(
            left: BorderSide(color: Colors.blue.shade200),
            right: BorderSide(color: Colors.blue.shade200),
            bottom: BorderSide(color: Colors.blue.shade200),
          ),
        ),
        child: FutureBuilder<List<Map<String,dynamic>>>(
          future: future,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Center(child: SizedBox(width: 24, height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2))));
            }
            final list = snap.data ?? [];
            if (list.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Center(child: Column(children: [
                  Icon(Icons.directions_run_outlined, size: 28, color: Colors.grey.shade300),
                  const Gap(6),
                  Text('まだ記録がありません', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                ])),
              );
            }
            final totalBurned = list.fold<int>(0, (s, e) => s + ((e['burned_kcal'] as int?) ?? 0));
            return Column(children: [
              ...list.map((e) {
                final type = e['exercise_type'] as String?;
                final min  = e['duration_min']  as int?;
                final kcal = e['burned_kcal']   as int?;
                return Column(children: [
                  Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: Row(children: [
                    Container(width: 34, height: 34,
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Icon(_typeIcon(type), size: 18, color: Colors.blue.shade600)),
                    const Gap(12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(_typeLabel(type), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      if (min != null) Text('$min 分', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                    ])),
                    Text(kcal != null ? '$kcal kcal' : '- kcal',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade600)),
                  ])),
                  Divider(height: 1, indent: 16, endIndent: 16, color: Colors.grey.shade100),
                ]);
              }),
              // 合計行
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('合計消費', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade600)),
                  Text('$totalBurned kcal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.blue.shade600)),
                ]),
              ),
            ]);
          },
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
// カロリー損益カード（拡張版: 5行表示）
// ─────────────────────────────────────────────
class _CalorieBalanceCard extends StatelessWidget {
  const _CalorieBalanceCard({required this.future});
  final Future<_CalorieData?> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CalorieData?>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade50, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Icon(Icons.local_fire_department_outlined, size: 18, color: Colors.grey.shade400),
              const Gap(10),
              Text('カロリー計算中...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
              const Spacer(),
              SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey.shade400)),
            ]),
          );
        }

        final data = snap.data;
        if (snap.hasError || data == null) return const SizedBox.shrink();

        final balance  = data.balance;
        final isOver   = balance > 0;
        final noMeal   = data.intake == 0;

        final mainColor = noMeal
            ? Colors.grey.shade400
            : isOver ? const Color(0xFFE24B4A) : AppTheme.primaryGreen;
        final bgColor = noMeal
            ? Colors.grey.shade50
            : isOver ? const Color(0xFFE24B4A).withOpacity(0.06) : AppTheme.primaryGreen.withOpacity(0.06);
        final borderColor = noMeal
            ? Colors.grey.shade200
            : isOver ? const Color(0xFFE24B4A).withOpacity(0.35) : AppTheme.primaryGreen.withOpacity(0.35);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: bgColor, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ヘッダー
            Row(children: [
              Icon(Icons.local_fire_department_outlined, size: 17, color: mainColor),
              const Gap(6),
              Text('1日のカロリー損益', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: mainColor)),
            ]),
            const Gap(14),

            // 5行の数値テーブル
            _CalRow(label: '摂取カロリー',     value: noMeal ? '--' : '${data.intake}',     color: Colors.black87,                 icon: Icons.restaurant_outlined),
            _CalRow(label: '基礎代謝',         value: '${data.bmr}',                         color: Colors.grey.shade600,           icon: Icons.monitor_heart_outlined),
            _CalRow(label: '運動消費',         value: '${data.exercise}',                    color: Colors.blue.shade600,           icon: Icons.directions_run_outlined),
            const Divider(height: 20),
            _CalRow(label: '合計消費',         value: '${data.totalBurn}',                   color: Colors.black87,                 icon: Icons.local_fire_department_outlined, bold: true),
            const Gap(4),

            // 差分
            Row(children: [
              Icon(noMeal ? Icons.edit_note_rounded
                  : isOver ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                size: 14, color: mainColor),
              const Gap(4),
              Expanded(child: Text(
                noMeal ? '食事を記録すると差分が表示されます'
                  : isOver ? '差分: +$balance kcal（摂取オーバー）'
                  : '差分: $balance kcal（余裕あり）',
                style: TextStyle(fontSize: 12, color: mainColor, fontWeight: FontWeight.w600),
              )),
            ]),

            if (!noMeal) ...[
              const Gap(10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (data.intake / data.totalBurn).clamp(0.0, 1.5),
                  minHeight: 6,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isOver ? const Color(0xFFE24B4A) : AppTheme.primaryGreen),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}

class _CalRow extends StatelessWidget {
  const _CalRow({required this.label, required this.value, required this.color, required this.icon, this.bold = false});
  final String label, value;
  final Color color;
  final IconData icon;
  final bool bold;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(children: [
      Icon(icon, size: 14, color: color.withOpacity(0.7)),
      const Gap(8),
      Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
      Text('$value kcal', style: TextStyle(
        fontSize: 13, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color)),
    ]),
  );
}


// ─────────────────────────────────────────────
// 運動目安カード
// ─────────────────────────────────────────────
class _ExerciseSuggestionCard extends StatelessWidget {
  const _ExerciseSuggestionCard({required this.future});
  final Future<_CalorieData?> future;

  // 運動種別ごとの kcal/分
  static const _rates = [
    ('ウォーキング', Icons.directions_walk_outlined, 4),
    ('筋トレ',       Icons.fitness_center_outlined,   6),
    ('プール',       Icons.pool_outlined,              8),
    ('ランニング',   Icons.directions_run_outlined,   10),
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CalorieData?>(
      future: future,
      builder: (_, snap) {
        // ローディング中・エラー・データなしは非表示
        if (snap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
        if (snap.hasError || snap.data == null)             return const SizedBox.shrink();

        final data    = snap.data!;
        final balance = data.balance; // + = 摂取オーバー / - = 余裕

        // ─── 収支OK ───────────────────────────
        if (balance <= 0) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: AppTheme.primaryGreen.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
            ),
            child: Row(children: [
              const Icon(Icons.check_circle_outline_rounded, size: 20, color: AppTheme.primaryGreen),
              const Gap(10),
              Expanded(
                child: Text(
                  '今日は収支OKです',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen),
                ),
              ),
              if (balance < 0)
                Text(
                  '余裕 ${balance.abs()} kcal',
                  style: TextStyle(fontSize: 12, color: AppTheme.midGreen),
                ),
            ]),
          );
        }

        // ─── 摂取オーバー → 運動目安を表示 ────
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.orange.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ヘッダー
            Row(children: [
              Icon(Icons.directions_run_rounded, size: 17, color: Colors.orange.shade700),
              const Gap(8),
              Expanded(
                child: Text(
                  'あと $balance kcal 消費すると収支0です',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange.shade800),
                ),
              ),
            ]),

            const Gap(14),
            Divider(height: 1, color: Colors.orange.shade200),
            const Gap(12),

            // 運動別の目安分数
            ...List.generate(_rates.length, (i) {
              final (label, icon, rate) = _rates[i];
              final minutes = (balance / rate).ceil(); // ceil で切り上げ
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(icon, size: 16, color: Colors.orange.shade600),
                  const Gap(10),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 13, color: Colors.orange.shade800)),
                  ),
                  // 分数バッジ
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '約 $minutes 分',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// 体重推移グラフカード（Flutter 標準のみ・CustomPaint）
// ─────────────────────────────────────────────
class _WeightChartCard extends StatelessWidget {
  const _WeightChartCard({required this.future});
  final Future<List<Map<String,dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,dynamic>>>(
      future: future,
      builder: (_, snap) {
        // ─── ローディング ────────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 160,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: SizedBox(width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          );
        }

        final logs = snap.data ?? [];

        // ─── データ不足 ──────────────────────────
        if (logs.length <= 1) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(children: [
              Icon(Icons.show_chart_rounded, size: 22, color: Colors.grey.shade300),
              const Gap(12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('体重推移', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                const Gap(2),
                Text('体重データが不足しています',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
              ])),
            ]),
          );
        }

        // ─── データあり → グラフ表示 ─────────────
        final weights = logs.map((r) => (r['weight_kg'] as num).toDouble()).toList();
        final dates   = logs.map((r) => r['log_date'] as String).toList();

        final minW  = weights.reduce((a, b) => a < b ? a : b);
        final maxW  = weights.reduce((a, b) => a > b ? a : b);
        final latestW = weights.last;
        final latestD = dates.last;

        // Y 軸の範囲に少し余白を持たせる
        final rangeW = (maxW - minW).clamp(1.0, double.infinity);
        final yMin   = (minW - rangeW * 0.15).floorToDouble();
        final yMax   = (maxW + rangeW * 0.15).ceilToDouble();

        return Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.2)),
            boxShadow: [BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 8, offset: const Offset(0, 2))],
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ヘッダー
            Row(children: [
              Icon(Icons.show_chart_rounded, size: 16, color: AppTheme.primaryGreen),
              const Gap(6),
              Text('体重推移（直近30日）',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
              const Spacer(),
              // 最新値バッジ
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.lightGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$latestW kg  $latestD',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primaryGreen)),
              ),
            ]),

            const Gap(12),

            // グラフ本体
            SizedBox(
              height: 120,
              child: CustomPaint(
                size: const Size(double.infinity, 120),
                painter: _WeightLinePainter(
                  weights: weights,
                  yMin:    yMin,
                  yMax:    yMax,
                  color:   AppTheme.primaryGreen,
                  dotColor: AppTheme.midGreen,
                ),
              ),
            ),

            const Gap(6),

            // X 軸の日付ラベル（最初・中間・最後）
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(_shortDate(dates.first),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              if (dates.length > 2)
                Text(_shortDate(dates[dates.length ~/ 2]),
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              Text(_shortDate(dates.last),
                style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ]),
          ]),
        );
      },
    );
  }

  // "YYYY-MM-DD" → "M/D" に短縮
  String _shortDate(String d) {
    final parts = d.split('-');
    if (parts.length < 3) return d;
    return '${int.tryParse(parts[1]) ?? parts[1]}/${int.tryParse(parts[2]) ?? parts[2]}';
  }
}

// ─────────────────────────────────────────────
// CustomPainter：折れ線グラフ
// ─────────────────────────────────────────────
class _WeightLinePainter extends CustomPainter {
  const _WeightLinePainter({
    required this.weights,
    required this.yMin,
    required this.yMax,
    required this.color,
    required this.dotColor,
  });

  final List<double> weights;
  final double yMin, yMax;
  final Color  color, dotColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (weights.length < 2) return;

    final w = size.width;
    final h = size.height;
    final range = yMax - yMin;

    // X 座標：データ点を等間隔に並べる
    double xOf(int i) => weights.length == 1
        ? w / 2
        : w * i / (weights.length - 1);

    // Y 座標：yMin → 下端、yMax → 上端（画面は上が小さい値）
    double yOf(double val) => h - h * (val - yMin) / range;

    // ─── グリッド横線（3本） ──────────────────
    final gridPaint = Paint()
      ..color = Colors.grey.shade100
      ..strokeWidth = 1;
    for (int i = 0; i <= 2; i++) {
      final y = h * i / 2;
      canvas.drawLine(Offset(0, y), Offset(w, y), gridPaint);
    }

    // ─── 塗りつぶし（グラデーション） ──────────
    final fillPath = Path();
    fillPath.moveTo(xOf(0), yOf(weights[0]));
    for (int i = 1; i < weights.length; i++) {
      fillPath.lineTo(xOf(i), yOf(weights[i]));
    }
    fillPath.lineTo(xOf(weights.length - 1), h);
    fillPath.lineTo(xOf(0), h);
    fillPath.close();

    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [color.withOpacity(0.18), color.withOpacity(0.0)],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // ─── 折れ線 ───────────────────────────────
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final linePath = Path();
    linePath.moveTo(xOf(0), yOf(weights[0]));
    for (int i = 1; i < weights.length; i++) {
      linePath.lineTo(xOf(i), yOf(weights[i]));
    }
    canvas.drawPath(linePath, linePaint);

    // ─── データ点（小さい丸） ─────────────────
    final dotFill = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final dotBorder = Paint()
      ..color = dotColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    const dotR = 3.5;
    for (int i = 0; i < weights.length; i++) {
      final pt = Offset(xOf(i), yOf(weights[i]));
      canvas.drawCircle(pt, dotR, dotFill);
      canvas.drawCircle(pt, dotR, dotBorder);
    }

    // ─── 最新点を強調（大きい丸） ─────────────
    final lastPt = Offset(xOf(weights.length - 1), yOf(weights.last));
    canvas.drawCircle(lastPt, 5.5, Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawCircle(lastPt, 5.5, Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(_WeightLinePainter old) =>
      old.weights != weights || old.yMin != yMin || old.yMax != yMax;
}
