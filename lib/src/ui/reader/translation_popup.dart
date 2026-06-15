import 'package:flutter/material.dart';

import '../../models/dictionary_entry.dart';

/// The small card shown when hovering or tapping a highlighted term. Displays
/// the stored translation/definition and offers an edit action.
class TranslationPopupCard extends StatelessWidget {
  const TranslationPopupCard({
    super.key,
    required this.entry,
    required this.onEdit,
    this.onPointerEnter,
    this.onPointerExit,
    this.maxWidth = 340,
  });

  final DictionaryEntry entry;
  final VoidCallback onEdit;
  final VoidCallback? onPointerEnter;
  final VoidCallback? onPointerExit;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: 320),
      child: Card(
        elevation: 6,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      entry.term,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Edit',
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                ],
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (entry.translation != null &&
                          entry.translation!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 6),
                          child: Text(
                            entry.translation!,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      if (entry.definition != null &&
                          entry.definition!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8, bottom: 6),
                          child: Text(
                            entry.definition!,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      if (entry.notes != null && entry.notes!.trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            entry.notes!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      if (!entry.hasContent)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, right: 8),
                          child: Text(
                            'No translation yet — tap edit to add one.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (onPointerEnter == null && onPointerExit == null) return card;
    return MouseRegion(
      onEnter: (_) => onPointerEnter?.call(),
      onExit: (_) => onPointerExit?.call(),
      child: card,
    );
  }
}
