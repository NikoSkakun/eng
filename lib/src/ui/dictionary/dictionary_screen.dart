import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dictionary_entry.dart';
import '../../state/dictionary_controller.dart';
import '../reader/add_entry_sheet.dart';

class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});

  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  String _query = '';

  Future<void> _edit(DictionaryEntry entry) async {
    await AddEntrySheet.show(
      context,
      documentId: entry.scopeDocumentId ?? 0,
      existing: entry,
    );
  }

  Future<void> _addManual() async {
    await AddEntrySheet.show(context, documentId: 0);
  }

  Future<void> _delete(DictionaryEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete entry?'),
        content: Text('“${entry.term}” will be removed from the dictionary.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(dictionaryControllerProvider.notifier).delete(entry.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(dictionaryControllerProvider);
    final q = _query.trim().toLowerCase();
    final entries = q.isEmpty
        ? state.entries
        : state.entries
              .where(
                (e) =>
                    e.term.toLowerCase().contains(q) ||
                    (e.translation?.toLowerCase().contains(q) ?? false),
              )
              .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Dictionary')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'dictionaryAddFab',
        onPressed: _addManual,
        icon: const Icon(Icons.add),
        label: const Text('Add word'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search terms or translations',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (entries.isEmpty)
            const Expanded(child: _EmptyDictionary())
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
                itemCount: entries.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, i) => _EntryTile(
                  entry: entries[i],
                  onTap: () => _edit(entries[i]),
                  onDelete: () => _delete(entries[i]),
                  onToggleHighlight: () => ref
                      .read(dictionaryControllerProvider.notifier)
                      .toggleHighlight(entries[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    required this.onDelete,
    required this.onToggleHighlight,
  });

  final DictionaryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleHighlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitleParts = <String>[
      if (entry.translation != null && entry.translation!.isNotEmpty)
        entry.translation!,
      if (!entry.isGlobal) 'this document only',
    ];
    return ListTile(
      title: Text(entry.term, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: subtitleParts.isEmpty
          ? null
          : Text(
              subtitleParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: onTap,
      leading: IconButton(
        tooltip: entry.highlightEnabled
            ? 'Highlighting on'
            : 'Highlighting off',
        icon: Icon(
          entry.highlightEnabled ? Icons.highlight : Icons.highlight_off,
          color: entry.highlightEnabled
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        onPressed: onToggleHighlight,
      ),
      trailing: IconButton(
        tooltip: 'Delete',
        icon: const Icon(Icons.delete_outline),
        onPressed: onDelete,
      ),
    );
  }
}

class _EmptyDictionary extends StatelessWidget {
  const _EmptyDictionary();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.translate_outlined,
              size: 64,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('No words yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Words you add while reading appear here. They are highlighted in every '
              'document by default.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
