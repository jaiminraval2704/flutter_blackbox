import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../adapters/storage/blackbox_storage_adapter.dart';
import '../../blackbox.dart';
import '../widgets/empty_state.dart';

class StoragePanel extends StatefulWidget {
  const StoragePanel({super.key});

  @override
  State<StoragePanel> createState() => _StoragePanelState();
}

class _StoragePanelState extends State<StoragePanel> {
  int _selectedAdapter = 0;
  Map<String, dynamic> _data = {};
  bool _loading = true;
  String _query = '';

  bool _isSensitive(String key) {
    // If developer opted out of redaction, nothing is sensitive
    if (!BlackBox.instance.redactSensitiveData) return false;
    if (_adapters.isEmpty) return false;
    return _adapters[_selectedAdapter].isSensitiveKey(key);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  List<BlackBoxStorageAdapter> get _adapters =>
      BlackBox.instance.storageAdapters;

  Future<void> _loadData() async {
    if (_adapters.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _adapters[_selectedAdapter].readAll();
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _data = {'error': e.toString()};
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteKey(String key) async {
    await _adapters[_selectedAdapter].delete(key);
    if (mounted) _loadData();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('Clear all data?',
            style: TextStyle(fontSize: 13, color: Colors.white)),
        content: Text(
          'This will delete all keys in "${_adapters[_selectedAdapter].name}". This action cannot be undone.',
          style: const TextStyle(fontSize: 12, color: Colors.white60),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All',
                style: TextStyle(color: Color(0xFFE24B4A), fontSize: 12)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _adapters[_selectedAdapter].clear();
      if (mounted) _loadData();
    }
  }

  Future<void> _editValue(String key, dynamic currentValue) async {
    // Block editing of sensitive keys
    if (_isSensitive(key)) return;

    final type = _detectType(currentValue);

    final result = await showDialog<_EditResult>(
      context: context,
      builder: (ctx) => _EditDialog(
        keyName: key,
        initialValue: currentValue.toString(),
        currentType: type,
      ),
    );

    if (result != null && mounted) {
      final parsedValue = _parseValue(result.value, result.type);
      await _adapters[_selectedAdapter].write(key, parsedValue);
      if (mounted) _loadData();
    }
  }

  Future<void> _addNewKey() async {
    final result = await showDialog<_EditResult>(
      context: context,
      builder: (ctx) => const _AddKeyDialog(),
    );

    if (result != null &&
        result.key != null &&
        result.key!.isNotEmpty &&
        mounted) {
      final parsedValue = _parseValue(result.value, result.type);
      await _adapters[_selectedAdapter].write(result.key!, parsedValue);
      if (mounted) _loadData();
    }
  }

  String _detectType(dynamic value) {
    if (value is bool) return 'bool';
    if (value is int) return 'int';
    if (value is double) return 'double';
    if (value is List) return 'List<String>';
    return 'String';
  }

  dynamic _parseValue(String value, String type) {
    return switch (type) {
      'bool' => value.toLowerCase() == 'true',
      'int' => int.tryParse(value) ?? 0,
      'double' => double.tryParse(value) ?? 0.0,
      'List<String>' => value.split(',').map((e) => e.trim()).toList(),
      _ => value,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_adapters.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storage_outlined, color: Colors.white24, size: 32),
            SizedBox(height: 8),
            Text('No storage adapters registered',
                style: TextStyle(fontSize: 12, color: Colors.white38)),
            SizedBox(height: 4),
            Text(
              'Pass storageAdapters to BlackBox.setup()',
              style: TextStyle(fontSize: 10, color: Colors.white24),
            ),
          ],
        ),
      );
    }

    final q = _query.toLowerCase();
    final filteredEntries = _data.entries
        .where(
          (e) =>
              _query.isEmpty ||
              e.key.toLowerCase().contains(q) ||
              e.value.toString().toLowerCase().contains(q),
        )
        .toList();

    return Column(
      children: [
        // ── Adapter selector & toolbar ──────────────────────────────────
        if (_adapters.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: SizedBox(
              height: 30,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _adapters.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (ctx, i) {
                  final isSelected = i == _selectedAdapter;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedAdapter = i);
                      _loadData();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF6C63FF).withValues(alpha: 0.2)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF6C63FF)
                              : Colors.white10,
                          width: 0.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          _adapters[i].name,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

        // ── Search bar & actions ────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: PanelSearchBar(
                  hint: 'Search keys or values…',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addNewKey,
                child: const Icon(Icons.add_circle_outline,
                    color: Colors.white38, size: 18),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _loadData,
                child:
                    const Icon(Icons.refresh, color: Colors.white38, size: 18),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _clearAll,
                child: const Icon(Icons.delete_outline,
                    color: Colors.white38, size: 18),
              ),
            ],
          ),
        ),

        // ── Key count badge ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Builder(builder: (ctx) {
              final sensitiveCount =
                  filteredEntries.where((e) => _isSensitive(e.key)).length;
              return Text(
                '${filteredEntries.length} key${filteredEntries.length == 1 ? '' : 's'}'
                '${sensitiveCount > 0 ? ' · $sensitiveCount redacted' : ''}'
                '${_query.isNotEmpty ? ' (filtered)' : ''}',
                style: const TextStyle(fontSize: 9, color: Colors.white24),
              );
            }),
          ),
        ),

        // ── Key-value list ──────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white38))
              : filteredEntries.isEmpty
                  ? const EmptyState(
                      icon: Icons.search_off,
                      label: 'No keys found',
                      emoji: '🗄️')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      itemCount: filteredEntries.length,
                      itemBuilder: (ctx, i) {
                        final entry = filteredEntries[i];
                        final sensitive = _isSensitive(entry.key);
                        return _StorageTile(
                          keyName: entry.key,
                          value: entry.value,
                          type: _detectType(entry.value),
                          isSensitive: sensitive,
                          onEdit: sensitive
                              ? null
                              : () => _editValue(entry.key, entry.value),
                          onDelete: () => _deleteKey(entry.key),
                          onCopy: sensitive
                              ? null
                              : () => Clipboard.setData(ClipboardData(
                                  text: '${entry.key}: ${entry.value}')),
                        );
                      },
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StorageTile extends StatelessWidget {
  const _StorageTile({
    required this.keyName,
    required this.value,
    required this.type,
    this.isSensitive = false,
    this.onEdit,
    required this.onDelete,
    this.onCopy,
  });

  final String keyName;
  final dynamic value;
  final String type;
  final bool isSensitive;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onCopy;

  static const _redactedValue = '••••••••';

  Color get _typeColor => switch (type) {
        'bool' => Colors.orange,
        'int' => Colors.blue,
        'double' => Colors.cyan,
        'List<String>' => Colors.purple,
        _ => Colors.green,
      };

  @override
  Widget build(BuildContext context) {
    String displayValue;
    if (isSensitive) {
      displayValue = _redactedValue;
    } else {
      displayValue = value.toString();
      if (value is Map || value is List) {
        try {
          displayValue = const JsonEncoder.withIndent('  ').convert(value);
        } catch (_) {}
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isSensitive
            ? Colors.red.withValues(alpha: 0.03)
            : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              isSensitive ? Colors.red.withValues(alpha: 0.15) : Colors.white10,
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: _typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(type,
                    style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w700,
                        color: _typeColor)),
              ),
              // ── Sensitive badge ────────────────────────────────────────
              if (isSensitive) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock, size: 7, color: Colors.redAccent),
                      SizedBox(width: 2),
                      Text('REDACTED',
                          style: TextStyle(
                              fontSize: 6,
                              fontWeight: FontWeight.w800,
                              color: Colors.redAccent)),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  keyName,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white70,
                      fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Copy — disabled for sensitive keys
              if (onCopy != null)
                GestureDetector(
                  onTap: onCopy,
                  child:
                      const Icon(Icons.copy, size: 13, color: Colors.white24),
                )
              else
                const Icon(Icons.copy, size: 13, color: Colors.white10),
              const SizedBox(width: 8),
              // Edit — disabled for sensitive keys
              if (onEdit != null)
                GestureDetector(
                  onTap: onEdit,
                  child:
                      const Icon(Icons.edit, size: 13, color: Colors.white24),
                )
              else
                const Icon(Icons.edit, size: 13, color: Colors.white10),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onDelete,
                child: const Icon(Icons.close, size: 13, color: Colors.white24),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Toggle bool values inline
          if (value is bool && !isSensitive)
            GestureDetector(
              onTap: onEdit,
              child: Row(
                children: [
                  Icon(
                    value == true ? Icons.toggle_on : Icons.toggle_off,
                    color: value == true
                        ? const Color(0xFF1D9E75)
                        : Colors.white24,
                    size: 28,
                  ),
                  const SizedBox(width: 4),
                  Text(value.toString(),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white54,
                          fontFamily: 'monospace')),
                ],
              ),
            )
          else
            Text(
              isSensitive
                  ? _redactedValue
                  : (displayValue.length > 200
                      ? '${displayValue.substring(0, 200)}…'
                      : displayValue),
              style: TextStyle(
                  fontSize: 10,
                  color: isSensitive
                      ? Colors.redAccent.withValues(alpha: 0.5)
                      : Colors.white54,
                  fontFamily: 'monospace',
                  letterSpacing: isSensitive ? 2 : 0,
                  height: 1.4),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialogs
// ─────────────────────────────────────────────────────────────────────────────

class _EditResult {
  _EditResult({this.key, required this.value, required this.type});
  final String? key;
  final String value;
  final String type;
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.keyName,
    required this.initialValue,
    required this.currentType,
  });

  final String keyName;
  final String initialValue;
  final String currentType;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late String _type;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _type = widget.currentType;
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: Text('Edit: ${widget.keyName}',
          style: const TextStyle(fontSize: 13, color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_type == 'bool')
            SwitchListTile(
              title: Text(_controller.text,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              value: _controller.text.toLowerCase() == 'true',
              onChanged: (v) => setState(() => _controller.text = v.toString()),
              activeThumbColor: const Color(0xFF6C63FF),
              contentPadding: EdgeInsets.zero,
            )
          else
            TextField(
              controller: _controller,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              decoration: InputDecoration(
                hintText: 'Value',
                hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
              maxLines: _type == 'String' ? 3 : 1,
              keyboardType: (_type == 'int' || _type == 'double')
                  ? TextInputType.number
                  : TextInputType.text,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
              context, _EditResult(value: _controller.text, type: _type)),
          child: const Text('Save',
              style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
        ),
      ],
    );
  }
}

class _AddKeyDialog extends StatefulWidget {
  const _AddKeyDialog();

  @override
  State<_AddKeyDialog> createState() => _AddKeyDialogState();
}

class _AddKeyDialogState extends State<_AddKeyDialog> {
  String _type = 'String';
  late final TextEditingController _keyController;
  late final TextEditingController _valueController;

  @override
  void initState() {
    super.initState();
    _keyController = TextEditingController();
    _valueController = TextEditingController();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1A2E),
      title: const Text('Add new key',
          style: TextStyle(fontSize: 13, color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _keyController,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            decoration: InputDecoration(
              hintText: 'Key name',
              hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _type,
            dropdownColor: const Color(0xFF1A1A2E),
            style: const TextStyle(fontSize: 12, color: Colors.white70),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white.withValues(alpha: 0.04),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: const [
              DropdownMenuItem(value: 'String', child: Text('String')),
              DropdownMenuItem(value: 'bool', child: Text('bool')),
              DropdownMenuItem(value: 'int', child: Text('int')),
              DropdownMenuItem(value: 'double', child: Text('double')),
            ],
            onChanged: (v) => setState(() => _type = v ?? 'String'),
          ),
          const SizedBox(height: 8),
          if (_type == 'bool')
            SwitchListTile(
              title: Text(
                  _valueController.text.isEmpty
                      ? 'false'
                      : _valueController.text,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
              value: _valueController.text.toLowerCase() == 'true',
              onChanged: (v) =>
                  setState(() => _valueController.text = v.toString()),
              activeThumbColor: const Color(0xFF6C63FF),
              contentPadding: EdgeInsets.zero,
            )
          else
            TextField(
              controller: _valueController,
              style: const TextStyle(fontSize: 12, color: Colors.white70),
              decoration: InputDecoration(
                hintText: 'Value',
                hintStyle: const TextStyle(fontSize: 11, color: Colors.white24),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.04),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none),
              ),
              keyboardType: (_type == 'int' || _type == 'double')
                  ? TextInputType.number
                  : TextInputType.text,
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
              context,
              _EditResult(
                key: _keyController.text,
                value: _valueController.text.isEmpty && _type == 'bool'
                    ? 'false'
                    : _valueController.text,
                type: _type,
              )),
          child: const Text('Add',
              style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
        ),
      ],
    );
  }
}
