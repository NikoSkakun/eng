import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/library_document.dart';
import '../../state/library_controller.dart';
import '../reader/reader_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;

  Future<void> _import() async {
    if (_importing) return;
    const typeGroup = XTypeGroup(
      label: 'PDF',
      extensions: ['pdf'],
      mimeTypes: ['application/pdf'],
      uniformTypeIdentifiers: ['com.adobe.pdf'],
    );
    final file = await openFile(acceptedTypeGroups: [typeGroup]);
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final doc = await ref
          .read(libraryControllerProvider.notifier)
          .importFromPath(file.path);
      if (!mounted) return;
      await _open(doc);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import: $e')));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _open(LibraryDocument doc) async {
    ref.read(libraryControllerProvider.notifier).recordOpened(doc);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ReaderScreen(document: doc)));
  }

  Future<void> _rename(LibraryDocument doc) async {
    final controller = TextEditingController(text: doc.title);
    final newTitle = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename document'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Title'),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (newTitle != null && newTitle.trim().isNotEmpty) {
      ref.read(libraryControllerProvider.notifier).rename(doc, newTitle.trim());
    }
  }

  Future<void> _remove(LibraryDocument doc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove document?'),
        content: Text(
          '“${doc.title}” will be removed from your library and its file deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(libraryControllerProvider.notifier).remove(doc);
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = ref.watch(libraryControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import PDF'),
      ),
      body: docs.isEmpty
          ? _EmptyLibrary(onImport: _importing ? null : _import)
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _DocumentTile(
                doc: docs[i],
                onOpen: () => _open(docs[i]),
                onRename: () => _rename(docs[i]),
                onRemove: () => _remove(docs[i]),
              ),
            ),
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.doc,
    required this.onOpen,
    required this.onRename,
    required this.onRemove,
  });

  final LibraryDocument doc;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final subtitle = <String>[
      if (doc.pageCount > 0) '${doc.pageCount} pages',
      if (doc.lastOpenedAt != null)
        'opened ${DateFormat.yMMMd().add_jm().format(doc.lastOpenedAt!)}',
    ].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.picture_as_pdf_outlined)),
        title: Text(doc.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isEmpty
            ? null
            : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onOpen,
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'rename':
                onRename();
              case 'remove':
                onRemove();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});
  final VoidCallback? onImport;

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
              Icons.menu_book_outlined,
              size: 72,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text('Your library is empty', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Import a PDF to start reading. Select an unknown word or phrase '
              'to add a translation — it will be highlighted everywhere it appears.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import PDF'),
            ),
          ],
        ),
      ),
    );
  }
}
