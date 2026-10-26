import 'package:flutter/material.dart';

import 'l10n.dart';
import 'pakka.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pakka's diagnostics: describe a connection problem, get a diagnosis with
/// the evidence behind it, and see the service checks underneath. Reached
/// from the Titles tab, signed in or out — Pakka takes no bearer.
class PakkaPage extends StatefulWidget {
  const PakkaPage({super.key, required this.pakka});
  final PakkaApi pakka;

  @override
  State<PakkaPage> createState() => PakkaPageState();
}

class PakkaPageState extends State<PakkaPage> {
  final _symptoms = TextEditingController();
  Future<PakkaInvestigation>? _investigation;
  late Future<PakkaRun> _checks;
  bool _diagnosing = false;

  @override
  void initState() {
    super.initState();
    _checks = widget.pakka.run();
  }

  @override
  void dispose() {
    _symptoms.dispose();
    super.dispose();
  }

  /// The diagnosis is a second future rather than a reload of the page: the
  /// symptoms stay typed and the checks stay read while it runs.
  Future<void> _diagnose() async {
    if (_diagnosing) return;
    final f = widget.pakka.investigate(symptoms: _symptoms.text.trim());
    setState(() {
      _diagnosing = true;
      _investigation = f;
    });
    try {
      await f;
    } catch (_) {
      // The FutureBuilder below shows it; awaiting here only drives the button.
    } finally {
      if (mounted) setState(() => _diagnosing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: glassAppBar(title: Text(l.pakkaTitle)),
      body: RefreshIndicator(
        edgeOffset: glassTop(context),
        onRefresh: () async => setState(() => _checks = widget.pakka.run()),
        child: ListView(
          padding: pagePadding(context, top: 12),
          children: [
            Text(l.pakkaIntro, style: TextStyle(color: tokensOf(context).muted, fontSize: 13.5, height: 1.4)),
            const SizedBox(height: 12),
            TextField(
              controller: _symptoms,
              minLines: 2,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _diagnose(),
              decoration: InputDecoration(labelText: l.pakkaSymptomsLabel, hintText: l.pakkaSymptomsHint),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _diagnosing ? null : _diagnose,
              icon: _diagnosing
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.troubleshoot_outlined),
              label: Text(l.pakkaDiagnose),
            ),
            if (_investigation != null) ...[
              const SizedBox(height: 20),
              SectionLabel(l.pakkaFinding),
              FutureBuilder<PakkaInvestigation>(
                future: _investigation,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) return _InlineFailure(snap.error);
                  return _FindingView(investigation: snap.data!);
                },
              ),
            ],
            const SizedBox(height: 20),
            SectionLabel(l.pakkaChecks),
            FutureBuilder<PakkaRun>(
              future: _checks,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) return _InlineFailure(snap.error);
                final results = snap.data!.results;
                if (results.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      l.pakkaChecksEmpty,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: tokensOf(context).muted),
                    ),
                  );
                }
                return Column(children: [for (final r in results) _CheckRow(result: r)]);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// The failure state inside this page's scrolling body: [LoadFailure]'s words
/// without its own scrollable, which cannot nest inside the page's [ListView].
class _InlineFailure extends StatelessWidget {
  const _InlineFailure(this.error);
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final t = tokensOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      child: Column(
        children: [
          Text(
            context.l10n.loadFailed,
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted),
          ),
          const SizedBox(height: 8),
          Text(
            LoadFailure.reasonOf(context.l10n, error),
            textAlign: TextAlign.center,
            style: TextStyle(color: t.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// A diagnosis: the verdict as a pill, what Pakka concluded, what to do next,
/// and the checks it cites.
class _FindingView extends StatelessWidget {
  const _FindingView({required this.investigation});
  final PakkaInvestigation investigation;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final f = investigation.finding;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatePill(text: diagnosisText(l, f.diagnosis), state: diagnosisState(f.diagnosis)),
                if (f.summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(f.summary, style: const TextStyle(height: 1.4)),
                ],
                if (f.recommendedNext.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    l.pakkaRecommendedNext,
                    style: TextStyle(fontFamily: uiFont, color: tokensOf(context).muted, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(f.recommendedNext, style: const TextStyle(height: 1.4)),
                ],
              ],
            ),
          ),
        ),
        if (investigation.results.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionLabel(l.pakkaEvidence),
          for (final r in investigation.results) _CheckRow(result: r),
        ],
      ],
    );
  }
}

/// One check as an expandable row: green when it passed, red when it failed,
/// grey when it was skipped. The summary opens underneath on tap.
class _CheckRow extends StatelessWidget {
  const _CheckRow({required this.result});
  final PakkaCheckResult result;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return StateRow(
      name: result.checkId,
      pill: outcomeText(l, result.outcome),
      state: outcomeState(result.outcome),
      expandedChild: result.summary.isEmpty
          ? null
          : Text(result.summary, style: const TextStyle(fontSize: 13.5, height: 1.4)),
    );
  }
}

/// A service outage is amber, not red: the services are at fault, so there is
/// nothing wrong on the phone to fix. An unknown word from a newer harness
/// claims nothing.
RowState diagnosisState(String diagnosis) => switch (diagnosis) {
  'healthy' => RowState.ok,
  'service-outage' => RowState.warn,
  'local-failure' => RowState.bad,
  _ => RowState.idle,
};

/// What a person reads for a diagnosis. An unknown one shows the harness's
/// own word, as an untranslated error code does.
String diagnosisText(AppLocalizations l, String diagnosis) => switch (diagnosis) {
  'healthy' => l.pakkaDiagnosisHealthy,
  'service-outage' => l.pakkaDiagnosisServiceOutage,
  'local-failure' => l.pakkaDiagnosisLocalFailure,
  'insufficient-evidence' => l.pakkaDiagnosisInsufficient,
  _ => diagnosis,
};

RowState outcomeState(String outcome) => switch (outcome) {
  'pass' => RowState.ok,
  'fail' || 'error' => RowState.bad,
  _ => RowState.idle,
};

String outcomeText(AppLocalizations l, String outcome) => switch (outcome) {
  'pass' => l.pakkaOutcomePass,
  'fail' => l.pakkaOutcomeFail,
  'error' => l.pakkaOutcomeError,
  'skipped' => l.pakkaOutcomeSkipped,
  _ => outcome,
};
