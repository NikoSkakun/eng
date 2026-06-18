import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/document_format.dart';
import '../../models/library_document.dart';
import '../../models/library_folder.dart';
import '../../state/library_controller.dart';
import '../reader/reader_screen.dart';
import '../reader/text_reader_screen.dart';

const XTypeGroup _docTypeGroup = XTypeGroup(
  label: 'Documents & books',
  extensions: kSupportedImportExtensions,
);

/// The icon shown for a document of the given [format] in the library list.
IconData _iconForFormat(DocumentFormat format) {
  switch (format) {
    case DocumentFormat.pdf:
      return Icons.picture_as_pdf_outlined;
    case DocumentFormat.epub:
    case DocumentFormat.mobi:
    case DocumentFormat.fb2:
      return Icons.auto_stories_outlined;
    case DocumentFormat.html:
    case DocumentFormat.markdown:
      return Icons.article_outlined;
    case DocumentFormat.txt:
    case DocumentFormat.rtf:
    case DocumentFormat.unknown:
      return Icons.description_outlined;
  }
}

// ---------------------------------------------------------------------------
// Shared item operations
// ---------------------------------------------------------------------------

Future<void> _openDoc(
  BuildContext context,
  WidgetRef ref,
  LibraryDocument doc,
) async {
  ref.read(libraryControllerProvider.notifier).recordOpened(doc);
  // Reading is full-screen: push on the root navigator so the reader covers the
  // sidebar. PDFs use the fixed-layout pdfrx reader; every other format uses
  // the reflowable text reader.
  await Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute(
      builder: (_) => doc.format.isReflowable
          ? TextReaderScreen(document: doc)
          : ReaderScreen(document: doc),
    ),
  );
}

void _openFolder(BuildContext context, LibraryFolder folder) {
  // Folder browsing stays inside the Library tab (sidebar remains visible), so
  // this uses the nearest (nested) navigator.
  Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => FolderScreen(folderId: folder.id)));
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

Future<void> _renameFolder(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder folder,
) async {
  final name = await _promptName(
    context,
    title: 'Rename folder',
    label: 'Folder name',
    initial: folder.name,
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    ref
        .read(libraryControllerProvider.notifier)
        .renameFolder(folder, name.trim());
  }
}

/// Confirm-and-delete a folder. Returns true if it was deleted.
Future<bool> _deleteFolder(
  BuildContext context,
  WidgetRef ref,
  LibraryFolder folder,
) async {
  final count = ref.read(libraryControllerProvider).countIn(folder.id);
  final ok = await _confirm(
    context,
    title: 'Delete folder?',
    message: count == 0
        ? '“${folder.name}” will be deleted.'
        : '“${folder.name}” will be deleted. Its $count item(s) move up to the '
              'parent (documents and subfolders are kept).',
    confirmLabel: 'Delete',
  );
  if (ok && context.mounted) {
    ref.read(libraryControllerProvider.notifier).deleteFolder(folder);
    return true;
  }
  return false;
}

/// Move [item] via a folder picker (the menu alternative to drag-and-drop).
Future<void> _moveItem(
  BuildContext context,
  WidgetRef ref,
  LibraryItem item,
) async {
  final choice = await _pickFolder(context, ref, item: item);
  if (choice == null || !context.mounted) return;
  ref
      .read(libraryControllerProvider.notifier)
      .moveItemTo(item: item, targetParentId: choice.folderId);
}

Future<void> _createFolderAt(
  BuildContext context,
  WidgetRef ref,
  int? parentId,
) async {
  final name = await _promptName(
    context,
    title: 'New folder',
    label: 'Folder name',
  );
  if (name != null && name.trim().isNotEmpty && context.mounted) {
    await ref
        .read(libraryControllerProvider.notifier)
        .createFolder(name.trim(), parentId: parentId);
  }
}

/// Open a file picker and import one PDF into [folderId] (root when null).
Future<LibraryDocument?> _pickAndImport(
  BuildContext context,
  WidgetRef ref, {
  int? folderId,
}) async {
  final file = await openFile(acceptedTypeGroups: const [_docTypeGroup]);
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

  Future<void> _onDrop(List<DropItem> items) async {
    setState(() => _dragging = false);
    if (_importing) return;
    final files = items.where((e) => isSupportedImportPath(e.path)).toList();
    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That file type is not supported.')),
      );
      return;
    }
    setState(() => _importing = true);
    final notifier = ref.read(libraryControllerProvider.notifier);
    var imported = 0;
    LibraryDocument? last;
    try {
      for (final f in files) {
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
      ).showSnackBar(SnackBar(content: Text('Imported $imported documents.')));
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    final doc = await _pickAndImport(context, ref);
    if (mounted) setState(() => _importing = false);
    if (doc != null && mounted) await _openDoc(context, ref, doc);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final hasItems = state.countIn(null) > 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _createFolderAt(context, ref, null),
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
        label: const Text('Import'),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) => _onDrop(detail.files),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasItems
                  ? const _LibraryLevel(parentId: null)
                  : _EmptyLibrary(onImport: _importing ? null : _import),
            ),
            if (_dragging) const _DropOverlay(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Folder detail screen (navigate into a folder; supports unlimited nesting)
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

  Future<void> _import() async {
    if (_importing) return;
    setState(() => _importing = true);
    await _pickAndImport(context, ref, folderId: widget.folderId);
    if (mounted) setState(() => _importing = false);
  }

  Future<void> _onDrop(List<DropItem> items) async {
    setState(() => _dragging = false);
    if (_importing) return;
    final files = items.where((e) => isSupportedImportPath(e.path)).toList();
    if (files.isEmpty) return;
    setState(() => _importing = true);
    final notifier = ref.read(libraryControllerProvider.notifier);
    try {
      for (final f in files) {
        await notifier.importFromPath(f.path, folderId: widget.folderId);
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(libraryControllerProvider);
    final folder = state.folderById(widget.folderId);
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Folder')),
        body: const Center(child: Text('This folder no longer exists.')),
      );
    }
    final hasItems = state.countIn(folder.id) > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(folder.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'New folder',
            icon: const Icon(Icons.create_new_folder_outlined),
            onPressed: () => _createFolderAt(context, ref, folder.id),
          ),
          IconButton(
            tooltip: 'Rename folder',
            icon: const Icon(Icons.drive_file_rename_outline),
            onPressed: () => _renameFolder(context, ref, folder),
          ),
          IconButton(
            tooltip: 'Delete folder',
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final deleted = await _deleteFolder(context, ref, folder);
              if (deleted && context.mounted) Navigator.of(context).pop();
            },
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
        label: const Text('Import'),
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (detail) => _onDrop(detail.files),
        child: Stack(
          children: [
            Positioned.fill(
              child: hasItems
                  ? _LibraryLevel(parentId: folder.id)
                  : const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text(
                          'This folder is empty.\nImport a document, drag items in, or '
                          'use “Move to folder…”.',
                          textAlign: TextAlign.center,
                        ),
                      ),
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
// One level of the library: an ordered, drag-and-drop list of items.
// ---------------------------------------------------------------------------

class _LibraryLevel extends ConsumerWidget {
  const _LibraryLevel({required this.parentId});

  final int? parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(libraryControllerProvider).itemsIn(parentId);
    final children = <Widget>[_DropGap(parentId: parentId, index: 0)];
    for (var i = 0; i < items.length; i++) {
      children.add(_ItemRow(key: ValueKey(items[i].key), item: items[i]));
      children.add(_DropGap(parentId: parentId, index: i + 1));
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      children: children,
    );
  }
}

/// A thin reorder drop zone between rows; shows an insertion line while a
/// dragged item hovers over it.
class _DropGap extends ConsumerWidget {
  const _DropGap({required this.parentId, required this.index});

  final int? parentId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<LibraryItem>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => ref
          .read(libraryControllerProvider.notifier)
          .moveItemTo(item: d.data, targetParentId: parentId, gapIndex: index),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: active ? 28 : 14,
          alignment: Alignment.center,
          // A transparent fill keeps the gap hit-testable so the DragTarget
          // actually receives items dropped here (an empty box would not).
          color: Colors.transparent,
          child: active
              ? Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// A folder or document row: draggable by its handle, tappable to open, and (for
/// folders) a drop target that accepts items dropped onto it (move into).
class _ItemRow extends ConsumerWidget {
  const _ItemRow({super.key, required this.item});

  final LibraryItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!item.isFolder) return _rowCard(context, ref, active: false);
    return DragTarget<LibraryItem>(
      onWillAcceptWithDetails: (d) =>
          d.data.key != item.key &&
          ref
              .read(libraryControllerProvider.notifier)
              .canMoveInto(d.data, item.folder!.id),
      onAcceptWithDetails: (d) => ref
          .read(libraryControllerProvider.notifier)
          .moveItemTo(item: d.data, targetParentId: item.folder!.id),
      builder: (context, candidate, rejected) =>
          _rowCard(context, ref, active: candidate.isNotEmpty),
    );
  }

  Widget _rowCard(BuildContext context, WidgetRef ref, {required bool active}) {
    final theme = Theme.of(context);
    final isFolder = item.isFolder;
    final title = isFolder ? item.folder!.name : item.document!.title;

    final leading = isFolder
        ? Icon(Icons.folder, color: theme.colorScheme.primary)
        : Icon(_iconForFormat(item.document!.format));

    final String? subtitle;
    if (isFolder) {
      final count = ref
          .watch(libraryControllerProvider)
          .countIn(item.folder!.id);
      subtitle = '$count item${count == 1 ? '' : 's'}';
    } else {
      final doc = item.document!;
      final parts = <String>[
        if (doc.pageCount > 0) '${doc.pageCount} pages',
        if (doc.lastOpenedAt != null)
          'opened ${DateFormat.yMMMd().add_jm().format(doc.lastOpenedAt!)}',
      ];
      subtitle = parts.isEmpty ? null : parts.join(' · ');
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      color: active
          ? theme.colorScheme.primaryContainer
          : (isFolder ? theme.colorScheme.surfaceContainerHighest : null),
      shape: active
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: theme.colorScheme.primary, width: 2),
            )
          : null,
      child: Row(
        children: [
          // Drag handle — the only place a drag starts, so taps/scrolls are
          // unaffected.
          Draggable<LibraryItem>(
            data: item,
            dragAnchorStrategy: pointerDragAnchorStrategy,
            feedback: _DragFeedback(icon: leading, title: title),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
              child: Icon(Icons.drag_indicator),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => isFolder
                  ? _openFolder(context, item.folder!)
                  : _openDoc(context, ref, item.document!),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: isFolder
                                ? const TextStyle(fontWeight: FontWeight.w600)
                                : null,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.outline,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _itemMenu(context, ref),
        ],
      ),
    );
  }

  Widget _itemMenu(BuildContext context, WidgetRef ref) {
    if (item.isFolder) {
      final folder = item.folder!;
      return PopupMenuButton<String>(
        tooltip: 'Folder actions',
        onSelected: (v) {
          switch (v) {
            case 'open':
              _openFolder(context, folder);
            case 'move':
              _moveItem(context, ref, item);
            case 'rename':
              _renameFolder(context, ref, folder);
            case 'delete':
              _deleteFolder(context, ref, folder);
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'open', child: Text('Open')),
          PopupMenuItem(value: 'move', child: Text('Move to folder…')),
          PopupMenuItem(value: 'rename', child: Text('Rename')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );
    }
    final doc = item.document!;
    return PopupMenuButton<String>(
      onSelected: (v) {
        switch (v) {
          case 'move':
            _moveItem(context, ref, item);
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
    );
  }
}

class _DragFeedback extends StatelessWidget {
  const _DragFeedback({required this.icon, required this.title});

  final Widget icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 8,
      borderRadius: BorderRadius.circular(10),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Container(
        width: 280,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            icon,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Misc widgets
// ---------------------------------------------------------------------------

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
                    'Drop files to add them',
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
              'Import a document — PDF, EPUB, MOBI, FB2, TXT and more — or drag one in '
              'reading. Use the folder button to group documents; drag items by '
              'the handle to reorder them or drop them onto a folder.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onImport,
              icon: const Icon(Icons.add),
              label: const Text('Import'),
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

/// Pick a destination folder for [item], excluding invalid targets (a folder
/// can't move into itself or one of its descendants).
Future<_FolderChoice?> _pickFolder(
  BuildContext context,
  WidgetRef ref, {
  required LibraryItem item,
}) {
  final notifier = ref.read(libraryControllerProvider.notifier);
  final state = ref.read(libraryControllerProvider);
  // Folders shown with an indented path so nesting is legible.
  String pathOf(LibraryFolder f) {
    final parts = <String>[f.name];
    var cur = f.parentId == null ? null : state.folderById(f.parentId!);
    var guard = 0;
    while (cur != null && guard++ < 64) {
      parts.insert(0, cur.name);
      cur = cur.parentId == null ? null : state.folderById(cur.parentId!);
    }
    return parts.join(' / ');
  }

  final targets =
      state.folders.where((f) => notifier.canMoveInto(item, f.id)).toList()
        ..sort(
          (a, b) => pathOf(a).toLowerCase().compareTo(pathOf(b).toLowerCase()),
        );

  return showDialog<_FolderChoice>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Move to folder'),
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        content: SizedBox(
          width: 380,
          child: ListView(
            shrinkWrap: true,
            children: [
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Library (no folder)'),
                onTap: () =>
                    Navigator.of(dialogContext).pop(const _FolderChoice(null)),
              ),
              const Divider(height: 1),
              for (final f in targets)
                ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(pathOf(f)),
                  onTap: () =>
                      Navigator.of(dialogContext).pop(_FolderChoice(f.id)),
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
