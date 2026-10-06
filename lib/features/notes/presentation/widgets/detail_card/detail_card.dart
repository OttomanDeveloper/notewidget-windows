import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/repositories.dart';
import '../../providers/notes_providers.dart';

class DetailCard extends ConsumerWidget {
  const DetailCard({super.key, required this.error});
  final CorruptDataFileError error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final FileDescription? details = ref.watch(fileDescriptionProvider(error.path));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('File', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          SelectableText(
            error.path,
            style: theme.textTheme.bodySmall?.copyWith(fontFamily: 'Consolas'),
          ),
          const SizedBox(height: 12),
          Text('Problem', style: theme.textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(error.reason, style: theme.textTheme.bodySmall),
          if (details != null) ...<Widget>[
            const SizedBox(height: 12),
            Text(
              '${details.bytes} bytes, last changed '
              '${_stamp(details.changed)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _stamp(DateTime when) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}';
  }
}
