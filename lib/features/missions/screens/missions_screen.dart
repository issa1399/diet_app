// lib/features/missions/screens/missions_screen.dart
//
// ミッション一覧画面。
// - デイリー / ウィークリーをタブで切り替え
// - missions + user_missions を結合して進捗表示
// - 達成済みは「報酬を受け取る」ボタン
// - 受け取り時に profiles.points を加算、100pt ごとにレベルアップ

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../mission_service.dart';

class MissionsScreen extends StatefulWidget {
  const MissionsScreen({super.key});

  @override
  State<MissionsScreen> createState() => _MissionsScreenState();
}

class _MissionsScreenState extends State<MissionsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  late Future<List<MissionEntry>> _dailyFuture;
  late Future<List<MissionEntry>> _weeklyFuture;
  String? _userId;

  @override
  void initState() {
    super.initState();
    _tab    = TabController(length: 2, vsync: this);
    _userId = Supabase.instance.client.auth.currentUser?.id;
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _reload() {
    if (_userId == null) return;
    setState(() {
      _dailyFuture  = MissionService.fetchMissions(userId: _userId!, type: 'daily');
      _weeklyFuture = MissionService.fetchMissions(userId: _userId!, type: 'weekly');
    });
  }

  Future<void> _claim(MissionEntry entry) async {
    if (_userId == null) return;
    final umId = entry.userMissionId;
    if (umId == null) return;

    await MissionService.claimReward(
      userId:        _userId!,
      userMissionId: umId,
      rewardPoints:  entry.rewardPoints,
    );

    _reload();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.star_rounded, color: Colors.white, size: 18),
            const Gap(8),
            Text('+${entry.rewardPoints} pt 獲得しました！',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
          backgroundColor: AppTheme.primaryGreen,
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ミッション'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => context.go('/home'),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '更新',
            onPressed: _reload,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: AppTheme.primaryGreen,
          tabs: const [
            Tab(text: 'デイリー'),
            Tab(text: 'ウィークリー'),
          ],
        ),
      ),
      body: _userId == null
          ? const Center(child: Text('ログインが必要です'))
          : TabBarView(
              controller: _tab,
              children: [
                _MissionTab(
                  future:    _dailyFuture,
                  onClaim:   _claim,
                  onRefresh: _reload,
                ),
                _MissionTab(
                  future:    _weeklyFuture,
                  onClaim:   _claim,
                  onRefresh: _reload,
                ),
              ],
            ),
    );
  }
}

// ─────────────────────────────────────────────
// タブコンテンツ（FutureBuilder + リスト）
// ─────────────────────────────────────────────
class _MissionTab extends StatelessWidget {
  const _MissionTab({
    required this.future,
    required this.onClaim,
    required this.onRefresh,
  });

  final Future<List<MissionEntry>> future;
  final Future<void> Function(MissionEntry) onClaim;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<MissionEntry>>(
      future: future,
      builder: (_, snap) {
        // ─── ローディング ────────────────────────
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // ─── エラー ──────────────────────────────
        if (snap.hasError) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline_rounded,
                  color: AppTheme.errorColor, size: 36),
              const Gap(12),
              Text('取得に失敗しました',
                  style: TextStyle(color: AppTheme.errorColor)),
              const Gap(12),
              TextButton(
                onPressed: onRefresh,
                child: const Text('再試行'),
              ),
            ]),
          );
        }

        final list = snap.data ?? [];

        // ─── データなし ──────────────────────────
        if (list.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.emoji_events_outlined,
                  size: 52, color: Colors.grey.shade300),
              const Gap(16),
              Text('ミッションがありません',
                  style: TextStyle(
                      fontSize: 15, color: Colors.grey.shade500)),
              const Gap(6),
              Text('Supabase の missions テーブルにデータを追加してください',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade400),
                  textAlign: TextAlign.center),
            ]),
          );
        }

        // ─── リスト ──────────────────────────────
        return RefreshIndicator(
          onRefresh: () async => onRefresh(),
          color: AppTheme.primaryGreen,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            itemCount: list.length,
            separatorBuilder: (_, __) => const Gap(12),
            itemBuilder: (_, i) =>
                _MissionCard(entry: list[i], onClaim: onClaim),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// ミッションカード
// ─────────────────────────────────────────────
class _MissionCard extends StatefulWidget {
  const _MissionCard({required this.entry, required this.onClaim});

  final MissionEntry entry;
  final Future<void> Function(MissionEntry) onClaim;

  @override
  State<_MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends State<_MissionCard> {
  bool _claiming = false;

  @override
  Widget build(BuildContext context) {
    final e        = widget.entry;
    final progress = e.progress;
    final required = e.requiredCount;
    final ratio    = (progress / required).clamp(0.0, 1.0);
    final done     = e.isCompleted;     // 達成済み
    final claimed  = e.claimed;         // 報酬受け取り済み

    // カードの背景・枠色
    final bgColor = claimed
        ? Colors.grey.shade50
        : done
            ? AppTheme.primaryGreen.withOpacity(0.05)
            : Colors.white;

    final borderColor = claimed
        ? Colors.grey.shade200
        : done
            ? AppTheme.primaryGreen.withOpacity(0.5)
            : Colors.grey.shade200;

    // アイコン
    final icon = claimed
        ? Icons.check_circle_rounded
        : done
            ? Icons.emoji_events_rounded
            : Icons.emoji_events_outlined;

    final iconColor = claimed
        ? Colors.grey.shade400
        : AppTheme.primaryGreen;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: borderColor,
          width: done && !claimed ? 1.5 : 1,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ─── ヘッダー行 ──────────────────────────
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // アイコン
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: claimed
                  ? Colors.grey.shade100
                  : AppTheme.lightGreen,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),

          const Gap(12),

          // タイトル・説明
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(
                e.mission['title'] as String? ?? '',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: claimed ? Colors.grey.shade400 : Colors.black87,
                  decoration:
                      claimed ? TextDecoration.lineThrough : null,
                ),
              ),
              const Gap(2),
              Text(
                e.mission['description'] as String? ?? '',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ]),
          ),

          const Gap(8),

          // 報酬バッジ
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: claimed
                  ? Colors.grey.shade100
                  : AppTheme.lightGreen,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '+${e.rewardPoints} pt',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: claimed
                    ? Colors.grey.shade400
                    : AppTheme.primaryGreen,
              ),
            ),
          ),
        ]),

        const Gap(14),

        // ─── 進捗バー ────────────────────────────
        Row(children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 7,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation<Color>(
                  claimed
                      ? Colors.grey.shade300
                      : AppTheme.primaryGreen,
                ),
              ),
            ),
          ),
          const Gap(10),

          // 進捗数値
          Text(
            '$progress / $required',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: claimed
                  ? Colors.grey.shade400
                  : AppTheme.primaryGreen,
            ),
          ),

          // 完了チェックマーク
          if (done) ...[
            const Gap(6),
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: claimed
                  ? Colors.grey.shade400
                  : AppTheme.primaryGreen,
            ),
          ],
        ]),

        // ─── 受け取るボタン（達成済み & 未受取のみ） ──
        if (done && !claimed) ...[
          const Gap(14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _claiming
                  ? null
                  : () async {
                      setState(() => _claiming = true);
                      await widget.onClaim(e);
                      if (mounted) setState(() => _claiming = false);
                    },
              icon: _claiming
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.redeem_rounded, size: 16),
              label: Text(_claiming ? '処理中...' : '報酬を受け取る'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryGreen,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppTheme.primaryGreen.withOpacity(0.5),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],

        // ─── 受け取り済みの表示 ───────────────────
        if (claimed) ...[
          const Gap(10),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.check_circle_rounded,
                size: 14, color: Colors.grey.shade400),
            const Gap(4),
            Text(
              '受け取り済み',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey.shade400),
            ),
          ]),
        ],
      ]),
    );
  }
}
