import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/library_document.dart';
import '../../models/library_folder.dart';
import '../../state/library_controller.dart';
import '../reader/reader_screen.dart';

const XTypeGroup _pdfTypeGroup = XTypeGroup(
  label: 'PDF',
  extensions: ['pdf'],
  mimeTypes: ['application/pdf'],
  uniformTypeIdentifiers: ['com.adobe.pdf'],
);

// ---------------------------------------------------------------------------
// Shared document/folder operations (used by both the root and folder views).
// ---------------------------------------------------------------------------

Future<void> _openDoc(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
  ref.read(libraryControllerProvider.notifier).recordOpened(doc);
  await Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => ReaderScreen(document: doc)));
}

Future<void> _renameDoc(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
  final name = await _promptName(
    context,
    title: 'Rename document',
    label: 'Title',
    initial: doc.title,
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    ref.read(libraryControllerProvider.notifier).rename(doc, name.trim());
  }
}

Future<void> _removeDoc(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
  final ok = await _confirm(
    context,
    title: 'Remove document?',
    message:
        '“${doc.title}” will be removed from your library and its file deleted.',
    confirmLabel: 'Remove',
  );
  if (ok && context.mounted) {
    await ref.read(libraryControllerProvider.notifier).remove(doc);
  }
}

Future<void> _moveDoc(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
  final choice = await _pickFolder(context, ref, currentFolderId: doc.folderId);
  if (choice == null || !context.mounted) return; // cancelled or gone
  ref
      .read(libraryControllerProvider.notifier)
      .moveToFolder(doc, choice.folderId);
}

/// Open a file picker and import one PDF into [folderId] (root when null).
Future<LibraryDocument?> _pickAndImport(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  final file = await openFile(acceptedTypeGroups: const [_pdfTypeGroup]);
  if (file == null) return null;
  try {
    return await ref
        .read(libraryControllerProvider.notifier)
        .importFromPath(file.path, folderId: folderId);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not import: $e')));
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Root library screen
// ---------------------------------------------------------------------------

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _importing = false;
  bool _dragging = false;
  final Set<int> _expanded = {};

  Future<void> _onDrop(List<DropItem> items) async {
    setState(() => _dragging = false);
    if (_importing) return;
    final pdfs = items
        .where((e) => e.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (pdfs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only PDF files can be added.')),
      );
      return;
    }
    setState(() => _importing = true);
    final notifier = ref.read(libraryControllerProvider.notifier);
    var imported = 0;
    LibraryDocument? last;
    try {
      for (final f in pdfs) {
        last = await notifier.importFromPath(f.path);
        imported++;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not import: $e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
    if (!mounted) return;
    if (imported == 1 && last != null) {
      await _openDoc(context, ref, last);
    } else if (imported > 1) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Imported $imported PDFs.')));
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    final doc = await _pickAndImport(context, ref);
    if (mounted) setState(() => _importing = false);
    if (doc != null && mounted) await _openDoc(context, ref, doc);
  }

  Future<void> _newFolder() async {
    final name = await _promptName(
      context,
      title: 'New folder',
      label: 'Folder name',
    );
    if (name != null && name.trim().isNotEmpty) {
      final folder = await ref
          .read(libraryControllerProvider.notifier)
          .createFolder(name.trim());
      if (mounted) setState(() => _expanded.add(folder.id));
    }
  }

  Future<void> _renameFolder(LibraryFolder folder) async {
    final name = await _promptName(
      context,
      title: 'Rename folder',
      label: 'Folder name',
      initial: folder.name,
    );
    if (name != null && name.trim().isNotEmpty) {
      ref
          .read(libraryControllerProvider.notifier)
          .renameFolder(folder, name.trim());
    }
  }

  Future<void> _deleteFolder(LibraryFolder folder, int count) async {
    final ok = await _confirm(
      context,
      title: 'Delete folder?',
      message: count == 0
          ? '“${folder.name}” will be deleted.'
          : '“${folder.name}” will be deleted. Its $count document(s) move back '
                'to the library (the files are kept).',
      confirmLabel: 'Delete',
    );
    if (ok) ref.read(libraryControllerProvider.notifier).deleteFolder(folder);
  }

  void _openFolder(LibraryFolder folder) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => FolderScreen(folderId: folder.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final folders = state.folders;
    final rootDocs = state.rootDocuments;
    final isEmpty = folders.isEmpty && state.documents.isEmpty;

    final children = <Widget>[];
    for (final folder in folders) {
      final count = state.countIn(folder.id);
      final expanded = _expanded.contains(folder.id);
      children.add(
        _FolderTile(
          folder: folder,
          count: count,
          expanded: expanded,
          onToggle: () => setState(
            () => expanded
                ? _expanded.remove(folder.id)
                : _expanded.add(folder.id),
          ),
          onOpen: () => _openFolder(folder),
          onRename: () => _renameFolder(folder),
          onDelete: () => _deleteFolder(folder, count),
        ),
      );
      if (expanded) {
        final docs = state.documentsIn(folder.id);
        if (docs.isEmpty) {
          children.add(const _IndentedHint('No documents in this folder yet.'));
        } else {
          for (final doc in docs) {
            children.add(
              Padding(
                padding: const EdgeInsets.only(left: 24),
                child: _DocumentTile(doc: doc),
              ),
            );
          }
        }
      }
    }

    if (rootDocs.isNotEmpty) {
      if (folders.isNotEmpty) {
        children.add(const _SectionLabel('Ungrouped'));
      }
      for (final doc in rootDocs) {
        children.add(_DocumentTile(doc: doc));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: _newFolder,
          ),
        ],
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'libraryImportFab',
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import PDF'),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) => _onDrop(detail.files),
        child: Stack(
          children: [
            Positioned.fill(
              child: isEmpty
                  ? _EmptyLibrary(onImport: _importing ? null : _import)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      children: children,
                    ),
            ),
            if (_dragging) const _DropOverlay(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folder detail screen (navigate into a folder)
// ---------------------------------------------------------------------------

class FolderScreen extends ConsumerStatefulWidget {
  const FolderScreen({super.key, required this.folderId});

  final int folderId;

  @override
  ConsumerState<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends ConsumerState<FolderScreen> {
  bool _importing = false;
  bool _dragging = false;

  LibraryFolder? _folderFrom(LibraryState state) {
    for (final f in state.folders) {
      if (f.id == widget.folderId) return f;
    }
    return null;
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    await _pickAndImport(context, ref, folderId: widget.folderId);
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _onDrop(List<DropItem> items) async {
    setState(() => _dragging = false);
    if (_importing) return;
    final pdfs = items
        .where((e) => e.path.toLowerCase().endsWith('.pdf'))
        .toList();
    if (pdfs.isEmpty) return;
    setState(() => _importing = true);
    final notifier = ref.read(libraryControllerProvider.notifier);
    try {
      for (final f in pdfs) {
        await notifier.importFromPath(f.path, folderId: widget.folderId);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _rename(LibraryFolder folder) async {
    final name = await _promptName(
      context,
      title: 'Rename folder',
      label: 'Folder name',
      initial: folder.name,
    );
    if (name != null && name.trim().isNotEmpty) {
      ref
          .read(libraryControllerProvider.notifier)
          .renameFolder(folder, name.trim());
    }
  }

  Future<void> _delete(LibraryFolder folder, int count) async {
    final ok = await _confirm(
      context,
      title: 'Delete folder?',
      message: count == 0
          ? '“${folder.name}” will be deleted.'
          : '“${folder.name}” will be deleted. Its $count document(s) move back '
                'to the library (the files are kept).',
      confirmLabel: 'Delete',
    );
    if (ok) {
      ref.read(libraryControllerProvider.notifier).deleteFolder(folder);
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final folder = _folderFrom(state);
    if (folder == null) {
      // Folder was deleted while open.
      return Scaffold(
        appBar: AppBar(title: const Text('Folder')),
        body: const Center(child: Text('This folder no longer exists.')),
      );
    }
    final docs = state.documentsIn(folder.id);

    return Scaffold(
      appBar: AppBar(
        title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Rename folder',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () => _rename(folder),
          ),
          IconButton(
            tooltip: 'Delete folder',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(folder, docs.length),
          ),
        ],
        bottom: _importing
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(),
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'folderImportFab',
        onPressed: _importing ? null : _import,
        icon: const Icon(Icons.add),
        label: const Text('Import PDF'),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) => _onDrop(detail.files),
        child: Stack(
          children: [
            Positioned.fill(
              child: docs.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'This folder is empty.\nImport a PDF, or move documents '
                          'here with “Move to folder…”.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                      children: [
                        for (final doc in docs) _DocumentTile(doc: doc),
                      ],
                    ),
            ),
            if (_dragging) const _DropOverlay(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folder row (root view): expand via the triangle, open via double-click.
// ---------------------------------------------------------------------------

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.folder,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
  });

  final LibraryFolder folder;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      color: scheme.surfaceContainerHighest,
      // ListTile.onTap handles the single-tap toggle (and correctly lets the
      // leading/trailing buttons receive their own taps); the GestureDetector
      // only adds double-tap-to-open on top.
      child: GestureDetector(
        onDoubleTap: onOpen,
        child: ListTile(
          onTap: onToggle,
          leading: IconButton(
            tooltip: expanded ? 'Collapse' : 'Expand',
            icon: Icon(expanded ? Icons.expand_more : Icons.chevron_right),
            onPressed: onToggle,
          ),
          title: Row(
            children: [
              Icon(Icons.folder, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          subtitle: Text('$count document${count == 1 ? '' : 's'}'),
          trailing: PopupMenuButton<String>(
            tooltip: 'Folder actions',
            onSelected: (v) {
              switch (v) {
                case 'open':
                  onOpen();
                case 'rename':
                  onRename();
                case 'delete':
                  onDelete();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'open', child: Text('Open')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.doc});

  final LibraryDocument doc;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onTap: () => _openDoc(context, ref, doc),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'move':
                _moveDoc(context, ref, doc);
              case 'rename':
                _renameDoc(context, ref, doc);
              case 'remove':
                _removeDoc(context, ref, doc);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            PopupMenuItem(value: 'rename', child: Text('Rename')),
            PopupMenuItem(value: 'remove', child: Text('Remove')),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

class _IndentedHint extends StatelessWidget {
  const _IndentedHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 4, 12, 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    );
  }
}

class _DropOverlay extends StatelessWidget {
  const _DropOverlay();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary, width: 2),
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.file_download_outlined,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Drop PDF files to add them',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
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
              'Import a PDF — or drag one in from your file manager — to start '
              'reading. Use the folder button to group documents.',
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

// ---------------------------------------------------------------------------
// Shared dialogs
// ---------------------------------------------------------------------------

/// A folder choice returned by [_pickFolder]; folderId null means library root.
class _FolderChoice {
  const _FolderChoice(this.folderId);
  final int? folderId;
}

Future<_FolderChoice?> _pickFolder(
  BuildContext context,
  WidgetRef ref, {
  required int? currentFolderId,
}) {
  final state = ref.read(libraryControllerProvider);
  return showDialog<_FolderChoice>(
    context: context,
    builder: (dialogContext) {
      Widget option(int? id, String label, IconData icon) {
        final selected = id == currentFolderId;
        return ListTile(
          leading: Icon(icon),
          title: Text(label),
          trailing: selected ? const Icon(Icons.check) : null,
          onTap: () => Navigator.of(dialogContext).pop(_FolderChoice(id)),
        );
      }

      return AlertDialog(
        title: const Text('Move to folder'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 360,
          child: ListView(
            shrinkWrap: true,
            children: [
              option(null, 'Library (no folder)', Icons.home_outlined),
              const Divider(height: 1),
              for (final f in state.folders)
                option(f.id, f.name, Icons.folder_outlined),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.create_new_folder_outlined),
                title: const Text('New folder…'),
                onTap: () async {
                  final name = await _promptName(
                    dialogContext,
                    title: 'New folder',
                    label: 'Folder name',
                  );
                  if (name == null || name.trim().isEmpty) return;
                  final folder = await ref
                      .read(libraryControllerProvider.notifier)
                      .createFolder(name.trim());
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop(_FolderChoice(folder.id));
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );
}

/// Prompt for a single line of text; returns null on cancel.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
