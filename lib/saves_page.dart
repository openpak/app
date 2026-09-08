import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Cloud saves are specified but not built (`prds/cloud-saves-prd.md`), so this
/// says so plainly instead of showing an empty list that looks broken. When the
/// service exists this screen gets a real body and nothing else moves.
class SavesPage extends StatelessWidget {
  const SavesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Saves')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          Panel(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.cloud_outlined, color: t.muted),
                      const SizedBox(width: 10),
                      Text(
                        'Coming soon',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Cloud save sync is not running yet. When it is, your '
                    'saves will appear here: which game, how big, and when '
                    'they last changed.',
                    style: TextStyle(color: t.ink2, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.paper2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.visibility_outlined, size: 18, color: t.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'It will be read-only here. Uploading and deleting '
                            'saves is deliberate work that belongs on the '
                            'website, not one tap away on a phone.',
                            style: TextStyle(color: t.muted, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
