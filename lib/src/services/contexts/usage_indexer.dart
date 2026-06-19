import 'package:flutter/foundation.dart';

import '../../data/dictionary_repository.dart';
import '../../data/library_repository.dart';
import '../../data/usage_repository.dart';
import '../../models/dictionary_entry.dart';
import '../../models/usage.dart';
import '../../text/term_matcher.dart';
import 'word_contexts_service.dart';

/// Builds and maintains the persistent cross-library usage cache in the
/// background. When a term is added/edited it scans the current document first
/// and then the rest of the library, writing occurrence pointers so opening a
/// word's contexts later is instant.
///
/// All work flows through a single serial queue, so only one document is being
/// extracted at a time — that keeps the UI responsive ("smooth") even while the
/// whole library is scanned. [revision] ticks whenever the cache changes so open
/// views can reload.
class UsageIndexer {
  UsageIndexer(this._usages, this._dictionary, this._library, this._contexts);

  final UsageRepository _usages;
  final DictionaryRepository _dictionary;
  final LibraryRepository _library;
  final WordContextsService _contexts;

  final List<({int entryId, int docId})> _queue = [];
  final Set<String> _queued = {};
  bool _running = false;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  String _key(int entryId, int docId) => '$entryId:$docId';

  void _enqueue(int entryId, int docId, {bool front = false}) {
    if (!_queued.add(_key(entryId, docId))) return; // already queued
    final job = (entryId: entryId, docId: docId);
    if (front) {
      _queue.insert(0, job);
    } else {
      _queue.add(job);
    }
  }

  /// Re-index a term from scratch (it is new, or its term / match mode changed):
  /// drop its cache, scan [priorityDocId] first (e.g. the document being read),
  /// then the rest of the library in the background.
  void reindexEntry(DictionaryEntry entry, {int? priorityDocId}) {
    _usages.clearEntry(entry.id);
    revision.value++;
    if (priorityDocId != null && _library.getById(priorityDocId) != null) {
      _enqueue(entry.id, priorityDocId, front: true);
    }
    for (final doc in _library.getAll()) {
      if (doc.id != priorityDocId) _enqueue(entry.id, doc.id);
    }
    _pump();
  }

  /// Ensure [entry] is scanned across the whole library, filling any gaps (e.g.
  /// after an interrupted pass or a newly imported document). Pairs already
  /// scanned are left untouched.
  void ensureEntryIndexed(DictionaryEntry entry) {
    final done = _usages.indexedDocsForEntry(entry.id);
    for (final doc in _library.getAll()) {
      if (!done.contains(doc.id)) _enqueue(entry.id, doc.id);
    }
    _pump();
  }

  /// Scan a newly imported document for every existing term (low priority).
  void indexNewDocument(int docId) {
    for (final entry in _dictionary.getAll()) {
      if (!_usages.isIndexed(entry.id, docId)) _enqueue(entry.id, docId);
    }
    _pump();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        _queued.remove(_key(job.entryId, job.docId));

        // Skip duplicates already done, or rows that vanished meanwhile.
        if (_usages.isIndexed(job.entryId, job.docId)) continue;
        final entry = _dictionary.getById(job.entryId);
        final doc = _library.getById(job.docId);
        if (entry == null || doc == null) continue;

        final term = MatchableTerm.fromTerm(
          entry.id,
          entry.term,
          partial: entry.matchPartial,
        );
        final matcher = TermMatcher(term == null ? const [] : [term]);

        List<WordContext> found;
        try {
          found = await _contexts.contextsIn(doc, matcher);
        } catch (_) {
          found = const [];
        }

        try {
          // The entry/document may have been removed while we were extracting;
          // a stale putPair would violate a foreign key — just skip it.
          if (_dictionary.getById(job.entryId) == null) continue;
          _usages.putPair(job.entryId, job.docId, [
            for (final c in found)
              Usage(
                id: 0,
                entryId: job.entryId,
                documentId: job.docId,
                page: c.page,
                blockIndex: c.blockIndex,
                snippet: c.text,
                highlights: c.highlights,
              ),
          ]);
          revision.value++;
        } catch (_) {
          // Transient DB error or a row deleted mid-flight — leave it unindexed.
        }

        // Yield between documents so the UI stays responsive.
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    } finally {
      _running = false;
    }
  }
}
