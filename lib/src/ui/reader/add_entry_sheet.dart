import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/dictionary_entry.dart';
import '../../services/translation/translation_models.dart';
import '../../state/dictionary_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/providers.dart';
import '../../util/languages.dart';

/// Bottom sheet for adding a new dictionary entry (from a selected word/phrase)
/// or editing an existing one. Auto-suggests a translation and can look up a
/// definition, while always leaving room for the user's own wording.
class AddEntrySheet extends ConsumerStatefulWidget {
  const AddEntrySheet({
    super.key,
    required this.documentId,
    this.initialTerm = '',
    this.existing,
  });

  final int documentId;
  final String initialTerm;
  final DictionaryEntry? existing;

  /// Show the sheet; resolves to true if an entry was saved.
  static Future<bool?> show(
    BuildContext context, {
    required int documentId,
    String initialTerm = '',
    DictionaryEntry? existing,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: AddEntrySheet(
          documentId: documentId,
          initialTerm: initialTerm,
          existing: existing,
        ),
      ),
    );
  }

  @override
  ConsumerState<AddEntrySheet> createState() => _AddEntrySheetState();
}

class _AddEntrySheetState extends ConsumerState<AddEntrySheet> {
  late final TextEditingController _term;
  late final TextEditingController _translation;
  late final TextEditingController _definition;
  late final TextEditingController _notes;

  late bool _global;
  late bool _highlight;

  bool _loadingSuggestion = false;
  bool _loadingDefinition = false;
  List<String> _suggestions = const [];
  String? _suggestionError;
  String? _definitionError;
  String? _phonetic;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _term = TextEditingController(text: e?.term ?? widget.initialTerm.trim());
    _translation = TextEditingController(text: e?.translation ?? '');
    _definition = TextEditingController(text: e?.definition ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    _global = e?.isGlobal ?? true;
    _highlight = e?.highlightEnabled ?? true;

    // Auto-suggest only for brand-new entries when enabled.
    if (e == null && _term.text.isNotEmpty) {
      final settings = ref.read(settingsControllerProvider);
      if (settings.autoSuggestEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSuggestion());
      }
    }
  }

  @override
  void dispose() {
    _term.dispose();
    _translation.dispose();
    _definition.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _fetchSuggestion() async {
    final term = _term.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _loadingSuggestion = true;
      _suggestionError = null;
    });
    try {
      final result = await ref
          .read(translationServiceProvider)
          .suggestTranslation(term);
      if (!mounted) return;
      final all = <String>[
        result.translatedText,
        ...result.alternatives,
      ].where((s) => s.trim().isNotEmpty).toList();
      setState(() {
        _suggestions = all;
        if (_translation.text.trim().isEmpty && all.isNotEmpty) {
          _translation.text = all.first;
        }
      });
    } on ProviderException catch (e) {
      if (mounted) setState(() => _suggestionError = e.message);
    } catch (e) {
      if (mounted) setState(() => _suggestionError = '$e');
    } finally {
      if (mounted) setState(() => _loadingSuggestion = false);
    }
  }

  Future<void> _fetchDefinition() async {
    final term = _term.text.trim();
    if (term.isEmpty) return;
    setState(() {
      _loadingDefinition = true;
      _definitionError = null;
    });
    try {
      final result = await ref
          .read(translationServiceProvider)
          .lookupDefinition(term);
      if (!mounted) return;
      if (result == null || result.isEmpty) {
        setState(() => _definitionError = 'No definition found.');
        return;
      }
      setState(() {
        _phonetic = result.phonetic;
        final formatted = _formatDefinition(result);
        if (_definition.text.trim().isEmpty) {
          _definition.text = formatted;
        } else {
          _definition.text = '${_definition.text.trimRight()}\n$formatted';
        }
      });
    } on ProviderException catch (e) {
      if (mounted) setState(() => _definitionError = e.message);
    } catch (e) {
      if (mounted) setState(() => _definitionError = '$e');
    } finally {
      if (mounted) setState(() => _loadingDefinition = false);
    }
  }

  static String _formatDefinition(DefinitionResult r) {
    final b = StringBuffer();
    for (final sense in r.senses.take(3)) {
      for (final item in sense.items.take(2)) {
        final pos = sense.partOfSpeech.isEmpty
            ? ''
            : '(${sense.partOfSpeech}) ';
        b.writeln('$pos${item.definition}');
        if (item.example != null && item.example!.isNotEmpty) {
          b.writeln('   “${item.example}”');
        }
      }
    }
    return b.toString().trim();
  }

  Future<void> _save() async {
    final term = _term.text.trim();
    if (term.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Enter a word or phrase.')));
      return;
    }
    final settings = ref.read(settingsControllerProvider);
    final now = DateTime.now();
    String? orNull(TextEditingController c) =>
        c.text.trim().isEmpty ? null : c.text.trim();
    final scope = _global ? null : widget.documentId;

    final base = widget.existing;
    final DictionaryEntry entry = base == null
        ? DictionaryEntry(
            id: 0,
            term: term,
            sourceLang: settings.learningLang,
            targetLang: settings.nativeLang,
            translation: orNull(_translation),
            definition: orNull(_definition),
            notes: orNull(_notes),
            highlightEnabled: _highlight,
            scopeDocumentId: scope,
            createdAt: now,
            updatedAt: now,
          )
        : base.copyWith(
            term: term,
            translation: orNull(_translation),
            definition: orNull(_definition),
            notes: orNull(_notes),
            highlightEnabled: _highlight,
            scopeDocumentId: scope,
            updatedAt: now,
          );

    await ref.read(dictionaryControllerProvider.notifier).save(entry);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    final src = languageForCode(settings.learningLang);
    final dst = languageForCode(settings.nativeLang);
    final definitionsAvailable = settings.definitionsAvailable;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  isEditing ? 'Edit entry' : 'Add to dictionary',
                  style: theme.textTheme.titleLarge,
                ),
                const Spacer(),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text('${src.englishName} → ${dst.nativeName}'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _term,
              decoration: InputDecoration(
                labelText: 'Word or phrase',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: 'Suggest translation',
                  onPressed: _loadingSuggestion ? null : _fetchSuggestion,
                  icon: _loadingSuggestion
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _translation,
              decoration: const InputDecoration(
                labelText: 'Translation',
                border: OutlineInputBorder(),
              ),
            ),
            if (_suggestionError != null) ...[
              const SizedBox(height: 6),
              Text(
                _suggestionError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            if (_suggestions.length > 1) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _suggestions.take(6))
                    ActionChip(
                      label: Text(s),
                      onPressed: () => setState(() => _translation.text = s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _definition,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: 'Definition / notes on meaning',
                helperText: _phonetic == null
                    ? null
                    : 'Pronunciation: $_phonetic',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: (!definitionsAvailable || _loadingDefinition)
                      ? null
                      : _fetchDefinition,
                  icon: _loadingDefinition
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.menu_book_outlined),
                  label: Text(
                    definitionsAvailable
                        ? 'Look up definition'
                        : 'Definitions unavailable for ${src.englishName}',
                  ),
                ),
              ],
            ),
            if (_definitionError != null)
              Text(
                _definitionError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            const SizedBox(height: 4),
            TextField(
              controller: _notes,
              decoration: const InputDecoration(
                labelText: 'Personal notes (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _highlight,
              onChanged: (v) => setState(() => _highlight = v),
              title: const Text('Highlight this term'),
            ),
            if (widget.documentId > 0)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: !_global,
                onChanged: (v) => setState(() => _global = !v),
                title: const Text('Only in this document'),
                subtitle: const Text('Off = shared across the whole library'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(isEditing ? 'Save' : 'Add'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
