import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dictionary_entry.dart';
import '../../models/library_document.dart';
import '../../models/usage.dart';
import '../../services/contexts/usage_indexer.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../reader/reader_screen.dart';
import '../reader/text_reader_screen.dart';

/// Full-screen "concordance" for a dictionary term: the paragraphs / snippets
/// where the term occurs across the library, served from the persistent usage
/// cache (so it opens instantly), with a per-source filter and tap-to-jump.
///
/// Opening the screen also asks the [UsageIndexer] to fill any not-yet-scanned
/// documents in the background; results appear as they are indexed.
class WordContextsScreen extends ConsumerStatefulWidget {
  const WordContextsScreen({super.key, required this.entry});

  final DictionaryEntry entry;

  @override
  ConsumerState<WordContextsScreen> createState() => _WordContextsScreenState();
}

class _WordContextsScreenState extends ConsumerState<WordContextsScreen> {
  late final UsageIndexer _indexer;

  /// Documents currently shown (defaults to all).
  late Set<int> _selected;
  List<Usage> _usages = const [];
  Set<int> _indexedDocs = const {};

  @override
  void initState() {
    super.initState();
    _indexer = ref.read(usageIndexerProvider);
    _selected = {
      for (final d in ref.read(libraryControllerProvider).documents) d.id,
    };
    _reload();
    _indexer.revision.addListener(_reload);
    // Fill any documents not yet scanned for this term (resumes an interrupted
    // background pass / picks up newly imported documents).
    _indexer.ensureEntryIndexed(widget.entry);
  }

  @override
  void dispose() {
    _indexer.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    final repo = ref.read(usageRepositoryProvider);
    setState(() {
      _usages = repo.forEntry(widget.entry.id);
      _indexedDocs = repo.indexedDocsForEntry(widget.entry.id);
    });
  }

  Future<void> _pickSources() async {
    final docs = ref.read(libraryControllerProvider).documents;
    final result = await showDialog<Set<int>>(
      context: context,
      builder: (_) => _SourcePickerDialog(documents: docs, selected: _selected),
    );
    if (result != null && mounted) setState(() => _selected = result);
  }

  void _open(Usage u, LibraryDocument doc) {
    ref.read(libraryControllerProvider.notifier).recordOpened(doc);
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => doc.format.isReflowable
            ? TextReaderScreen(document: doc, initialBlockIndex: u.blockIndex)
            : ReaderScreen(document: doc, initialPage: u.page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docsById = {
      for (final d in ref.watch(libraryControllerProvider).documents) d.id: d,
    };
    final selectedIds = _selected.where(docsById.containsKey).toSet();
    final indexedSelected = selectedIds.where(_indexedDocs.contains).length;
    final indexing = indexedSelected < selectedIds.length;
    final visible = _usages
        .where((u) => _selected.contains(u.documentId))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('“${widget.entry.term}”'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: _pickSources,
              icon: const Icon(Icons.filter_list),
              label: Text('Sources ${selectedIds.length}/${docsById.length}'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          if (indexing)
            _IndexProgress(done: indexedSelected, total: selectedIds.length)
          else if (visible.isNotEmpty)
            _CountBar(count: visible.length),
          Expanded(child: _body(theme, visible, docsById, indexing)),
        ],
      ),
    );
  }

  Widget _body(
    ThemeData theme,
    List<Usage> visible,
    Map<int, LibraryDocument> docsById,
    bool indexing,
  ) {
    if (visible.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) {
          final u = visible[i];
          final doc = docsById[u.documentId];
          if (doc == null) return const SizedBox.shrink();
          return _ContextCard(
            usage: u,
            sourceTitle: doc.title,
            onTap: () => _open(u, doc),
          );
        },
      );
    }
    if (indexing) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('Searching your library…'),
        ),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _selected.isEmpty
              ? 'No sources selected — choose some from “Sources”.'
              : 'No occurrences of “${widget.entry.term}” found in the selected sources.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ContextCard extends StatelessWidget {
  const _ContextCard({
    required this.usage,
    required this.sourceTitle,
    required this.onTap,
  });

  final Usage usage;
  final String sourceTitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge ?? const TextStyle();
    final highlight = base.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
    );
    final label = usage.page != null
        ? '$sourceTitle · p. ${usage.page}'
        : sourceTitle;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: _spans(usage.snippet, usage.highlights, base, highlight),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    size: 14,
                    color: theme.colorScheme.outline,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  TextSpan _spans(
    String text,
    List<({int start, int end})> spans,
    TextStyle base,
    TextStyle highlight,
  ) {
    final children = <TextSpan>[];
    var i = 0;
    final sorted = [...spans]..sort((a, b) => a.start.compareTo(b.start));
    for (final s in sorted) {
      var st = s.start;
      var en = s.end;
      if (st < i) st = i; // clip overlap with a prior span
      if (st < 0) st = 0;
      if (en > text.length) en = text.length;
      if (en <= st) continue;
      if (st > i) children.add(TextSpan(text: text.substring(i, st)));
      children.add(TextSpan(text: text.substring(st, en), style: highlight));
      i = en;
    }
    if (i < text.length) children.add(TextSpan(text: text.substring(i)));
    return TextSpan(style: base, children: children);
  }
}

class _IndexProgress extends StatelessWidget {
  const _IndexProgress({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          const SizedBox(height: 4),
          Text(
            'Indexing $done / $total sources…',
            style: theme.textTheme.labelSmall,
          ),
        ],
      ),
    );
  }
}

class _CountBar extends StatelessWidget {
  const _CountBar({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$count ${count == 1 ? 'context' : 'contexts'}',
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ),
    );
  }
}

class _SourcePickerDialog extends StatefulWidget {
  const _SourcePickerDialog({required this.documents, required this.selected});

  final List<LibraryDocument> documents;
  final Set<int> selected;

  @override
  State<_SourcePickerDialog> createState() => _SourcePickerDialogState();
}

class _SourcePickerDialogState extends State<_SourcePickerDialog> {
  late Set<int> _sel;

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sources'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(
                    () => _sel = {for (final d in widget.documents) d.id},
                  ),
                  child: const Text('All'),
                ),
                TextButton(
                  onPressed: () => setState(() => _sel = {}),
                  child: const Text('None'),
                ),
              ],
            ),
            const Divider(height: 1),
            Flexible(
              child: widget.documents.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Your library is empty.'),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final d in widget.documents)
                          CheckboxListTile(
                            dense: true,
                            value: _sel.contains(d.id),
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                _sel.add(d.id);
                              } else {
                                _sel.remove(d.id);
                              }
                            }),
                            title: Text(
                              d.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            secondary: Icon(
                              d.format.isPdf
                                  ? Icons.picture_as_pdf_outlined
                                  : Icons.menu_book_outlined,
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _sel),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
