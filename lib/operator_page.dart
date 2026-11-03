import 'package:flutter/material.dart';

import 'api.dart';
import 'l10n.dart';

class OperatorPage extends StatelessWidget {
  const OperatorPage({super.key, required this.api});
  final OpenPakApi api;

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: Text(context.l10n.operatorTitle)));
}
