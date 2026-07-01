import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/settings_store.dart';
import '../../models/dictionary_entry.dart';
import '../../services/translation/translation_models.dart';
import '../../state/dictionary_controller.dart';
import '../../state/settings_controller.dart';
import '../../state/providers.dart';
import '../../text/text_normalizer.dart';
import '../../util/languages.dart';

/// Bottom sheet for adding a new dictionary entry (from a selected word/phrase)
/// or editing an existing one. Auto-suggests a translation and can look up a
/// definition, while always leaving room for the user's own wording.
class AddEntrySheet extends ConsumerStatefulWidget {
  const AddEntrySheet({
    super.key,
    required this.documentId,
    this.initialTerm = '',
    this.initialSourceWord,
    this.contextPassage,
    this.existing,
  });

  final int documentId;
  final String initialTerm;

  /// The longer word [initialTerm] was selected from, when it was a partial
  /// in-word selection. Defaults the new entry to sub-word matching.
  final String? initialSourceWord;

  /// The paragraph/passage the selection came from, when opened from a reader.
  /// When DeepL is the active provider, the sheet shows this passage and its
  /// DeepL translation so the term can be seen in its specific context.
  final String? contextPassage;

  final DictionaryEntry? existing;

  /// Show the sheet; resolves to true if an entry was saved.
  static Future<bool?> show(
    BuildContext context, {
    required int documentId,
    String initialTerm = '',
    String? initialSourceWord,
    String? contextPassage,
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
          initialSourceWord: initialSourceWord,
          contextPassage: contextPassage,
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

  /// One editable row per alternative translation (besides the primary one in
  /// [_translation]). Disposed with the sheet; rows removed by the user are
  /// disposed after the frame in [_removeAlternativeAt].
  final List<TextEditingController> _altControllers = [];

  late bool _global;
  late bool _highlight;
  late bool _matchPartial;
  String? _sourceWord;

  bool _loadingSuggestion = false;
  bool _loadingDefinition = false;
  List<String> _suggestions = const [];
  String? _suggestionError;
  String? _definitionError;
  String? _phonetic;

  /// Id of the provider that produced the current translation suggestion, used
  /// to mark the field as coming from DeepL.
  String? _suggestionProviderId;

  // In-context (paragraph) translation by DeepL.
  bool _loadingContext = false;
  String? _contextTranslation;
  String? _contextError;

  /// Whether the editing-time DeepL suggestion panel has been requested.
  bool _showDeepLPanel = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _term = TextEditingController(text: e?.term ?? widget.initialTerm.trim());
    _translation = TextEditingController(text: e?.translation ?? '');
    _definition = TextEditingController(text: e?.definition ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    for (final alt in e?.alternativeTranslations ?? const <String>[]) {
      _altControllers.add(TextEditingController(text: alt));
    }
    _global = e?.isGlobal ?? true;
    _highlight = e?.highlightEnabled ?? true;
    _sourceWord = e?.sourceWord ?? widget.initialSourceWord;
    _matchPartial = e?.matchPartial ?? (widget.initialSourceWord != null);
    // Rebuild as the term is edited so the sub-word toggle tracks single-word vs
    // multi-word terms.
    _term.addListener(_onTermChanged);

    // Brand-new entries auto-fetch DeepL data on open. When editing, nothing is
    // fetched automatically — the user triggers it with the "Suggest with
    // DeepL" button, so a saved translation is never silently re-fetched or
    // overwritten and the suggestions appear in a separate panel.
    if (e == null && _term.text.isNotEmpty) {
      final settings = ref.read(settingsControllerProvider);
      if (settings.autoSuggestEnabled) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _fetchSuggestion();
          if (settings.deepLEnabled && _hasContext) _fetchContextTranslation();
        });
      }
    }
  }

  bool get _hasContext => widget.contextPassage?.trim().isNotEmpty ?? false;

  /// Fetch the DeepL word suggestion(s) and the in-context paragraph translation
  /// for display in the editing-time panel, without touching the saved fields.
  void _requestDeepLSuggestions() {
    setState(() => _showDeepLPanel = true);
    _fetchSuggestion();
    if (_hasContext) _fetchContextTranslation();
  }

  @override
  void dispose() {
    _term.removeListener(_onTermChanged);
    _term.dispose();
    _translation.dispose();
    _definition.dispose();
    _notes.dispose();
    for (final c in _altControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onTermChanged() {
    if (mounted) setState(() {});
  }

  /// Whether the current term is a single word (sub-word matching only applies
  /// to single words).
  bool get _isSingleWord => TextNormalizer.tokenize(_term.text).length == 1;

  void _addAlternativeField() {
    setState(() => _altControllers.add(TextEditingController()));
  }

  void _removeAlternativeAt(int index) {
    final removed = _altControllers.removeAt(index);
    setState(() {});
    // Dispose after the frame: the field still referencing this controller is
    // torn down during the rebuild, and disposing a still-attached controller
    // throws "used after being disposed".
    WidgetsBinding.instance.addPostFrameCallback((_) => removed.dispose());
  }

  /// Add [suggestion] as an alternative translation, unless it already matches
  /// the primary translation or an existing alternative (case-insensitively).
  void _addSuggestionAsAlternative(String suggestion) {
    final t = suggestion.trim();
    if (t.isEmpty) return;
    final lower = t.toLowerCase();
    if (_translation.text.trim().toLowerCase() == lower) return;
    for (final c in _altControllers) {
      if (c.text.trim().toLowerCase() == lower) return;
    }
    setState(() => _altControllers.add(TextEditingController(text: t)));
  }

  Future<void> _fetchSuggestion() async {
    final term = _term.text.trim();
    if (term.isEmpty || !mounted) return;
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
        _suggestionProviderId = result.providerId;
        // Fill an empty translation field automatically, except when the
        // suggestion was requested into the editing-time panel — there it is
        // display-only so the saved translation is never overwritten.
        if (!_showDeepLPanel &&
            _translation.text.trim().isEmpty &&
            all.isNotEmpty) {
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

  /// Translate the surrounding passage with DeepL (no fallback) so the user can
  /// read the term in its specific context. The result is shown read-only — it
  /// is never written into the saved entry.
  Future<void> _fetchContextTranslation() async {
    final passage = widget.contextPassage?.trim() ?? '';
    if (passage.isEmpty || !mounted) return;
    setState(() {
      _loadingContext = true;
      _contextError = null;
    });
    try {
      final result = await ref
          .read(translationServiceProvider)
          .translateWith(TranslationProviderId.deepL, passage);
      if (!mounted) return;
      setState(() => _contextTranslation = result.translatedText);
    } on ProviderException catch (e) {
      if (mounted) setState(() => _contextError = e.message);
    } catch (e) {
      if (mounted) setState(() => _contextError = '$e');
    } finally {
      if (mounted) setState(() => _loadingContext = false);
    }
  }

  Future<void> _fetchDefinition() async {
    final term = _term.text.trim();
    if (term.isEmpty || !mounted) return;
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

    // Primary + alternative translations. Alternatives are trimmed, de-duplicated
    // case-insensitively, and never repeat the primary. If the primary was left
    // empty but alternatives were entered, promote the first so there is always
    // a primary to show inline and in lists.
    String? primary = orNull(_translation);
    final alternatives = <String>[];
    final seenAlts = <String>{};
    for (final c in _altControllers) {
      final t = c.text.trim();
      if (t.isEmpty) continue;
      final key = t.toLowerCase();
      if (primary != null && key == primary.toLowerCase()) continue;
      if (seenAlts.add(key)) alternatives.add(t);
    }
    if (primary == null && alternatives.isNotEmpty) {
      primary = alternatives.removeAt(0);
    }
    // Sub-word matching only applies to single-word terms; drop the remembered
    // parent word if matching is off, the term is now multi-word, or the term
    // was edited so it is no longer actually a part of that parent word.
    final single = TextNormalizer.tokenize(term).length == 1;
    final matchPartial = single && _matchPartial;
    String? sourceWord;
    if (matchPartial && _sourceWord != null && _sourceWord!.trim().isNotEmpty) {
      final parent = TextNormalizer.normalizeToken(_sourceWord!.trim());
      final word = TextNormalizer.normalizeToken(term);
      if (parent != word && parent.contains(word)) {
        sourceWord = _sourceWord!.trim();
      }
    }

    final base = widget.existing;
    final DictionaryEntry entry = base == null
        ? DictionaryEntry(
            id: 0,
            term: term,
            sourceLang: settings.learningLang,
            targetLang: settings.nativeLang,
            translation: primary,
            alternativeTranslations: alternatives,
            definition: orNull(_definition),
            notes: orNull(_notes),
            highlightEnabled: _highlight,
            matchPartial: matchPartial,
            sourceWord: sourceWord,
            scopeDocumentId: scope,
            createdAt: now,
            updatedAt: now,
          )
        : base.copyWith(
            term: term,
            translation: primary,
            alternativeTranslations: alternatives,
            definition: orNull(_definition),
            notes: orNull(_notes),
            highlightEnabled: _highlight,
            matchPartial: matchPartial,
            sourceWord: sourceWord,
            scopeDocumentId: scope,
            updatedAt: now,
          );

    final saved = await ref
        .read(dictionaryControllerProvider.notifier)
        .save(entry);
    // (Re)build this term's cross-library usage cache when its matching changed
    // — a new term, an edited surface form, or toggled sub-word matching. The
    // current document is scanned first, then the rest of the library in the
    // background, so opening the word's contexts later is instant.
    final matchChanged =
        base == null ||
        base.term != saved.term ||
        base.matchPartial != saved.matchPartial;
    if (matchChanged) {
      ref
          .read(usageIndexerProvider)
          .reindexEntry(
            saved,
            priorityDocId: widget.documentId == 0 ? null : widget.documentId,
          );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  /// Editor for the term's alternative translations: one removable text field
  /// per variant, plus an "add" button. Provider suggestions can also be dropped
  /// in here via the suggestion chips above.
  Widget _buildAlternativesEditor(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.alt_route, size: 18, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Text('Alternative translations', style: theme.textTheme.titleSmall),
          ],
        ),
        for (var i = 0; i < _altControllers.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _altControllers[i],
                    decoration: InputDecoration(
                      isDense: true,
                      labelText: 'Alternative ${i + 1}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: () => _removeAlternativeAt(i),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addAlternativeField,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add alternative translation'),
          ),
        ),
      ],
    );
  }

  /// The selection's surrounding paragraph (duplicated read-only) above its
  /// DeepL translation, so the term can be understood in its specific context.
  /// Used standalone when creating a new entry.
  Widget _buildContextSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.format_quote_outlined,
              size: 18,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: 6),
            Text('In context', style: theme.textTheme.titleSmall),
            const Spacer(),
            IconButton(
              tooltip: 'Re-translate this passage',
              visualDensity: VisualDensity.compact,
              onPressed: _loadingContext ? null : _fetchContextTranslation,
              icon: _loadingContext
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _buildContextBoxes(theme),
      ],
    );
  }

  /// The original paragraph (term highlighted) above its DeepL translation.
  Widget _buildContextBoxes(ThemeData theme) {
    final passage = widget.contextPassage!.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPassageBox(
          theme,
          label: 'Original paragraph',
          child: _passageRichText(theme, passage),
        ),
        const SizedBox(height: 8),
        _buildPassageBox(
          theme,
          label: 'Paragraph translation',
          badge: const _DeepLBadge(),
          child: _buildContextTranslationBody(theme),
        ),
      ],
    );
  }

  /// Editing-time affordance: a button that, once pressed, reveals a read-only
  /// sub-panel with the same DeepL data the creation window shows (translation
  /// suggestions plus the in-context paragraph), leaving the saved fields alone.
  Widget _buildEditDeepLArea(ThemeData theme) {
    if (!_showDeepLPanel) {
      return Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: _requestDeepLSuggestions,
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Suggest with DeepL'),
        ),
      );
    }
    final scheme = theme.colorScheme;
    final loading = _loadingSuggestion || _loadingContext;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('DeepL suggestion', style: theme.textTheme.titleSmall),
              const SizedBox(width: 6),
              const _DeepLBadge(),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh',
                visualDensity: VisualDensity.compact,
                onPressed: loading ? null : _requestDeepLSuggestions,
                icon: loading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 4),
          _buildWordSuggestionDisplay(theme),
          if (_hasContext) ...[
            const SizedBox(height: 12),
            _buildContextBoxes(theme),
          ],
        ],
      ),
    );
  }

  /// Read-only display of the suggested translation(s) for the edit panel, each
  /// adoptable on tap so the saved value is replaced only when the user chooses.
  Widget _buildWordSuggestionDisplay(ThemeData theme) {
    final Widget body;
    if (_loadingSuggestion && _suggestions.isEmpty) {
      body = _inlineLoading(theme, 'Translating…');
    } else if (_suggestionError != null && _suggestions.isEmpty) {
      body = Text(
        _suggestionError!,
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      );
    } else if (_suggestions.isEmpty) {
      body = Text(
        'No translation returned.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    } else {
      body = SelectableText(
        _suggestions.first,
        style: theme.textTheme.bodyMedium,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPassageBox(theme, label: 'Translation', child: body),
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: () =>
                    setState(() => _translation.text = _suggestions.first),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Use as primary'),
              ),
              for (final s in _suggestions.skip(1).take(5))
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(s),
                  onPressed: () => _addSuggestionAsAlternative(s),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _inlineLoading(ThemeData theme, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 8),
      Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      ),
    ],
  );

  Widget _buildContextTranslationBody(ThemeData theme) {
    if (_contextError != null) {
      return Text(
        _contextError!,
        style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
      );
    }
    final translation = _contextTranslation;
    if (translation == null || translation.isEmpty) {
      return Text(
        _loadingContext ? 'Translating…' : 'No translation yet.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
      );
    }
    return SelectableText(translation, style: theme.textTheme.bodyMedium);
  }

  /// A labelled, bordered, scrollable box for a passage of text.
  Widget _buildPassageBox(
    ThemeData theme, {
    required String label,
    Widget? badge,
    required Widget child,
  }) {
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (badge != null) ...[const SizedBox(width: 6), badge],
          ],
        ),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 120),
            child: SingleChildScrollView(child: child),
          ),
        ),
      ],
    );
  }

  /// The original passage with the selected term emphasised in place.
  Widget _passageRichText(ThemeData theme, String passage) {
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final term = _term.text.trim();
    final idx = term.isEmpty
        ? -1
        : passage.toLowerCase().indexOf(term.toLowerCase());
    if (idx < 0) {
      return SelectableText(passage, style: base);
    }
    final end = idx + term.length;
    final highlight = base.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
    );
    return SelectableText.rich(
      TextSpan(
        style: base,
        children: [
          if (idx > 0) TextSpan(text: passage.substring(0, idx)),
          TextSpan(text: passage.substring(idx, end), style: highlight),
          if (end < passage.length) TextSpan(text: passage.substring(end)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);
    final isEditing = widget.existing != null;
    final src = languageForCode(settings.learningLang);
    final dst = languageForCode(settings.nativeLang);
    final definitionsAvailable = settings.definitionsAvailable;
    // DeepL-specific affordances. When creating, the suggestion auto-fills the
    // field (badge it) and the passage shows below. When editing, the same data
    // is offered on demand in a separate panel so saved values are never
    // touched, so these inline/standalone variants are creation-only.
    final showWordDeepL =
        !isEditing && settings.deepLEnabled && _suggestionProviderId == 'deepl';
    final showContext = !isEditing && settings.deepLEnabled && _hasContext;
    final showEditDeepL = isEditing && settings.deepLEnabled;

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
                  onPressed: _loadingSuggestion
                      ? null
                      : (showEditDeepL
                            ? _requestDeepLSuggestions
                            : _fetchSuggestion),
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
              decoration: InputDecoration(
                labelText: 'Translation',
                border: const OutlineInputBorder(),
                suffixIcon: showWordDeepL
                    ? const Align(
                        alignment: Alignment.centerRight,
                        widthFactor: 1,
                        child: Padding(
                          padding: EdgeInsets.only(right: 10),
                          child: _DeepLBadge(),
                        ),
                      )
                    : null,
              ),
            ),
            if (!showEditDeepL && _suggestionError != null) ...[
              const SizedBox(height: 6),
              Text(
                _suggestionError!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
              ),
            ],
            if (!showEditDeepL && _suggestions.length > 1) ...[
              const SizedBox(height: 8),
              Text(
                'More suggestions (tap to add as an alternative)',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in _suggestions.skip(1).take(6))
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: Text(s),
                      onPressed: () => _addSuggestionAsAlternative(s),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            _buildAlternativesEditor(theme),
            if (showContext) ...[
              const SizedBox(height: 16),
              _buildContextSection(theme),
            ],
            if (showEditDeepL) ...[
              const SizedBox(height: 12),
              _buildEditDeepLArea(theme),
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
            if (_isSingleWord)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _matchPartial,
                onChanged: (v) => setState(() => _matchPartial = v),
                title: const Text('Match inside longer words'),
                subtitle: Text(
                  _sourceWord != null && _sourceWord!.isNotEmpty
                      ? 'Also highlights this inside longer words, '
                            'e.g. “${_sourceWord!}”'
                      : 'Also highlights this inside longer words '
                            '(e.g. “perturbation” in “perturbations” or '
                            '“small-perturbation”)',
                ),
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

/// Small "DeepL" pill marking a field/value as produced by DeepL, so the reader
/// knows the translation's source.
class _DeepLBadge extends StatelessWidget {
  const _DeepLBadge();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'DeepL',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
