import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/settings_store.dart';
import '../../services/backup_service.dart';
import '../../state/dictionary_controller.dart';
import '../../state/library_controller.dart';
import '../../state/providers.dart';
import '../../state/settings_controller.dart';
import '../../util/languages.dart';

const XTypeGroup _zipTypeGroup = XTypeGroup(
  label: 'eng backup (.zip)',
  extensions: ['zip'],
  mimeTypes: ['application/zip'],
  uniformTypeIdentifiers: ['public.zip-archive'],
);

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _email;
  late final TextEditingController _deepLKey;
  late final TextEditingController _libreUrl;
  late final TextEditingController _libreKey;

  /// Preset semi-transparent highlight colors (ARGB).
  static const _colorPresets = <int>[
    0x66FFC107, // amber
    0x6650C878, // green
    0x6442A5F5, // blue
    0x66EC407A, // pink
    0x66AB47BC, // purple
    0x66FF7043, // orange
  ];

  /// Preset opaque colors for the inline translation glosses (text color).
  static const _glossColorPresets = <int>[
    0xFF1565C0, // blue
    0xFFC62828, // red
    0xFF2E7D32, // green
    0xFF6A1B9A, // purple
    0xFFAD1457, // pink
    0xFF00838F, // teal
  ];

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsControllerProvider);
    _email = TextEditingController(text: s.myMemoryEmail);
    _deepLKey = TextEditingController(text: s.deepLApiKey);
    _libreUrl = TextEditingController(text: s.libreTranslateUrl);
    _libreKey = TextEditingController(text: s.libreTranslateApiKey);
  }

  @override
  void dispose() {
    _email.dispose();
    _deepLKey.dispose();
    _libreUrl.dispose();
    _libreKey.dispose();
    super.dispose();
  }

  void _mutate(AppSettings Function(AppSettings) f) =>
      ref.read(settingsControllerProvider.notifier).mutate(f);

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not open $url')));
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _export() async {
    final opts = await _BackupOptionsDialog.show(
      context,
      title: 'Export data',
      confirmLabel: 'Export',
    );
    if (opts == null || !mounted) return;
    if (!opts.library && !opts.dictionary) {
      _snack('Select at least one kind of data to export.');
      return;
    }
    final stamp = DateTime.now().toIso8601String().split('T').first;
    final location = await getSaveLocation(
      acceptedTypeGroups: const [_zipTypeGroup],
      suggestedName: 'eng-backup-$stamp.zip',
    );
    if (location == null || !mounted) return;
    var path = location.path;
    if (!path.toLowerCase().endsWith('.zip')) path = '$path.zip';
    try {
      final result = await ref
          .read(backupServiceProvider)
          .exportTo(
            path,
            includeLibrary: opts.library,
            includeDictionary: opts.dictionary,
          );
      _snack(
        'Exported ${result.documents} document(s) and ${result.entries} entry(ies).',
      );
    } catch (e) {
      _snack('Export failed: $e');
    }
  }

  Future<void> _import() async {
    final file = await openFile(acceptedTypeGroups: const [_zipTypeGroup]);
    if (file == null || !mounted) return;
    final service = ref.read(backupServiceProvider);
    final BackupContents info;
    try {
      info = await service.inspect(file.path);
    } catch (e) {
      _snack('Not a valid backup: $e');
      return;
    }
    if (!mounted) return;
    final opts = await _BackupOptionsDialog.show(
      context,
      title: 'Import data',
      confirmLabel: 'Import',
      contents: info,
    );
    if (opts == null || !mounted) return;
    try {
      final result = await service.importFrom(
        file.path,
        includeLibrary: opts.library,
        includeDictionary: opts.dictionary,
      );
      ref.invalidate(libraryControllerProvider);
      ref.invalidate(dictionaryControllerProvider);
      final skipped = result.skipped > 0
          ? ' (${result.skipped} duplicate(s) skipped)'
          : '';
      _snack(
        'Imported ${result.documents} document(s) and ${result.entries} entry(ies)$skipped.',
      );
    } catch (e) {
      _snack('Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Languages'),
          ListTile(
            title: const Text('I am learning'),
            subtitle: const Text('Language of the documents you read'),
            trailing: _LangDropdown(
              value: s.learningLang,
              onChanged: (v) => _mutate((x) => x.copyWith(learningLang: v)),
            ),
          ),
          ListTile(
            title: const Text('Translate into'),
            subtitle: const Text('Your own language'),
            trailing: _LangDropdown(
              value: s.nativeLang,
              onChanged: (v) => _mutate((x) => x.copyWith(nativeLang: v)),
            ),
          ),
          const Divider(),
          _SectionHeader('Highlighting'),
          SwitchListTile(
            title: const Text('Auto-highlight dictionary terms'),
            subtitle: const Text(
              'Highlight your saved words across all documents',
            ),
            value: s.highlightingEnabled,
            onChanged: (v) =>
                _mutate((x) => x.copyWith(highlightingEnabled: v)),
          ),
          SwitchListTile(
            title: const Text('Suggest translations automatically'),
            subtitle: const Text('Fetch a suggestion when you add a new word'),
            value: s.autoSuggestEnabled,
            onChanged: (v) => _mutate((x) => x.copyWith(autoSuggestEnabled: v)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text('Highlight color', style: theme.textTheme.bodyMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 12,
              children: [
                for (final c in _colorPresets)
                  GestureDetector(
                    onTap: () => _mutate((x) => x.copyWith(highlightColor: c)),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: s.highlightColor == c
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          width: s.highlightColor == c ? 3 : 1,
                        ),
                      ),
                      child: s.highlightColor == c
                          ? const Icon(Icons.check, size: 18)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text('Show translation under each word'),
            subtitle: const Text(
              'Small inline gloss between the lines, for highlighted terms that '
              'have a translation',
            ),
            value: s.inlineTranslationEnabled,
            onChanged: (v) =>
                _mutate((x) => x.copyWith(inlineTranslationEnabled: v)),
          ),
          if (s.inlineTranslationEnabled) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(
                'Inline translation color',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Wrap(
                spacing: 12,
                children: [
                  for (final c in _glossColorPresets)
                    GestureDetector(
                      onTap: () =>
                          _mutate((x) => x.copyWith(inlineGlossColor: c)),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Color(c),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: s.inlineGlossColor == c
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                            width: s.inlineGlossColor == c ? 3 : 1,
                          ),
                        ),
                        child: s.inlineGlossColor == c
                            ? const Icon(
                                Icons.check,
                                size: 18,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const Divider(),
          _SectionHeader('Translation provider'),
          ListTile(
            title: const Text('Provider'),
            trailing: DropdownButton<TranslationProviderId>(
              value: s.translationProvider,
              onChanged: (v) => v == null
                  ? null
                  : _mutate((x) => x.copyWith(translationProvider: v)),
              items: [
                for (final p in TranslationProviderId.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
            ),
          ),
          ..._providerConfig(s, theme),
          const Divider(),
          _SectionHeader('Definitions'),
          ListTile(
            title: const Text('Definition source'),
            trailing: DropdownButton<DefinitionProviderId>(
              value: s.definitionProvider,
              onChanged: (v) => v == null
                  ? null
                  : _mutate((x) => x.copyWith(definitionProvider: v)),
              items: [
                for (final p in DefinitionProviderId.values)
                  DropdownMenuItem(value: p, child: Text(p.label)),
              ],
            ),
          ),
          if (!kDefinitionLanguages.contains(s.learningLang) &&
              s.definitionProvider != DefinitionProviderId.none)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Definitions are currently only available when learning English.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          const Divider(),
          _SectionHeader('Backup & restore'),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Export data…'),
            subtitle: const Text('Save your library and dictionary to a file'),
            onTap: _export,
          ),
          ListTile(
            leading: const Icon(Icons.download_outlined),
            title: const Text('Import data…'),
            subtitle: const Text(
              'Restore from a backup made on another device',
            ),
            onTap: _import,
          ),
          const Divider(),
          _SectionHeader('About & data sources'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Selected text is sent to the chosen translation/definition service to '
              'fetch suggestions. Results are cached locally. You can always edit or '
              'replace any suggestion with your own wording.',
            ),
          ),
          ListTile(
            dense: true,
            title: const Text('MyMemory translation'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openUrl('https://mymemory.translated.net'),
          ),
          ListTile(
            dense: true,
            title: const Text('Definitions: Wiktionary (CC BY-SA)'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _openUrl('https://en.wiktionary.org'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  List<Widget> _providerConfig(AppSettings s, ThemeData theme) {
    switch (s.translationProvider) {
      case TranslationProviderId.myMemory:
        return [
          _configField(
            controller: _email,
            label: 'Email (optional)',
            helper:
                'Raises the free quota from 5,000 to 50,000 characters/day.',
            onChanged: (v) => _mutate((x) => x.copyWith(myMemoryEmail: v)),
          ),
        ];
      case TranslationProviderId.libreTranslate:
        return [
          _configField(
            controller: _libreUrl,
            label: 'Instance URL',
            helper:
                'e.g. https://translate.example.org (self-hosted = no key needed)',
            onChanged: (v) => _mutate((x) => x.copyWith(libreTranslateUrl: v)),
          ),
          _configField(
            controller: _libreKey,
            label: 'API key (optional)',
            obscure: true,
            onChanged: (v) =>
                _mutate((x) => x.copyWith(libreTranslateApiKey: v)),
          ),
        ];
      case TranslationProviderId.deepL:
        return [
          _configField(
            controller: _deepLKey,
            label: 'DeepL API key',
            helper: 'Free keys end in ":fx". Get one at deepl.com/pro-api.',
            obscure: true,
            onChanged: (v) => _mutate((x) => x.copyWith(deepLApiKey: v)),
          ),
        ];
      case TranslationProviderId.googleUnofficial:
        return [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(
              'Uses an undocumented Google endpoint. It may break without notice and '
              'using it can violate Google’s terms of service. Keyless, but use at your own risk.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ];
    }
  }

  Widget _configField({
    required TextEditingController controller,
    required String label,
    String? helper,
    bool obscure = false,
    required ValueChanged<String> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 3,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: onChanged,
      ),
    );
  }
}

class _LangDropdown extends StatelessWidget {
  const _LangDropdown({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      onChanged: (v) => v == null ? null : onChanged(v),
      items: [
        for (final lang in kSupportedLanguages)
          DropdownMenuItem(value: lang.code, child: Text(lang.nativeName)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        title,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Which data the user chose to include in an export/import.
class _BackupOptions {
  const _BackupOptions(this.library, this.dictionary);
  final bool library;
  final bool dictionary;
}

/// Dialog letting the user include/exclude Library and Dictionary data.
///
/// For export, [contents] is null and both toggles default on. For import,
/// [contents] reflects what's actually in the file; absent sections are
/// disabled, and counts are shown.
class _BackupOptionsDialog extends StatefulWidget {
  const _BackupOptionsDialog({
    required this.title,
    required this.confirmLabel,
    this.contents,
  });

  final String title;
  final String confirmLabel;
  final BackupContents? contents;

  static Future<_BackupOptions?> show(
    BuildContext context, {
    required String title,
    required String confirmLabel,
    BackupContents? contents,
  }) {
    return showDialog<_BackupOptions>(
      context: context,
      builder: (_) => _BackupOptionsDialog(
        title: title,
        confirmLabel: confirmLabel,
        contents: contents,
      ),
    );
  }

  @override
  State<_BackupOptionsDialog> createState() => _BackupOptionsDialogState();
}

class _BackupOptionsDialogState extends State<_BackupOptionsDialog> {
  late bool _library = widget.contents?.hasLibrary ?? true;
  late bool _dictionary = widget.contents?.hasDictionary ?? true;

  @override
  Widget build(BuildContext context) {
    final c = widget.contents;
    final libAvailable = c == null || c.hasLibrary;
    final dictAvailable = c == null || c.hasDictionary;
    final libSub = c == null
        ? 'Documents and reading positions'
        : '${c.documentCount} document(s)';
    final dictSub = c == null
        ? 'Words, translations and definitions'
        : '${c.dictionaryCount} entry(ies)';

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _library && libAvailable,
            onChanged: libAvailable
                ? (v) => setState(() => _library = v)
                : null,
            title: const Text('Library'),
            subtitle: Text(libAvailable ? libSub : 'Not in this backup'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _dictionary && dictAvailable,
            onChanged: dictAvailable
                ? (v) => setState(() => _dictionary = v)
                : null,
            title: const Text('Dictionary'),
            subtitle: Text(dictAvailable ? dictSub : 'Not in this backup'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_library || _dictionary)
              ? () => Navigator.of(
                  context,
                ).pop(_BackupOptions(_library, _dictionary))
              : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
