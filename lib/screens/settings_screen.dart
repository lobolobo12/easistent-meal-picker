import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/meal_structure_store.dart';
import '../services/preferences_store.dart';
import '../theme.dart';
import 'scheduler_debug_screen.dart';

/// Bottom gutter. The tab bar insets content on its own now, so this is
/// just breathing room at the end of a scroll.
const _navBarPad = 104.0;

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onLogout;

  const SettingsScreen({super.key, this.onLogout});

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = true;

  List<String> _liked = [];
  List<String> _disliked = [];
  List<String> _autoLiked = [];
  List<String> _autoDisliked = [];
  List<String> _ranking = [];

  final _likedCtrl = TextEditingController();
  final _dislikedCtrl = TextEditingController();

  // Hidden-access counter: 5 taps on the AppBar title opens the debug log.
  // Taps further apart than 1.5s reset the counter.
  int _titleTapCount = 0;
  DateTime? _lastTitleTap;

  void _onTitleTap() {
    final now = DateTime.now();
    if (_lastTitleTap != null &&
        now.difference(_lastTitleTap!).inMilliseconds > 1500) {
      _titleTapCount = 0;
    }
    _lastTitleTap = now;
    _titleTapCount++;
    if (_titleTapCount >= 5) {
      _titleTapCount = 0;
      _openDebugScreen();
    }
  }

  void _openDebugScreen() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const SchedulerDebugScreen()),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _likedCtrl.dispose();
    _dislikedCtrl.dispose();
    super.dispose();
  }

  Future<void> reloadPrefs() async => _loadPrefs();

  Future<void> _loadPrefs() async {
    final prefs = await PreferencesStore.load();
    setState(() {
      _liked = List<String>.from(prefs['liked_keywords'] ?? []);
      _disliked = List<String>.from(prefs['disliked_keywords'] ?? []);
      _autoLiked = List<String>.from(prefs['auto_liked_keywords'] ?? []);
      _autoDisliked = List<String>.from(prefs['auto_disliked_keywords'] ?? []);
      _ranking = List<String>.from(prefs['menu_type_ranking'] ?? []);
      _isLoading = false;
    });
    await _syncRankingWithStructure();
  }

  /// Sync the ranking list with the detected school meal structure.
  /// Adds newly detected menus at the end, removes menus no longer offered.
  Future<void> _syncRankingWithStructure() async {
    final structure = await MealStructureStore.load();
    final detected = List<String>.from(structure['menu_names'] ?? []);
    if (detected.isEmpty) return;

    if (_ranking.isEmpty) {
      setState(() => _ranking = detected);
      _save();
      return;
    }

    // Keep existing order for known menus, append new ones, drop removed
    final detectedSet = detected.toSet();
    final updated = _ranking.where((n) => detectedSet.contains(n)).toList();
    for (final name in detected) {
      if (!updated.contains(name)) updated.add(name);
    }
    if (updated.length != _ranking.length ||
        !_listEquals(updated, _ranking)) {
      setState(() => _ranking = updated);
      _save();
    }
  }

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _save() async {
    await PreferencesStore.save({
      'liked_keywords': _liked,
      'disliked_keywords': _disliked,
      'auto_liked_keywords': _autoLiked,
      'auto_disliked_keywords': _autoDisliked,
      'menu_type_ranking': _ranking,
    });
  }

  void _addKeyword(List<String> list, TextEditingController ctrl) {
    final text = ctrl.text.trim().toLowerCase();
    if (text.isEmpty || list.contains(text)) {
      ctrl.clear();
      return;
    }
    setState(() => list.add(text));
    ctrl.clear();
    _save();
  }

  void _removeKeyword(List<String> list, int index) {
    setState(() => list.removeAt(index));
    _save();
  }

  void _removeAutoKeyword(List<String> list, int index) {
    setState(() => list.removeAt(index));
    _save();
  }

  /// [newIndex] already accounts for the item being lifted out at
  /// [oldIndex] — that is the difference between `onReorderItem` and the
  /// deprecated `onReorder`, which needed the caller to decrement it.
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final item = _ranking.removeAt(oldIndex);
      _ranking.insert(newIndex, item);
    });
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _onTitleTap,
          child: const Text('Nastavitve'),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, _navBarPad),
              children: [
                _buildKeywordSection(
                  title: 'Všečne besede',
                  icon: Icons.thumb_up_outlined,
                  color: kAccentGreen,
                  keywords: _liked,
                  autoKeywords: _autoLiked,
                  controller: _likedCtrl,
                  onAdd: () => _addKeyword(_liked, _likedCtrl),
                  onRemove: (i) => _removeKeyword(_liked, i),
                  onRemoveAuto: (i) => _removeAutoKeyword(_autoLiked, i),
                ),
                const SizedBox(height: 20),
                _buildKeywordSection(
                  title: 'Nevšečne besede',
                  icon: Icons.thumb_down_outlined,
                  color: kAccentRed,
                  keywords: _disliked,
                  autoKeywords: _autoDisliked,
                  controller: _dislikedCtrl,
                  onAdd: () => _addKeyword(_disliked, _dislikedCtrl),
                  onRemove: (i) => _removeKeyword(_disliked, i),
                  onRemoveAuto: (i) =>
                      _removeAutoKeyword(_autoDisliked, i),
                ),
                const SizedBox(height: 20),
                _buildRankingSection(),
                if (widget.onLogout != null) ...[
                  const SizedBox(height: 32),
                  _buildLogoutSection(),
                ],
                const SizedBox(height: 16),
                _buildDebugEntry(),
              ],
            ),
    );
  }

  Widget _buildDebugEntry() {
    return Center(
      child: TextButton.icon(
        onPressed: _openDebugScreen,
        icon: const Icon(Icons.bug_report_outlined,
            size: 16, color: kTextMuted),
        label: const Text('Debug dnevnik',
            style: TextStyle(fontSize: 12, color: kTextMuted)),
      ),
    );
  }

  // ── Logout ──

  Widget _buildLogoutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 1,
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                kAccentRed.withAlpha(0),
                kAccentRed.withAlpha(60),
                kAccentRed.withAlpha(0),
              ],
            ),
          ),
        ),
        Center(
          child: GlassCard(
            radius: 20,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            borderColor: kAccentRed,
            onTap: _confirmLogout,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.logout, size: 18, color: kAccentRed),
                const SizedBox(width: 8),
                Text('Odjava',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: kAccentRed,
                    )),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Odjava'),
        content: const Text('Shranjeni podatki za prijavo bodo izbrisani.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kAccentRed),
            child: const Text('Odjavi se'),
          ),
        ],
      ),
    );
    if (confirmed == true) widget.onLogout?.call();
  }

  // ── Keyword section ──

  Widget _buildKeywordSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> keywords,
    required List<String> autoKeywords,
    required TextEditingController controller,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
    required void Function(int) onRemoveAuto,
  }) {
    final hasAny = keywords.isNotEmpty || autoKeywords.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // iOS puts the section label outside the group, in muted uppercase —
        // the colour belongs to the content, not the heading.
        Padding(
          padding: const EdgeInsets.fromLTRB(kSp16, 0, kSp16, kSp8),
          child: Text(title.toUpperCase(),
              style: kFootnote.copyWith(letterSpacing: 0.5)),
        ),
        GlassCard(
      padding: const EdgeInsets.all(kSp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!hasAny)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Ni besed',
                  style: TextStyle(fontSize: 13, color: kTextMuted)),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (var i = 0; i < keywords.length; i++)
                  _GlassChip(
                    label: keywords[i],
                    color: color,
                    onDelete: () => onRemove(i),
                  ),
                for (var i = 0; i < autoKeywords.length; i++)
                  _GlassChip(
                    label: autoKeywords[i],
                    color: kAccentMauve,
                    icon: Icons.auto_awesome,
                    muted: true,
                    onDelete: () => onRemoveAuto(i),
                  ),
              ],
            ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  style: const TextStyle(fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Dodaj besedo...',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onSubmitted: (_) => onAdd(),
                ),
              ),
              const SizedBox(width: 8),
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: const Size.square(32),
                onPressed: onAdd,
                child: Icon(CupertinoIcons.add_circled_solid,
                    size: 28, color: color),
              ),
            ],
          ),
        ],
      ),
        ),
      ],
    );
  }

  // ── Ranking section ──

  Widget _buildRankingSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(kSp16, 0, kSp16, kSp8),
          child: Text('VRSTNI RED MENIJEV',
              style: kFootnote.copyWith(letterSpacing: 0.5)),
        ),
        GlassCard(
      padding: const EdgeInsets.all(kSp16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Drži in povleci za prerazporeditev',
              style: kCaption),
          const SizedBox(height: kSp12),

          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _ranking.length,
            onReorderItem: _onReorder,
            proxyDecorator: (child, index, animation) {
              return AnimatedBuilder(
                animation: animation,
                builder: (context, child) => Container(
                  decoration: BoxDecoration(
                    color: kBgElevated2,
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: child,
                ),
                child: child,
              );
            },
            itemBuilder: (context, index) {
              final accent = menuColor(_ranking[index]);
              return _RankingTile(
                key: ValueKey(_ranking[index]),
                rank: index + 1,
                name: _ranking[index],
                color: accent,
              );
            },
          ),
        ],
      ),
        ),
      ],
    );
  }
}

class _RankingTile extends StatelessWidget {
  final int rank;
  final String name;
  final Color color;

  const _RankingTile(
      {super.key, required this.rank, required this.name, required this.color});

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 4),
      radius: 12,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              shape: BoxShape.circle,
              border: Border.all(color: color.withAlpha(70), width: 0.5),
            ),
            child: Text(
              '$rank',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(name,
                style: const TextStyle(fontSize: 14, color: kTextPrimary)),
          ),
          ReorderableDragStartListener(
            index: rank - 1,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle, color: kTextMuted, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass chip with blur effect ──

class _GlassChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool muted;
  final VoidCallback onDelete;

  const _GlassChip({
    required this.label,
    required this.color,
    this.icon,
    this.muted = false,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Auto-derived words read one step quieter than ones typed by hand,
    // which is the only distinction needed — the old sparkle icon was noise.
    return Container(
      padding: const EdgeInsets.only(
          left: kSp12, right: kSp4, top: kSp4, bottom: kSp4),
      decoration: BoxDecoration(
        color: muted
            ? kBgElevated2
            : color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 15,
                color: muted ? kLabelSecondary : kLabel,
              )),
          const SizedBox(width: kSp2),
          GestureDetector(
            onTap: onDelete,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(kSp4),
              child: Icon(CupertinoIcons.xmark,
                  size: 11, color: kLabelTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
