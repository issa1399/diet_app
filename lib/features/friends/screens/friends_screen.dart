// lib/features/friends/screens/friends_screen.dart
//
// フレンド機能。
// - ニックネームでユーザー検索 → friendships に pending で申請
// - 自分宛ての pending 申請を承認 / 拒否
// - accepted フレンド一覧（nickname + level）

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:diet_app/theme/app_theme.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  // 検索
  final _searchCtrl = TextEditingController();
  bool    _searching    = false;
  String? _searchError;
  String? _searchSuccess;
  List<Map<String,dynamic>> _searchResults = [];

  SupabaseClient get _db => Supabase.instance.client;
  String get _myId => _db.auth.currentUser!.id;

  // Futures
  late Future<List<Map<String,dynamic>>> _friendsFuture;
  late Future<List<Map<String,dynamic>>> _pendingFuture;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
    _reload();
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _friendsFuture = _fetchFriends();
      _pendingFuture = _fetchPending();
    });
  }

  // ─── accepted フレンド一覧 ─────────────────
  Future<List<Map<String,dynamic>>> _fetchFriends() async {
    final rows = await _db
        .from('friendships')
        .select('requester_id, addressee_id')
        .or('requester_id.eq.$_myId,addressee_id.eq.$_myId')
        .eq('status', 'accepted');

    final friends = <Map<String,dynamic>>[];
    for (final r in rows as List) {
      final otherId = r['requester_id'] == _myId
          ? r['addressee_id'] as String
          : r['requester_id'] as String;
      final p = await _db
          .from('profiles')
          .select('nickname, level')
          .eq('id', otherId)
          .maybeSingle();
      if (p != null) {
        friends.add({
          'user_id':  otherId,
          'nickname': (p['nickname'] as String?)?.trim().isNotEmpty == true
              ? p['nickname'] : '名無し',
          'level':    p['level'] ?? 1,
        });
      }
    }
    return friends;
  }

  // ─── 自分宛ての pending 申請 ───────────────
  Future<List<Map<String,dynamic>>> _fetchPending() async {
    final rows = await _db
        .from('friendships')
        .select('id, requester_id')
        .eq('addressee_id', _myId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    final pending = <Map<String,dynamic>>[];
    for (final r in rows as List) {
      final p = await _db
          .from('profiles')
          .select('nickname, level')
          .eq('id', r['requester_id'] as String)
          .maybeSingle();
      pending.add({
        'friendship_id': r['id'],
        'requester_id':  r['requester_id'],
        'nickname': (p?['nickname'] as String?)?.trim().isNotEmpty == true
            ? p!['nickname'] : '名無し',
        'level': p?['level'] ?? 1,
      });
    }
    return pending;
  }

  // ─── ニックネーム検索 ──────────────────────
  Future<void> _search() async {
    final nick = _searchCtrl.text.trim();
    if (nick.isEmpty) return;

    setState(() {
      _searching    = true;
      _searchError  = null;
      _searchSuccess = null;
      _searchResults = [];
    });

    try {
      // profiles.nickname で部分一致検索（自分を除く）
      final rows = await _db
          .from('profiles')
          .select('id, nickname, level')
          .ilike('nickname', '%$nick%')
          .neq('id', _myId)
          .limit(10);

      final results = List<Map<String,dynamic>>.from(rows as List);

      // すでに申請済み・フレンド済みの相手を除外するため status を確認
      final enriched = <Map<String,dynamic>>[];
      for (final r in results) {
        final targetId = r['id'] as String;
        final existing = await _db
            .from('friendships')
            .select('status')
            .or('and(requester_id.eq.$_myId,addressee_id.eq.$targetId),'
                'and(requester_id.eq.$targetId,addressee_id.eq.$_myId)')
            .maybeSingle();

        enriched.add({
          'id':       targetId,
          'nickname': (r['nickname'] as String?)?.trim().isNotEmpty == true
              ? r['nickname'] : '名無し',
          'level':    r['level'] ?? 1,
          'status':   existing?['status'], // null = 未申請
        });
      }

      setState(() => _searchResults = enriched);
      if (enriched.isEmpty) {
        setState(() => _searchError = '「$nick」に一致するユーザーが見つかりません');
      }
    } catch (e) {
      setState(() => _searchError = 'エラーが発生しました: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  // ─── 申請送信 ──────────────────────────────
  Future<void> _sendRequest(String targetId, String nickname) async {
    try {
      await _db.from('friendships').insert({
        'requester_id': _myId,
        'addressee_id': targetId,
        'status':       'pending',
      });
      // UI を更新（検索結果の status を pending に変える）
      setState(() {
        _searchResults = _searchResults.map((r) {
          if (r['id'] == targetId) return {...r, 'status': 'pending'};
          return r;
        }).toList();
        _searchSuccess = '$nickname さんに申請を送りました';
      });
      _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('申請に失敗しました: $e'),
          backgroundColor: AppTheme.errorColor,
        ));
      }
    }
  }

  // ─── 承認 ──────────────────────────────────
  Future<void> _accept(String friendshipId) async {
    await _db.from('friendships')
        .update({'status': 'accepted'}).eq('id', friendshipId);
    _reload();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('フレンドになりました！'),
        backgroundColor: AppTheme.primaryGreen,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  // ─── 拒否 ──────────────────────────────────
  Future<void> _reject(String friendshipId) async {
    await _db.from('friendships')
        .update({'status': 'rejected'}).eq('id', friendshipId);
    _reload();
  }

  // ─── build ─────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('フレンド'),
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
            onPressed: _reload,
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: AppTheme.primaryGreen,
          unselectedLabelColor: Colors.grey.shade500,
          indicatorColor: AppTheme.primaryGreen,
          tabs: const [
            Tab(text: 'フレンド'),
            Tab(text: '申請'),
            Tab(text: '検索'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _FriendsTab(future: _friendsFuture),
          _PendingTab(future: _pendingFuture, onAccept: _accept, onReject: _reject),
          _SearchTab(
            ctrl:          _searchCtrl,
            searching:     _searching,
            searchError:   _searchError,
            searchSuccess: _searchSuccess,
            results:       _searchResults,
            onSearch:      _search,
            onSend:        _sendRequest,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
// フレンド一覧タブ
// ─────────────────────────────────────────────
class _FriendsTab extends StatelessWidget {
  const _FriendsTab({required this.future});
  final Future<List<Map<String,dynamic>>> future;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,dynamic>>>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _EmptyState(
            icon: Icons.people_outline_rounded,
            message: 'まだフレンドがいません',
            sub: '「検索」タブでニックネームを検索して追加しましょう',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
          itemBuilder: (_, i) => _FriendRow(
            nickname: list[i]['nickname'] as String,
            level:    list[i]['level']    as int,
          ),
        );
      },
    );
  }
}

class _FriendRow extends StatelessWidget {
  const _FriendRow({required this.nickname, required this.level});
  final String nickname;
  final int    level;

  @override
  Widget build(BuildContext context) {
    final initial = nickname.isNotEmpty ? nickname[0].toUpperCase() : '?';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppTheme.lightGreen,
          child: Text(initial, style: TextStyle(
            color: AppTheme.primaryGreen, fontWeight: FontWeight.w700, fontSize: 15)),
        ),
        const Gap(14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(nickname, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const Gap(2),
          Text('Lv. $level', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ])),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.lightGreen, borderRadius: BorderRadius.circular(20)),
          child: Text('フレンド', style: TextStyle(fontSize: 11, color: AppTheme.primaryGreen, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────
// 申請一覧タブ
// ─────────────────────────────────────────────
class _PendingTab extends StatelessWidget {
  const _PendingTab({
    required this.future,
    required this.onAccept,
    required this.onReject,
  });
  final Future<List<Map<String,dynamic>>> future;
  final Future<void> Function(String) onAccept;
  final Future<void> Function(String) onReject;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String,dynamic>>>(
      future: future,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? [];
        if (list.isEmpty) {
          return _EmptyState(
            icon: Icons.mark_email_read_outlined,
            message: '申請はありません',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
          itemBuilder: (_, i) {
            final item = list[i];
            final nick = item['nickname'] as String;
            final lv   = item['level']   as int;
            final fid  = item['friendship_id'] as String;
            final initial = nick.isNotEmpty ? nick[0].toUpperCase() : '?';
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.orange.shade50,
                  child: Text(initial, style: TextStyle(
                    color: Colors.orange.shade700, fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                const Gap(14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(nick, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text('Lv. $lv', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ])),
                // 拒否ボタン
                TextButton(
                  onPressed: () => onReject(fid),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.errorColor,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('拒否', style: TextStyle(fontSize: 13)),
                ),
                const Gap(6),
                // 承認ボタン
                ElevatedButton(
                  onPressed: () => onAccept(fid),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryGreen,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('承認', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────
// 検索タブ
// ─────────────────────────────────────────────
class _SearchTab extends StatelessWidget {
  const _SearchTab({
    required this.ctrl,
    required this.searching,
    required this.searchError,
    required this.searchSuccess,
    required this.results,
    required this.onSearch,
    required this.onSend,
  });
  final TextEditingController ctrl;
  final bool searching;
  final String? searchError;
  final String? searchSuccess;
  final List<Map<String,dynamic>> results;
  final VoidCallback onSearch;
  final Future<void> Function(String id, String nickname) onSend;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ニックネームで検索',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const Gap(10),

          // 検索バー
          Row(children: [
            Expanded(child: AppTextField(
              controller: ctrl,
              label: '相手のニックネーム',
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSearch(),
            )),
            const Gap(10),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: searching ? null : onSearch,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryGreen,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: searching
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('検索', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),

          const Gap(16),

          // エラー
          if (searchError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.errorColor.withOpacity(0.08),
                border: Border.all(color: AppTheme.errorColor.withOpacity(0.4)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: AppTheme.errorColor, size: 16),
                const Gap(8),
                Expanded(child: Text(searchError!,
                  style: TextStyle(fontSize: 13, color: AppTheme.errorColor))),
              ]),
            ),

          // 成功
          if (searchSuccess != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primaryGreen.withOpacity(0.08),
                border: Border.all(color: AppTheme.primaryGreen.withOpacity(0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(children: [
                Icon(Icons.check_circle_outline_rounded, color: AppTheme.primaryGreen, size: 16),
                const Gap(8),
                Expanded(child: Text(searchSuccess!,
                  style: TextStyle(fontSize: 13, color: AppTheme.primaryGreen))),
              ]),
            ),

          const Gap(8),

          // 検索結果
          ...results.map((r) => _SearchResultRow(result: r, onSend: onSend)),

          // 注意書き
          if (results.isEmpty && searchError == null && searchSuccess == null) ...[
            const Gap(8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded, size: 15, color: Colors.blue.shade600),
                const Gap(8),
                Expanded(child: Text(
                  'ニックネームの一部を入力して検索してください。\n'
                  '相手がアプリでニックネームを設定している必要があります。',
                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700, height: 1.5),
                )),
              ]),
            ),
          ],
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 検索結果の1行
// ─────────────────────────────────────────────
class _SearchResultRow extends StatefulWidget {
  const _SearchResultRow({required this.result, required this.onSend});
  final Map<String,dynamic> result;
  final Future<void> Function(String id, String nickname) onSend;
  @override State<_SearchResultRow> createState() => _SearchResultRowState();
}

class _SearchResultRowState extends State<_SearchResultRow> {
  bool _sending = false;

  @override
  Widget build(BuildContext context) {
    final nick   = widget.result['nickname'] as String;
    final lv     = widget.result['level']    as int;
    final id     = widget.result['id']       as String;
    final status = widget.result['status']   as String?;
    final initial = nick.isNotEmpty ? nick[0].toUpperCase() : '?';

    // ステータスに応じたボタン表示
    Widget trailing;
    if (status == 'accepted') {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: AppTheme.lightGreen, borderRadius: BorderRadius.circular(20)),
        child: Text('フレンド', style: TextStyle(fontSize: 12, color: AppTheme.primaryGreen, fontWeight: FontWeight.w600)),
      );
    } else if (status == 'pending') {
      trailing = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.orange.shade200)),
        child: Text('申請中', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
      );
    } else {
      // 未申請 → 申請ボタン
      trailing = ElevatedButton.icon(
        onPressed: _sending ? null : () async {
          setState(() => _sending = true);
          await widget.onSend(id, nick);
          if (mounted) setState(() => _sending = false);
        },
        icon: _sending
            ? const SizedBox(width: 12, height: 12,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.person_add_outlined, size: 14),
        label: Text(_sending ? '...' : '申請'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryGreen,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.lightGreen,
            child: Text(initial, style: TextStyle(
              color: AppTheme.primaryGreen, fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const Gap(12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(nick, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            Text('Lv. $lv', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ])),
          trailing,
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// 空状態表示
// ─────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message, this.sub});
  final IconData icon;
  final String   message;
  final String?  sub;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 52, color: Colors.grey.shade300),
        const Gap(16),
        Text(message, style: TextStyle(fontSize: 15, color: Colors.grey.shade500, fontWeight: FontWeight.w500)),
        if (sub != null) ...[
          const Gap(6),
          Text(sub!, style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center),
        ],
      ]),
    ),
  );
}
