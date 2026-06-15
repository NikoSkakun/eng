import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/dictionary_entry.dart';
import '../text/term_matcher.dart';
import '../text/text_normalizer.dart';
import 'providers.dart';

/// Immutable snapshot of the dictionary plus a [revision] that increments on
/// every change. The reader watches [revision] to know when to recompute the
/// highlights on already-rendered pages.
class DictionaryState {
  DictionaryState({required this.entries, required this.revision})
    : byId = {for (final e in entries) e.id: e};

  final List<DictionaryEntry> entries;
  final Map<int, DictionaryEntry> byId;
  final int revision;
}

final dictionaryControllerProvider =
    NotifierProvider<DictionaryController, DictionaryState>(
      DictionaryController.new,
    );

class DictionaryController extends Notifier<DictionaryState> {
  @override
  DictionaryState build() {
    final repo = ref.read(dictionaryRepositoryProvider);
    return DictionaryState(entries: repo.getAll(), revision: 0);
  }

  void _reload() {
    final repo = ref.read(dictionaryRepositoryProvider);
    state = DictionaryState(
      entries: repo.getAll(),
      revision: state.revision + 1,
    );
  }

  /// Insert (id == 0) or update an entry, then refresh state.
  Future<DictionaryEntry> save(DictionaryEntry entry) async {
    final repo = ref.read(dictionaryRepositoryProvider);
    final DictionaryEntry saved;
    if (entry.id == 0) {
      saved = repo.insert(entry);
    } else {
      repo.update(entry);
      saved = entry;
    }
    _reload();
    return saved;
  }

  Future<void> delete(int id) async {
    ref.read(dictionaryRepositoryProvider).delete(id);
    _reload();
  }

  Future<void> toggleHighlight(DictionaryEntry entry) => save(
    entry.copyWith(
      highlightEnabled: !entry.highlightEnabled,
      updatedAt: DateTime.now(),
    ),
  );

  /// Find an existing entry matching [term] (by normalized form) within the
  /// given scope, so the UI can edit instead of duplicating.
  DictionaryEntry? findByTerm(String term, {int? scopeDocumentId}) {
    final key = TextNormalizer.normalizeKey(term);
    for (final e in state.entries) {
      if (e.normalizedTerm == key && e.scopeDocumentId == scopeDocumentId) {
        return e;
      }
    }
    return null;
  }

  /// Terms eligible for highlighting in [documentId]: enabled entries whose
  /// scope is global or this document, in the document's reading language.
  List<MatchableTerm> matchableTermsFor(int documentId, String learningLang) {
    final terms = <MatchableTerm>[];
    for (final e in state.entries) {
      if (!e.highlightEnabled) continue;
      if (e.scopeDocumentId != null && e.scopeDocumentId != documentId) {
        continue;
      }
      if (e.sourceLang != learningLang) continue;
      final t = MatchableTerm.fromTerm(e.id, e.term);
      if (t != null) terms.add(t);
    }
    return terms;
  }
}
