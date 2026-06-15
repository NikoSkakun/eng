import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/settings_store.dart';
import '../../state/settings_controller.dart';
import '../../util/languages.dart';

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
