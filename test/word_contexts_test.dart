import 'dart:io';

import 'package:eng/src/models/library_document.dart';
import 'package:eng/src/services/contexts/word_contexts_service.dart';
import 'package:eng/src/text/term_matcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('eng_ctx_test');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  LibraryDocument docFor(String path, {String title = 'Sample'}) =>
      LibraryDocument(
        id: 1,
        title: title,
        filePath: path,
        addedAt: DateTime.fromMillisecondsSinceEpoch(0),
      );

  TermMatcher matcherFor(String term, {bool partial = false}) =>
      TermMatcher([MatchableTerm.fromTerm(1, term, partial: partial)!]);

  String highlighted(WordContext c) =>
      c.highlights.map((h) => c.text.substring(h.start, h.end)).join('|');

  Future<List<WordContext>> contextsOf(String body, TermMatcher matcher) async {
    final f = File(p.join(tmp.path, 'sample.txt'));
    await f.writeAsString(body);
    return WordContextsService().contextsIn(docFor(f.path), matcher);
  }

  test('returns each paragraph containing the term; whole-word, case-insensitive', () async {
    final contexts = await contextsOf(
      'The cat sat.\n\nA dog ran. The CAT slept.\n\nNothing about categories.',
      matcherFor('cat'),
    );

    // "categories" must NOT match (whole-word), so exactly two paragraphs hit.
    expect(contexts.length, 2);
    expect(contexts.every((c) => c.sourceTitle == 'Sample'), isTrue);
    expect(highlighted(contexts[0]).toLowerCase(), 'cat');
    expect(highlighted(contexts[1]).toLowerCase(), 'cat');
    // Short paragraphs are shown whole.
    expect(contexts[0].text, 'The cat sat.');
  });

  test('highlights every occurrence within one paragraph', () async {
    final contexts = await contextsOf('cat and cat again', matcherFor('cat'));
    expect(contexts.length, 1);
    expect(contexts.single.highlights.length, 2);
  });

  test('windows a long block around the match and maps the highlight', () async {
    final long = '${'lorem ' * 120}cat ${'ipsum ' * 120}'; // one >600-char block
    final contexts = await contextsOf(long, matcherFor('cat'));

    expect(contexts.length, 1);
    final c = contexts.single;
    expect(c.text.length, lessThan(long.length)); // windowed, not the whole block
    expect(c.text, contains('…'));
    final h = c.highlights.single;
    expect(c.text.substring(h.start, h.end), 'cat');
  });

  test('no contexts when the term is absent', () async {
    final contexts = await contextsOf('nothing to see here', matcherFor('cat'));
    expect(contexts, isEmpty);
  });
}
