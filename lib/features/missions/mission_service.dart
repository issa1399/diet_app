// lib/features/missions/mission_service.dart
//
// ミッション進捗の更新 + ポイント付与の共有ロジック。
// 各画面から呼び出す。Provider 不使用・静的メソッドのみ。
//
// ─── Supabase テーブル想定 ────────────────────────────────────────────────
//
// missions テーブル:
//   id uuid PK
//   title text
//   description text
//   type text         -- 'daily' | 'weekly'
//   action_key text   -- 'login_daily' | 'meal_daily' | 'weight_daily'
//                        'login_weekly' | 'meal_weekly' | 'weight_weekly'
//   required_count int  -- 達成に必要な回数
//   reward_points int   -- 達成時のポイント
//
// user_missions テーブル:
//   id uuid PK
//   user_id uuid FK → auth.users
//   mission_id uuid FK → missions
//   progress int DEFAULT 0
//   claimed boolean DEFAULT false
//   week_start date   -- 週次ミッション用（その週の月曜日）
//   log_date date     -- 日次ミッション用（その日の日付）
//   created_at timestamptz
//   UNIQUE(user_id, mission_id, log_date)   -- 日次用
//   UNIQUE(user_id, mission_id, week_start) -- 週次用
// ─────────────────────────────────────────────────────────────────────────

import 'package:supabase_flutter/supabase_flutter.dart';

class MissionService {
  MissionService._();

  static SupabaseClient get _db => Supabase.instance.client;

  // ─── 日付ユーティリティ ──────────────────────
  static String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2,'0')}-${n.day.toString().padLeft(2,'0')}';
  }

  // その週の月曜日（ISO週: 月=1）
  static String _weekStart() {
    final now = DateTime.now();
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return '${monday.year}-${monday.month.toString().padLeft(2,'0')}-${monday.day.toString().padLeft(2,'0')}';
  }

  // ─── ポイント加算（100pt ごとにレベルアップ） ──
  static Future<void> addPoints(String userId, int pts) async {
    if (pts <= 0) return;
    final p = await _db.from('profiles')
        .select('points, level').eq('id', userId).single();
    int points = (p['points'] as int? ?? 0) + pts;
    int level  = p['level']  as int? ?? 1;
    while (points >= 100) { points -= 100; level += 1; }
    await _db.from('profiles')
        .update({'points': points, 'level': level}).eq('id', userId);
  }

  // ─── ミッション進捗を +1 する ────────────────
  //
  // actionKey: 'login_daily' | 'meal_daily' | 'weight_daily'
  //            'login_weekly' | 'meal_weekly' | 'weight_weekly'
  //
  // 処理:
  //   1. missions から該当 action_key の行を取得
  //   2. user_missions の当日 / 当週の行を upsert（progress += 1）
  //   3. claimed 済みは変更しない
  static Future<void> incrementProgress(String userId, String actionKey) async {
    try {
      final isWeekly = actionKey.endsWith('_weekly');

      // 対象ミッションを取得
      final missions = await _db.from('missions')
          .select('id, required_count')
          .eq('action_key', actionKey);

      for (final m in missions as List) {
        final missionId    = m['id'] as String;
        final requiredCount = m['required_count'] as int? ?? 1;

        final dateKey = isWeekly ? 'week_start' : 'log_date';
        final dateVal = isWeekly ? _weekStart()  : _today();

        // 現在の user_missions 行を取得
        final existing = await _db.from('user_missions')
            .select('id, progress, claimed')
            .eq('user_id',    userId)
            .eq('mission_id', missionId)
            .eq(dateKey,      dateVal)
            .maybeSingle();

        // claimed 済みは変更しない
        if (existing != null && existing['claimed'] == true) continue;

        final currentProgress = (existing?['progress'] as int?) ?? 0;

        // 上限は required_count まで（余分に増えないようにする）
        final newProgress = (currentProgress + 1).clamp(0, requiredCount);
        if (newProgress == currentProgress) continue; // 変化なし

        if (existing == null) {
          // 新規作成
          await _db.from('user_missions').insert({
            'user_id':    userId,
            'mission_id': missionId,
            'progress':   newProgress,
            'claimed':    false,
            dateKey:      dateVal,
          });
        } else {
          // 更新
          await _db.from('user_missions')
              .update({'progress': newProgress})
              .eq('id', existing['id'] as String);
        }
      }
    } catch (_) {
      // ミッション更新の失敗はサイレントに無視（本体機能を妨げない）
    }
  }

  // ─── デイリーミッションを increment（日次 3 種まとめて） ──
  static Future<void> onLogin(String userId) async {
    await incrementProgress(userId, 'login_daily');
    await incrementProgress(userId, 'login_weekly');
  }

  static Future<void> onMealSaved(String userId) async {
    await incrementProgress(userId, 'meal_daily');
    await incrementProgress(userId, 'meal_weekly');
  }

  static Future<void> onWeightSaved(String userId) async {
    await incrementProgress(userId, 'weight_daily');
    await incrementProgress(userId, 'weight_weekly');
  }

  // ─── ミッション報酬を受け取る ────────────────
  static Future<void> claimReward({
    required String userId,
    required String userMissionId,
    required int    rewardPoints,
  }) async {
    // claimed を true に更新
    await _db.from('user_missions')
        .update({'claimed': true})
        .eq('id', userMissionId);

    // ポイント加算
    await addPoints(userId, rewardPoints);
  }

  // ─── ミッション一覧 + user_missions を結合して取得 ──
  // 戻り値: [{mission, user_mission_or_null}] のリスト
  static Future<List<_MissionEntry>> fetchMissions({
    required String userId,
    required String type, // 'daily' | 'weekly'
  }) async {
    final isWeekly = type == 'weekly';
    final dateKey  = isWeekly ? 'week_start' : 'log_date';
    final dateVal  = isWeekly ? _weekStart()  : _today();

    final missions = await _db.from('missions')
        .select('id, title, description, type, action_key, required_count, reward_points')
        .eq('type', type)
        .order('required_count', ascending: true);

    final result = <_MissionEntry>[];
    for (final m in missions as List) {
      final um = await _db.from('user_missions')
          .select('id, progress, claimed')
          .eq('user_id',    userId)
          .eq('mission_id', m['id'] as String)
          .eq(dateKey,      dateVal)
          .maybeSingle();

      result.add(_MissionEntry(
        mission:     m,
        userMission: um,
      ));
    }
    return result;
  }
}

// ─────────────────────────────────────────────
// データクラス
// ─────────────────────────────────────────────
class _MissionEntry {
  const _MissionEntry({required this.mission, required this.userMission});
  final Map<String, dynamic>  mission;
  final Map<String, dynamic>? userMission;

  int  get progress      => (userMission?['progress'] as int?)  ?? 0;
  bool get claimed       => (userMission?['claimed']  as bool?) ?? false;
  int  get requiredCount => (mission['required_count'] as int?) ?? 1;
  int  get rewardPoints  => (mission['reward_points']  as int?) ?? 0;
  bool get isCompleted   => progress >= requiredCount;
  String? get userMissionId => userMission?['id'] as String?;
}

// 外部公開用（screens から import して使う）
typedef MissionEntry = _MissionEntry;
