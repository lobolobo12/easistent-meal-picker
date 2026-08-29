import 'package:flutter/material.dart';

import '../services/submission_log.dart';
import '../theme.dart';

const _dayNames = <int, String>{
  1: 'Ponedeljek',
  2: 'Torek',
  3: 'Sreda',
  4: 'Četrtek',
  5: 'Petek',
  6: 'Sobota',
  7: 'Nedelja',
};

/// Bottom gutter. The tab bar insets content on its own now, so this is
/// just breathing room at the end of a scroll.
const _navBarPad = 104.0;

class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLog();
  }

  Future<void> _loadLog() async {
    setState(() => _isLoading = true);
    final entries = await SubmissionLog.load();
    entries.sort((a, b) =>
        (b['submittedAt'] as String).compareTo(a['submittedAt'] as String));
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _confirmClear() async {
    if (_entries.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Počisti dnevnik?'),
        content: Text('Izbrisanih bo ${_entries.length} zapisov.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Prekliči'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: kAccentRed),
            child: const Text('Počisti'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await SubmissionLog.clear();
    setState(() => _entries = []);
  }

  String _formatMealDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final dayName = _dayNames[date.weekday] ?? '';
      return '$dayName, ${date.day}. ${date.month}. ${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatTimestamp(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr);
      final h = dt.hour.toString().padLeft(2, '0');
      final m = dt.minute.toString().padLeft(2, '0');
      return '${dt.day}. ${dt.month}. ${dt.year} ob $h:$m';
    } catch (_) {
      return isoStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Dnevnik'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Osveži',
            onPressed: _isLoading ? null : _loadLog,
          ),
          if (_entries.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Počisti',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _entries.isEmpty
              ? _buildEmpty()
              : _buildList(),
    );
  }

  Widget _buildEmpty() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history, size: 56, color: kTextMuted),
          SizedBox(height: 16),
          Text('Ni oddanih izbir',
              style: TextStyle(fontSize: 18, color: kTextMuted)),
          SizedBox(height: 8),
          Text('Oddane izbire iz zavihka Meni\nse bodo prikazale tukaj',
              style: TextStyle(fontSize: 13, color: kTextMuted),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildList() {
    return RefreshIndicator(
      onRefresh: _loadLog,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, _navBarPad),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          final menuName = entry['menuName'] as String? ?? '';
          return _LogCard(
            mealDate:
                _formatMealDate(entry['date'] as String? ?? ''),
            menuName: menuName,
            description: entry['description'] as String? ?? '',
            submittedAt:
                _formatTimestamp(entry['submittedAt'] as String? ?? ''),
            accent: menuColor(menuName),
          );
        },
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final String mealDate;
  final String menuName;
  final String description;
  final String submittedAt;
  final Color accent;

  const _LogCard({
    required this.mealDate,
    required this.menuName,
    required this.description,
    required this.submittedAt,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      margin: const EdgeInsets.only(bottom: 6),
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Color accent strip
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: accent.withAlpha(180),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 13, color: accent.withAlpha(150)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(mealDate,
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: kTextSecondary)),
                        ),
                        PillChip(
                          label: menuName.length > 20
                              ? menuName.substring(0, 20)
                              : menuName,
                          color: accent,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(menuName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: accent,
                          shadows: [
                            Shadow(
                                color: accent.withAlpha(80), blurRadius: 6),
                          ],
                        )),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(description,
                          style: const TextStyle(
                              fontSize: 12, color: kTextSecondary)),
                    ],
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 12, color: kAccentGreen.withAlpha(120)),
                        const SizedBox(width: 4),
                        Text('Oddano: $submittedAt',
                            style: const TextStyle(
                                fontSize: 11, color: kTextMuted)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
