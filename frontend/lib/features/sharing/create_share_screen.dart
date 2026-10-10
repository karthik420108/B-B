import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';
import '../../widgets/qr_scanner_dialog.dart';

class CreateShareScreen extends ConsumerStatefulWidget {
  const CreateShareScreen({super.key});

  @override
  ConsumerState<CreateShareScreen> createState() => _CreateShareScreenState();
}

class _CreateShareScreenState extends ConsumerState<CreateShareScreen> {
  final _label = TextEditingController();
  List<Map<String, dynamic>> _doctors = [];
  Map<String, dynamic>? _selectedDoctor;
  int _expiry = 1440;
  int _maxAccesses = 0;
  bool _includeAll = false;
  bool _includeSummary = true;
  bool _includeTimeline = true;
  bool _includeMedications = true;
  bool _includeAllergies = true;
  bool _includeObservations = true;
  bool _includeDuplicateAlerts = true;
  bool _busy = false;
  bool _doctorListLoaded = false;
  List<DocumentSummary> _documents = [];
  final Set<String> _selectedDocIds = {};
  bool _documentsLoaded = false;
  bool _documentsLoading = false;
  String? _documentsError;

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  /// Load the patient's records so they can pick exactly what to share.
  Future<void> _loadDocuments() async {
    if (_documentsLoaded || _documentsLoading) return;
    setState(() {
      _documentsLoading = true;
      _documentsError = null;
    });
    try {
      final result = await ref.read(documentsRepositoryProvider).list();
      if (!mounted) return;
      setState(() {
        _documents = result.items;
        _documentsLoaded = true;
        _documentsLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _documentsLoading = false;
        _documentsError = friendlyError(e);
      });
    }
  }

  Future<void> _loadDoctors() async {
    if (_doctorListLoaded) return;
    try {
      final docs = await ref.read(doctorRepositoryProvider).directory();
      if (!mounted) return;
      setState(() {
        _doctors = docs;
        _doctorListLoaded = true;
      });
    } catch (_) {
      // Directory is optional; the share can be created without naming a doctor.
    }
  }

  /// Scan a doctor's QR to nominate them. The payload identifies the doctor only —
  /// no medical data is disclosed by scanning. The doctor's verified identity is
  /// confirmed against the server directory before selection.
  Future<void> _scanDoctorQr() async {
    final scanned = await QrScannerDialog.show(
      context,
      title: 'Scan Doctor QR Code',
      hint: 'Paste or scan the doctor’s QR payload…',
      expectedType: 'doctor',
    );
    if (scanned == null || scanned.trim().isEmpty) return;

    Map<String, dynamic> payload;
    try {
      final decoded = jsonDecode(scanned.trim());
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      payload = decoded;
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid doctor QR payload. Expected a JSON object.')),
      );
      return;
    }

    if (payload['type'] != 'doctor') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This QR is not a doctor invitation code.')),
      );
      return;
    }

    final doctorId = payload['doctorId']?.toString() ?? '';
    if (doctorId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Doctor QR is missing a doctor identifier.')),
      );
      return;
    }

    // Confirm the doctor's identity against the server directory.
    if (!_doctorListLoaded) await _loadDoctors();
    if (!mounted) return;
    final match = _doctors.where((d) => d['id'] == doctorId).firstOrNull;
    if (match == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This doctor is not in the verified directory.')),
      );
      return;
    }

    final verification = (match['verification'] ?? 'unverified').toString();
    if (verification != 'verified' && verification != 'development') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${match['name']} is not a verified doctor ($verification).')),
      );
      return;
    }

    setState(() => _selectedDoctor = match);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${match['name']} selected as the nominated doctor.')),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadDoctors();
      _loadDocuments();
    });
  }

  Future<void> _create() async {
    setState(() => _busy = true);
    try {
      final payload = <String, dynamic>{
        'label': _label.text.trim().isEmpty ? null : _label.text.trim(),
        'documentIds': _includeAll ? const <String>[] : _selectedDocIds.toList(),
        'includeAll': _includeAll,
        'includeSummary': _includeSummary,
        'includeTimeline': _includeTimeline,
        'includeMedications': _includeMedications,
        'includeAllergies': _includeAllergies,
        'includeObservations': _includeObservations,
        'includeDuplicateAlerts': _includeDuplicateAlerts,
        'expiresInMinutes': _expiry,
        'maxAccesses': _maxAccesses,
        if (_selectedDoctor != null) 'doctorUserId': _selectedDoctor!['id'],
        if (_selectedDoctor != null) 'doctorEmail': _selectedDoctor!['email'],
        if (_selectedDoctor != null) 'doctorName': _selectedDoctor!['name'],
        if (_selectedDoctor != null) 'doctorSpecialty': _selectedDoctor!['specialty'],
      };
      final created = await ref.read(shareRepositoryProvider).create(payload);
      ref.invalidate(sharesProvider);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _ShareResultSheet(created: created),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('New share')),
      body: SafeArea(
        child: Form(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Choose exactly what a doctor may see. Access is logged, expires automatically, and can be revoked any time from the server — the doctor only ever sees the consented scope below.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _label,
                decoration: const InputDecoration(labelText: 'Label (optional)', prefixIcon: Icon(Icons.sell_outlined)),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: DropdownButtonFormField<Map<String, dynamic>>(
                      initialValue: _selectedDoctor,
                      hint: const Text('Any doctor who claims the link'),
                      decoration: const InputDecoration(labelText: 'Nominated doctor (optional)', prefixIcon: Icon(Icons.medical_services_outlined)),
                      items: _doctors
                          .map((d) => DropdownMenuItem(
                                value: d,
                                child: Text('${d['name']}${d['specialty'] != null ? ' — ${d['specialty']}' : ''}', overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _selectedDoctor = v),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Scan Doctor QR',
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanDoctorQr,
                  ),
                ],
              ),
              if (_selectedDoctor != null) ...[
                const SizedBox(height: 8),
                Card(
                  color: theme.colorScheme.secondaryContainer.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_selectedDoctor!['name']?.toString() ?? 'Doctor', style: theme.textTheme.titleSmall),
                              Text(
                                [
                                  _selectedDoctor!['specialty']?.toString(),
                                  _selectedDoctor!['clinicName']?.toString(),
                                  'Verification: ${_selectedDoctor!['verification'] ?? 'unknown'}',
                                ].whereType<String>().join(' • '),
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text('Scope', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Include ALL records'),
                subtitle: Text(_includeAll ? 'Overrides the toggles below' : 'Limit to selected sections'),
                value: _includeAll,
                onChanged: (v) => setState(() => _includeAll = v),
              ),
              if (!_includeAll)
                for (final (key, label) in const [
                  ('includeSummary', 'Medical summary'),
                  ('includeTimeline', 'Timeline & encounters'),
                  ('includeMedications', 'Medications'),
                  ('includeAllergies', 'Allergies'),
                  ('includeObservations', 'Lab results'),
                  ('includeDuplicateAlerts', 'Duplicate-test alerts'),
                ])
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(label),
                    value: _valueOf(key),
                    onChanged: (v) => _setValueOf(key, v),
                  ),
              if (!_includeAll) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(child: Text('Records to share', style: theme.textTheme.titleSmall)),
                    if (_documents.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          if (_selectedDocIds.length == _documents.length) {
                            _selectedDocIds.clear();
                          } else {
                            _selectedDocIds
                              ..clear()
                              ..addAll(_documents.map((d) => d.id));
                          }
                        }),
                        child: Text(_selectedDocIds.length == _documents.length ? 'Clear all' : 'Select all'),
                      ),
                  ],
                ),
                Text(
                  _documents.isEmpty
                      ? 'The doctor will only ever see the records you select here.'
                      : 'Pick the records the doctor may open — ${_selectedDocIds.length} of ${_documents.length} selected.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                if (_documentsLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_documentsError != null)
                  Row(
                    children: [
                      Expanded(child: Text(_documentsError!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error))),
                      TextButton(onPressed: _loadDocuments, child: const Text('Retry')),
                    ],
                  )
                else if (_documents.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'You have no records yet. Enable "Include ALL records", or upload a document first, then try again.',
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                  )
                else
                  for (final d in _documents)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: _selectedDocIds.contains(d.id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selectedDocIds.add(d.id);
                        } else {
                          _selectedDocIds.remove(d.id);
                        }
                      }),
                      title: Text(d.originalName, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          titleCase(d.category),
                          if ((d.providerName ?? '').isNotEmpty) d.providerName!,
                          if (d.eventDate != null) formatDateTime(d.eventDate),
                        ].join(' • '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
              ],
              const SizedBox(height: 20),
              Text('Expiry & access', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 60, label: Text('1 h')),
                  ButtonSegment(value: 1440, label: Text('1 day')),
                  ButtonSegment(value: 10080, label: Text('7 days')),
                  ButtonSegment(value: 43200, label: Text('30 days')),
                ],
                selected: {_expiry},
                onSelectionChanged: (s) => setState(() => _expiry = s.first),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: _maxAccesses,
                decoration: const InputDecoration(labelText: 'Max accesses (0 = unlimited)', prefixIcon: Icon(Icons.lock_clock_outlined)),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('Unlimited')),
                  DropdownMenuItem(value: 1, child: Text('1 access')),
                  DropdownMenuItem(value: 3, child: Text('3 accesses')),
                  DropdownMenuItem(value: 10, child: Text('10 accesses')),
                ],
                onChanged: (v) => setState(() => _maxAccesses = v ?? 0),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: (_busy || (!_includeAll && _selectedDocIds.isEmpty)) ? null : _create,
                child: _busy
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Generate share link'),
              ),
              if (!_includeAll && _selectedDocIds.isEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Select at least one record above, or switch on "Include ALL records".',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'The token is shown exactly once and never stored in readable form on the server.',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _valueOf(String key) => switch (key) {
        'includeSummary' => _includeSummary,
        'includeTimeline' => _includeTimeline,
        'includeMedications' => _includeMedications,
        'includeAllergies' => _includeAllergies,
        'includeObservations' => _includeObservations,
        'includeDuplicateAlerts' => _includeDuplicateAlerts,
        _ => false,
      };

  void _setValueOf(String key, bool v) => setState(() {
        switch (key) {
          case 'includeSummary':
            _includeSummary = v;
          case 'includeTimeline':
            _includeTimeline = v;
          case 'includeMedications':
            _includeMedications = v;
          case 'includeAllergies':
            _includeAllergies = v;
          case 'includeObservations':
            _includeObservations = v;
          case 'includeDuplicateAlerts':
            _includeDuplicateAlerts = v;
        }
      });
}

class _ShareResultSheet extends StatelessWidget {
  const _ShareResultSheet({required this.created});
  final ShareCreated created;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final qrData = created.absoluteUrl ?? created.shareUrl;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 44, color: theme.colorScheme.primary),
            const SizedBox(height: 8),
            Text('Share created', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(data: qrData, version: QrVersions.auto, size: 220),
            ),
            const SizedBox(height: 8),
            Text('Scan to open the share page (no medical data in the QR — only an opaque, revocable link).', textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
            const SizedBox(height: 16),
            Card(
              color: theme.colorScheme.surfaceContainerHigh,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Secret token (shown once)', style: theme.textTheme.labelMedium),
                    SelectableText(
                      created.token,
                      style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace', letterSpacing: 1),
                    ),
                    const SizedBox(height: 10),
                    Text('Share link', style: theme.textTheme.labelMedium),
                    Text(qrData, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Clipboard.setData(ClipboardData(text: qrData)),
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('Copy link'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}