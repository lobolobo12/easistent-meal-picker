import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/scheduler_debug_log.dart';
import '../theme.dart';

/// In-app view of the scheduler debug log, since adb is unavailable on
/// Family Link-managed devices.
///
/// Shows the last 200 lines newest-first. The full log is kept on disk
/// (capped at 100 KB by [SchedulerDebugLog]) — older lines beyond the
/// display window are still there for "copy to clipboard" to include.
class SchedulerDebugScreen extends StatefulWidget {
  const SchedulerDebugScreen({super.key});

  @override
  State<SchedulerDebugScreen> createState() => _SchedulerDebugScreenState();
}

class _SchedulerDebugScreenState extends State<SchedulerDebugScreen> {
  static const _maxDisplayLines = 200;
  static const _navBarPad = 104.0;

  String _fullLog = '';
  List<String> _displayLines = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final content = await SchedulerDebugLog.read();
    final lines = content
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList()
        .reversed
        .take(_maxDisplayLines)
        .toList();
    if (!mounted) return;
    setState(() {
      _fullLog = content;
      _displayLines = lines;
      _loading = false;
    });
  }

  Future<void> _copyAll() async {
    if (_fullLog.isEmpty) {
      showCenteredToast(context, 'Dnevnik je prazen.', color: kTextMuted);
      return;
    }
    await Clipboard.setData(ClipboardData(text: _fullLog));
    if (!mounted) return;
    showCenteredToast(context, 'Dnevnik kopiran v odložišče.',
        color: kAccentGreen);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Počisti dnevnik?'),
        content: const Text(
            'Vse obstoječe dnevniške zapise bo izbrisalo. Novi zapisi se bodo še vedno beležili.'),
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
    await SchedulerDebugLog.clear();
    await _reload();
    if (!mounted) return;
    showCenteredToast(context, 'Dnevnik počiščen.', color: kAccentGreen);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: kBgGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Debug dnevnik'),
          actions: [
            IconButton(
              tooltip: 'Osveži',
              icon: const Icon(Icons.refresh),
              onPressed: _loading ? null : _reload,
            ),
            IconButton(
              tooltip: 'Kopiraj',
              icon: const Icon(Icons.copy_all_outlined),
              onPressed: _loading ? null : _copyAll,
            ),
            IconButton(
              tooltip: 'Počisti',
              icon: const Icon(Icons.delete_outline, color: kAccentRed),
              onPressed: _loading ? null : _confirmClear,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _displayLines.isEmpty
                ? _buildEmpty()
                : _buildList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                size: 56, color: kTextMuted),
            const SizedBox(height: 12),
            const Text(
              'Dnevnik je prazen.',
              style: TextStyle(fontSize: 16, color: kTextPrimary),
            ),
            const SizedBox(height: 6),
            const Text(
              'Še ni zapisov. Počakaj na naslednji alarm ali se odjavi in znova prijavi, da sprožiš perm/init zapise.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: kTextSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, _navBarPad),
      itemCount: _displayLines.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) return _buildHeader();
        return _DebugLine(raw: _displayLines[index - 1]);
      },
    );
  }

  Widget _buildHeader() {
    final total = _fullLog.split('\n').where((l) => l.trim().isNotEmpty).length;
    final shown = _displayLines.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        radius: 10,
        child: Text(
          'Prikazanih ${shown < total ? 'zadnjih ' : ''}$shown od $total zapisov (najnovejši zgoraj).',
          style: const TextStyle(fontSize: 12, color: kTextSecondary),
        ),
      ),
    );
  }
}

class _DebugLine extends StatelessWidget {
  final String raw;
  const _DebugLine({required this.raw});

  @override
  Widget build(BuildContext context) {
    // Parse "ISO-8601 | source | message"
    final parts = raw.split(' | ');
    final stamp = parts.isNotEmpty ? parts[0] : '';
    final source = parts.length >= 2 ? parts[1] : '';
    final msg = parts.length >= 3 ? parts.sublist(2).join(' | ') : raw;

    final sourceColor = switch (source) {
      'alarm' => kAccentMauve,
      'perm' => kAccentAmber,
      'init' => kAccentTeal,
      'schedule' => kAccentYellow,
      'notif' => kAccentGreen,
      _ => kTextMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x14FFFFFF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0x20FFFFFF), width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: sourceColor.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: sourceColor.withAlpha(100), width: 0.5),
                      ),
                      child: Text(source.isEmpty ? '?' : source,
                          style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w700,
                              color: sourceColor)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _shortStamp(stamp),
                        style: const TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: kTextMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  msg,
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: kTextPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Format 2026-04-16T20:31:02.123 → 04-16 20:31:02
  String _shortStamp(String iso) {
    try {
      final dt = DateTime.parse(iso);
      String two(int x) => x.toString().padLeft(2, '0');
      return '${two(dt.month)}-${two(dt.day)} '
          '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
    } catch (_) {
      return iso;
    }
  }
}
