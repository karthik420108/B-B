import 'dart:convert';

/// Consolidated, lightweight DTOs mirroring the backend JSON `data` objects.

String _s(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();
bool _b(dynamic v, [bool fallback = false]) => v is bool ? v : (v == null ? fallback : v == true);
int _i(dynamic v, [int fallback = 0]) => v is int ? v : (v is num ? v.toInt() : fallback);
double _d(dynamic v, [double fallback = 0]) => v is num ? v.toDouble() : (v is String ? (double.tryParse(v) ?? fallback) : fallback);
DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

/// Light-weight user session payload.
class AuthData {
  AuthData({
    required this.accessToken,
    required this.refreshToken,
    this.expiresIn,
    this.user,
  });

  factory AuthData.fromJson(Map<String, dynamic> json) => AuthData(
        accessToken: _s(json['accessToken']),
        refreshToken: _s(json['refreshToken']),
        expiresIn: json['expiresIn']?.toString(),
        user: json['user'] != null ? User.fromJson(json['user'] as Map<String, dynamic>) : null,
      );

  final String accessToken;
  final String refreshToken;
  final String? expiresIn;
  final User? user;
}

class User {
  User({required this.id, required this.name, required this.email, required this.role, this.doctorVerification});

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: _s(json['id']),
        name: _s(json['name']),
        email: _s(json['email']),
        role: _s(json['role'], 'patient'),
        doctorVerification: json['doctorVerification']?.toString(),
      );

  final String id;
  final String name;
  final String email;
  final String role;

  /// Doctor identity-verification status (`unverified`, `development`, `verified`).
  /// Only present for doctor accounts.
  final String? doctorVerification;

  bool get isPatient => role == 'patient';
  bool get isDoctor => role == 'doctor';
  bool get isDoctorVerified => isDoctor && (doctorVerification == 'verified' || doctorVerification == 'development');

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'email': email, 'role': role, 'doctorVerification': doctorVerification};
}

class DocumentSummary {
  DocumentSummary({
    required this.id,
    required this.originalName,
    required this.category,
    required this.mimeType,
    required this.size,
    required this.extractionStatus,
    this.eventDate,
    this.providerName,
    this.pageCount = 0,
    this.tags = const [],
  });

  factory DocumentSummary.fromJson(Map<String, dynamic> json) => DocumentSummary(
        id: _s(json['id']),
        originalName: _s(json['originalName']),
        category: _s(json['category'], 'other'),
        mimeType: _s(json['mimeType']),
        size: _i(json['size']),
        extractionStatus: _s(json['extractionStatus'], 'pending'),
        eventDate: _dt(json['eventDate']),
        providerName: json['providerName']?.toString(),
        pageCount: _i(json['pageCount']),
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );

  final String id;
  final String originalName;
  final String category;
  final String mimeType;
  final int size;
  final String extractionStatus;
  final DateTime? eventDate;
  final String? providerName;
  final int pageCount;
  final List<String> tags;
}

class TimelineItem {
  TimelineItem({
    required this.kind,
    required this.title,
    required this.id,
    required this.date,
    this.dateUnknown = false,
    this.providerName,
    this.subtitle,
    this.status,
    this.source,
    this.verification,
    this.value,
    this.unit,
  });

  factory TimelineItem.fromJson(Map<String, dynamic> json) => TimelineItem(
        kind: _s(json['kind']),
        title: _s(json['title']),
        id: _s(json['id']),
        date: _dt(json['date']),
        dateUnknown: _b(json['dateUnknown']),
        providerName: json['providerName']?.toString(),
        subtitle: json['subtitle']?.toString(),
        status: json['status']?.toString(),
        source: json['source']?.toString(),
        verification: json['verification']?.toString(),
        value: json['value']?.toString(),
        unit: json['unit']?.toString(),
      );

  final String kind;
  final String title;
  final String id;
  final DateTime? date;
  final bool dateUnknown;
  final String? providerName;
  final String? subtitle;
  final String? status;
  final String? source;
  final String? verification;
  final String? value;
  final String? unit;

  String get kindLabel {
    switch (kind) {
      case 'observation':
        return 'Lab result';
      case 'medication':
        return 'Medication';
      case 'condition':
        return 'Diagnosis';
      case 'allergy':
        return 'Allergy';
      case 'encounter':
        return 'Visit';
      case 'document':
        return 'Document';
      default:
        return 'Record';
    }
  }
}

class Observation {
  Observation({
    required this.id,
    required this.testName,
    required this.verification,
    required this.value,
    this.valueString,
    this.unit,
    this.referenceRange,
    this.date,
    this.abnormal,
    this.providerName,
    this.source,
    this.confidence,
  });

  factory Observation.fromJson(Map<String, dynamic> json) => Observation(
        id: _s(json['id']),
        testName: _s(json['testName']),
        verification: _s(json['verification'], 'unverified'),
        value: _d(json['value'], double.nan),
        valueString: json['valueString']?.toString(),
        unit: json['unit']?.toString(),
        referenceRange: json['referenceRange']?.toString(),
        date: _dt(json['date']),
        abnormal: json['abnormal'],
        providerName: json['providerName']?.toString(),
        source: json['source']?.toString(),
        confidence: json['confidence'],
      );

  final String id;
  final String testName;
  final String verification;
  final double value;
  final String? valueString;
  final String? unit;
  final String? referenceRange;
  final DateTime? date;
  final dynamic abnormal;
  final String? providerName;
  final String? source;
  final dynamic confidence;

  bool get hasValue => value.isFinite || (valueString?.isNotEmpty ?? false);

  String get displayValue =>
      value.isFinite ? '$value${unit != null ? ' $unit' : ''}' : (valueString ?? '—');

  bool get isVerified => verification == 'verified';
}

class Medication {
  Medication({
    required this.id,
    required this.name,
    required this.status,
    required this.verification,
    this.genericName,
    this.strength,
    this.frequency,
    this.route,
    this.form,
    this.startDate,
    this.endDate,
    this.prescriber,
    this.providerName,
    this.source,
  });

  factory Medication.fromJson(Map<String, dynamic> json) => Medication(
        id: _s(json['id']),
        name: _s(json['name']),
        status: _s(json['status'], 'unknown'),
        verification: _s(json['verification'], 'unverified'),
        genericName: json['genericName']?.toString(),
        strength: json['strength']?.toString(),
        frequency: json['frequency']?.toString(),
        route: json['route']?.toString(),
        form: json['form']?.toString(),
        startDate: _dt(json['startDate']),
        endDate: _dt(json['endDate']),
        prescriber: json['prescriber']?.toString(),
        providerName: json['providerName']?.toString(),
        source: json['source']?.toString(),
      );

  final String id;
  final String name;
  final String status;
  final String verification;
  final String? genericName;
  final String? strength;
  final String? frequency;
  final String? route;
  final String? form;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? prescriber;
  final String? providerName;
  final String? source;

  bool get isActive => status == 'active';
}

class Allergy {
  Allergy({required this.id, required this.substance, this.reaction, this.severity, this.verification, this.source});
  factory Allergy.fromJson(Map<String, dynamic> json) => Allergy(
        id: _s(json['id']),
        substance: _s(json['substance']),
        reaction: json['reaction']?.toString(),
        severity: json['severity']?.toString(),
        verification: json['verification']?.toString(),
        source: json['source']?.toString(),
      );
  final String id;
  final String substance;
  final String? reaction;
  final String? severity;
  final String? verification;
  final String? source;
}

class ConditionRecord {
  ConditionRecord({required this.id, required this.name, this.onsetDate, this.status, this.verification, this.providerName});
  factory ConditionRecord.fromJson(Map<String, dynamic> json) => ConditionRecord(
        id: _s(json['id']),
        name: _s(json['name']),
        onsetDate: _dt(json['onsetDate']),
        status: json['status']?.toString(),
        verification: json['verification']?.toString(),
        providerName: json['providerName']?.toString(),
      );
  final String id;
  final String name;
  final DateTime? onsetDate;
  final String? status;
  final String? verification;
  final String? providerName;
}

class EncounterRecord {
  EncounterRecord({required this.id, required this.type, this.date, this.providerName, this.diagnosis = const []});
  factory EncounterRecord.fromJson(Map<String, dynamic> json) => EncounterRecord(
        id: _s(json['id']),
        type: _s(json['type']),
        date: _dt(json['date']),
        providerName: json['providerName']?.toString(),
        diagnosis: (json['diagnosis'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      );
  final String id;
  final String type;
  final DateTime? date;
  final String? providerName;
  final List<String> diagnosis;
}

class DuplicateFinding {
  DuplicateFinding({
    required this.kind,
    required this.normalizedTestName,
    required this.confidence,
    required this.reason,
    required this.recommendation,
    this.gapDays,
    this.date,
    this.value,
    this.unit,
  });

  factory DuplicateFinding.fromJson(Map<String, dynamic> json) => DuplicateFinding(
        kind: _s(json['kind'], 'repeated_test'),
        normalizedTestName: _s(json['normalizedTestName']),
        confidence: _d(json['confidence']),
        reason: _s(json['reason']),
        recommendation: _s(json['recommendation']),
        gapDays: json['gapDays'],
        date: _dt((json['current'] as Map<String, dynamic>?)?['date']),
        value: (json['current'] as Map<String, dynamic>?)?['value'],
        unit: (json['current'] as Map<String, dynamic>?)?['unit']?.toString(),
      );

  final String kind;
  final String normalizedTestName;
  final double confidence;
  final String reason;
  final String recommendation;
  final dynamic gapDays;
  final DateTime? date;
  final dynamic value;
  final String? unit;

  bool get isDuplicateUpload => kind == 'possible_duplicate_upload';
}

class InteractionAlert {
  InteractionAlert({
    required this.title,
    required this.severity,
    required this.effect,
    required this.recommendation,
    this.medications = const [],
    this.source = 'validated-dataset',
  });

  factory InteractionAlert.fromJson(Map<String, dynamic> json) => InteractionAlert(
        title: _s(json['title']),
        severity: _s(json['severity'], 'unknown'),
        effect: _s(json['effect']),
        recommendation: _s(json['recommendation']),
        medications: (json['medications'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        source: json['source']?.toString() ?? 'validated-dataset',
      );

  final String title;
  final String severity;
  final String effect;
  final String recommendation;
  final List<String> medications;
  final String source;
}

class MedicationSafetyReport {
  MedicationSafetyReport({
    required this.checkerAvailable,
    this.interactions = const [],
    this.duplicates = const [],
  });

  factory MedicationSafetyReport.fromJson(Map<String, dynamic> json) => MedicationSafetyReport(
        checkerAvailable: _b(json['checkerAvailable'], true),
        interactions: (json['interactions'] as List?)
                ?.map((e) => InteractionAlert.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        duplicates: (json['duplicates'] as List?)
                ?.map((e) => DuplicateFinding.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  final bool checkerAvailable;
  final List<InteractionAlert> interactions;
  final List<DuplicateFinding> duplicates;
}

class Citation {
  Citation({required this.kind, this.recordId, this.documentId, this.documentName, this.label, this.date, this.providerName});
  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        kind: _s(json['kind']),
        recordId: json['recordId']?.toString(),
        documentId: json['documentId']?.toString(),
        documentName: json['documentName']?.toString(),
        label: json['label']?.toString(),
        date: _dt(json['date']),
        providerName: json['providerName']?.toString(),
      );
  final String kind;
  final String? recordId;
  final String? documentId;
  final String? documentName;
  final String? label;
  final DateTime? date;
  final String? providerName;
}

class AiAnswer {
  AiAnswer({
    required this.answer,
    required this.grounded,
    required this.provider,
    this.citations = const [],
    this.uncertainty,
    this.disclaimer,
    this.question = '',
  });

  factory AiAnswer.fromJson(Map<String, dynamic> json) => AiAnswer(
        question: _s(json['question']),
        answer: _s(json['answer']),
        grounded: _b(json['grounded']),
        provider: _s(json['provider'], 'local'),
        citations: (json['citations'] as List?)
                ?.map((e) => Citation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        uncertainty: json['uncertainty'] is Map<String, dynamic>
            ? Uncertainty.fromJson(json['uncertainty'] as Map<String, dynamic>)
            : null,
        disclaimer: json['disclaimer']?.toString(),
      );

  final String question;
  final String answer;
  final bool grounded;
  final String provider;
  final List<Citation> citations;
  final Uncertainty? uncertainty;
  final String? disclaimer;
}

class Uncertainty {
  Uncertainty({required this.level, this.missing = false, this.reason});
  factory Uncertainty.fromJson(Map<String, dynamic> json) => Uncertainty(
        level: _s(json['level'], 'low'),
        missing: _b(json['missing']),
        reason: json['reason']?.toString(),
      );
  final String level;
  final bool missing;
  final String? reason;
}

class MedicalSummary {
  MedicalSummary({
    required this.narrative,
    required this.missing,
    required this.citations,
    required this.generatedAt,
    required this.disclaimer,
    this.counts = const {},
  });

  factory MedicalSummary.fromJson(Map<String, dynamic> json) => MedicalSummary(
        narrative: _s(json['narrative']),
        missing: (json['missing'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        citations: (json['citations'] as List?)
                ?.map((e) => Citation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        generatedAt: json['generatedAt']?.toString() ?? '',
        disclaimer: _s(json['disclaimer']),
        counts: (json['counts'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, _i(v))) ?? const {},
      );

  final String narrative;
  final List<String> missing;
  final List<Citation> citations;
  final String generatedAt;
  final String disclaimer;
  final Map<String, int> counts;
}

class ShareGrant {
  ShareGrant({
    required this.id,
    required this.status,
    this.label,
    this.doctorName,
    this.doctorEmail,
    this.expiresAt,
    this.createdAt,
    this.accessCount = 0,
    this.tokenPreview,
    this.isActive = false,
    this.documentCount = 0,
  });

  factory ShareGrant.fromJson(Map<String, dynamic> json) => ShareGrant(
        id: _s(json['id']),
        status: _s(json['status']),
        label: json['label']?.toString(),
        doctorName: json['doctorName']?.toString(),
        doctorEmail: json['doctorEmail']?.toString(),
        expiresAt: _dt(json['expiresAt']),
        createdAt: _dt(json['createdAt']),
        accessCount: _i(json['accessCount']),
        tokenPreview: json['tokenPreview']?.toString(),
        isActive: _b(json['isActive']),
        documentCount: _i(json['documentCount']),
      );

  final String id;
  final String status;
  final String? label;
  final String? doctorName;
  final String? doctorEmail;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final int accessCount;
  final String? tokenPreview;
  final bool isActive;
  final int documentCount;
}

class ShareCreated {
  ShareCreated({required this.share, required this.token, required this.shareUrl, this.absoluteUrl});
  factory ShareCreated.fromJson(Map<String, dynamic> json) => ShareCreated(
        share: ShareGrant.fromJson(json['share'] as Map<String, dynamic>),
        token: _s(json['token']),
        shareUrl: _s(json['shareUrl']),
        absoluteUrl: json['absoluteUrl']?.toString(),
      );
  final ShareGrant share;
  final String token;
  final String shareUrl;
  final String? absoluteUrl;
}

class AccessLogEntry {
  AccessLogEntry({required this.action, required this.at, this.actorRole, this.detail});
  factory AccessLogEntry.fromJson(Map<String, dynamic> json) => AccessLogEntry(
        action: _s(json['action']),
        at: _dt(json['at']),
        actorRole: json['actorRole']?.toString(),
        detail: json['detail']?.toString(),
      );
  final String action;
  final DateTime? at;
  final String? actorRole;
  final String? detail;
}

class ShareDetail {
  ShareDetail({
    required this.id,
    required this.status,
    required this.accessCount,
    required this.documentCount,
    required this.accessLog,
    this.label,
    this.doctorName,
    this.doctorEmail,
    this.expiresAt,
    this.createdAt,
    this.isActive = false,
    this.permissions = const {},
  });

  factory ShareDetail.fromJson(Map<String, dynamic> json) => ShareDetail(
        id: _s(json['id']),
        status: _s(json['status']),
        accessCount: _i(json['accessCount']),
        documentCount: _i(json['documentCount']),
        accessLog: (json['accessLog'] as List?)
                ?.map((e) => AccessLogEntry.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        label: json['label']?.toString(),
        doctorName: json['doctorName']?.toString(),
        doctorEmail: json['doctorEmail']?.toString(),
        expiresAt: _dt(json['expiresAt']),
        createdAt: _dt(json['createdAt']),
        isActive: _b(json['isActive']),
        permissions: (json['permissions'] as Map<String, dynamic>?)?.cast<String, dynamic>() ?? const {},
      );

  final String id;
  final String status;
  final int accessCount;
  final int documentCount;
  final List<AccessLogEntry> accessLog;
  final String? label;
  final String? doctorName;
  final String? doctorEmail;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final bool isActive;
  final Map<String, dynamic> permissions;
}

/// A doctor-facing bundle assembled from a share token.
class DoctorBundle {
  DoctorBundle({
    required this.patientName,
    required this.documents,
    required this.observations,
    required this.conditions,
    required this.allergies,
    required this.medications,
    required this.duplicateAlerts,
    required this.medicationAlerts,
    this.patientDateOfBirth,
    this.generatedAt,
    this.permissions = const {},
  });

  factory DoctorBundle.fromJson(Map<String, dynamic> json) {
    final patient = (json['patient'] as Map<String, dynamic>?) ?? const {};
    return DoctorBundle(
      patientName: _s(patient['name'], 'Patient'),
      patientDateOfBirth: _dt(patient['dateOfBirth']),
      documents: (json['documents'] as List?)
              ?.map((e) => DocumentSummary.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      observations: (json['observations'] as List?)
              ?.map((e) => Observation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      conditions: (json['conditions'] as List?)
              ?.map((e) => ConditionRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      allergies: (json['allergies'] as List?)
              ?.map((e) => Allergy.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      medications: (json['medications'] as List?)
              ?.map((e) => Medication.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      duplicateAlerts: (json['duplicateAlerts'] as List?)
              ?.map((e) => DuplicateFinding.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      medicationAlerts: json['medicationAlerts'] != null
          ? MedicationSafetyReport.fromJson(json['medicationAlerts'] as Map<String, dynamic>)
          : null,
    );
  }

  final String patientName;
  final DateTime? patientDateOfBirth;
  final List<DocumentSummary> documents;
  final List<Observation> observations;
  final List<ConditionRecord> conditions;
  final List<Allergy> allergies;
  final List<Medication> medications;
  final List<DuplicateFinding> duplicateAlerts;
  final MedicationSafetyReport? medicationAlerts;
  final String? generatedAt;
  final Map<String, dynamic> permissions;
}

class Appointment {
  Appointment({required this.id, required this.title, required this.dateTime, this.providerName, this.reason, this.reminder = false});
  factory Appointment.fromJson(Map<String, dynamic> json) => Appointment(
        id: _s(json['id']),
        title: _s(json['title']),
        dateTime: _dt(json['dateTime']) ?? DateTime.now(),
        providerName: json['providerName']?.toString(),
        reason: json['reason']?.toString(),
        reminder: _b(json['reminder']),
      );
  final String id;
  final String title;
  final DateTime dateTime;
  final String? providerName;
  final String? reason;
  final bool reminder;
}

class PatientProfile {
  PatientProfile({
    this.id,
    this.dateOfBirth,
    this.sex,
    this.bloodGroup,
    this.address,
    this.chronicConditions = const [],
    this.medicalHistory = const [],
    this.currentMedicationsText = const [],
    this.emergencyContacts = const [],
    this.allergies = const [],
    this.emergencyCard = const {},
  });
  factory PatientProfile.fromJson(Map<String, dynamic> json) => PatientProfile(
        id: json['id']?.toString() ?? json['_id']?.toString(),
        dateOfBirth: _dt(json['dateOfBirth']),
        sex: json['sex']?.toString(),
        bloodGroup: json['bloodGroup']?.toString(),
        address: json['address']?.toString(),
        chronicConditions: (json['chronicConditions'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        medicalHistory: (json['medicalHistory'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        currentMedicationsText: (json['currentMedicationsText'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        emergencyContacts: (json['emergencyContacts'] as List?)
                ?.map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        allergies: (json['allergies'] as List?)
                ?.map((e) => ProfileAllergy.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        emergencyCard: (json['emergencyCard'] as Map<String, dynamic>?) ?? const {},
      );
  final String? id;
  final DateTime? dateOfBirth;
  final String? sex;
  final String? bloodGroup;
  final String? address;
  final List<String> chronicConditions;
  final List<String> medicalHistory;
  final List<String> currentMedicationsText;
  final List<EmergencyContact> emergencyContacts;
  final List<ProfileAllergy> allergies;
  final Map<String, dynamic> emergencyCard;
}

class EmergencyContact {
  const EmergencyContact({this.name = '', this.relation, this.phone});
  factory EmergencyContact.fromJson(Map<String, dynamic> json) => EmergencyContact(
        name: _s(json['name']),
        relation: json['relation']?.toString(),
        phone: json['phone']?.toString(),
      );
  final String name;
  final String? relation;
  final String? phone;
}

class ProfileAllergy {
  const ProfileAllergy({this.substance = '', this.reaction, this.severity, this.verification});
  factory ProfileAllergy.fromJson(Map<String, dynamic> json) => ProfileAllergy(
        substance: _s(json['substance']),
        reaction: json['reaction']?.toString(),
        severity: json['severity']?.toString(),
        verification: json['verification']?.toString(),
      );
  final String substance;
  final String? reaction;
  final String? severity;
  final String? verification;
}

/// Emergency card snapshot assembled server-side from consented data.
class EmergencyCardData {
  EmergencyCardData({
    required this.enabled,
    required this.settings,
    required this.missing,
    required this.disclaimer,
    this.bloodGroup,
    this.conditions = const [],
    this.allergies = const [],
    this.medications = const [],
    this.emergencyContacts = const [],
    this.recentResults = const [],
  });
  factory EmergencyCardData.fromJson(Map<String, dynamic> json) => EmergencyCardData(
        enabled: _b(json['enabled']),
        settings: (json['settings'] as Map<String, dynamic>?) ?? const {},
        bloodGroup: json['bloodGroup']?.toString(),
        conditions: (json['conditions'] as List?)
                ?.map((e) => ConditionRecord.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        allergies: (json['allergies'] as List?)
                ?.map((e) => ProfileAllergy.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        medications: (json['medications'] as List?)
                ?.map((e) => Medication.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        emergencyContacts: (json['emergencyContacts'] as List?)
                ?.map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        recentResults: (json['recentResults'] as List?)
                ?.map((e) => Observation.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        missing: (json['missing'] as List?)?.map((e) => e.toString()).toList() ?? const [],
        disclaimer: _s(json['disclaimer']),
      );
  final bool enabled;
  final Map<String, dynamic> settings;
  final String? bloodGroup;
  final List<ConditionRecord> conditions;
  final List<ProfileAllergy> allergies;
  final List<Medication> medications;
  final List<EmergencyContact> emergencyContacts;
  final List<Observation> recentResults;
  final List<String> missing;
  final String disclaimer;
}

class AppNotification {
  AppNotification({required this.id, required this.title, required this.body, required this.read, this.createdAt, this.type});
  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: _s(json['id']),
        title: _s(json['title']),
        body: _s(json['body']),
        read: _b(json['read']),
        createdAt: _dt(json['createdAt']),
        type: json['type']?.toString(),
      );
  final String id;
  final String title;
  final String body;
  final bool read;
  final DateTime? createdAt;
  final String? type;
}

class DashboardData {
  DashboardData({
    this.recentDocuments = const [],
    this.upcomingAppointments = const [],
    this.medicationAlerts,
    this.counts = const {},
    this.notifications = const [],
  });

  factory DashboardData.fromJson(Map<String, dynamic> json) => DashboardData(
        recentDocuments: (json['recentDocuments'] as List?)
                ?.map((e) => DocumentSummary.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        upcomingAppointments: (json['upcomingAppointments'] as List?)
                ?.map((e) => Appointment.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        medicationAlerts: json['medicationAlerts'] != null
            ? MedicationSafetyReport.fromJson(json['medicationAlerts'] as Map<String, dynamic>)
            : null,
        counts: (json['counts'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, _i(v))) ?? const {},
        notifications: (json['notifications'] as List?)
                ?.map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  final List<DocumentSummary> recentDocuments;
  final List<Appointment> upcomingAppointments;
  final MedicationSafetyReport? medicationAlerts;
  final Map<String, int> counts;
  final List<AppNotification> notifications;
}

/// Extracted data attached to a document detail response.
class ExtractedBundle {
  ExtractedBundle({
    this.observations = const [],
    this.conditions = const [],
    this.allergies = const [],
    this.medications = const [],
    this.encounters = const [],
  });

  factory ExtractedBundle.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ExtractedBundle();
    return ExtractedBundle(
      observations: (json['observations'] as List?)
              ?.map((e) => Observation.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      conditions: (json['conditions'] as List?)
              ?.map((e) => ConditionRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      allergies: (json['allergies'] as List?)
              ?.map((e) => Allergy.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      medications: (json['medications'] as List?)
              ?.map((e) => Medication.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      encounters: (json['encounters'] as List?)
              ?.map((e) => EncounterRecord.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  final List<Observation> observations;
  final List<ConditionRecord> conditions;
  final List<Allergy> allergies;
  final List<Medication> medications;
  final List<EncounterRecord> encounters;
}

class DocumentDetail {
  DocumentDetail({required this.document, this.extracted, this.rawText});

  factory DocumentDetail.fromJson(Map<String, dynamic> json) => DocumentDetail(
        document: DocumentSummary.fromJson(json),
        extracted: ExtractedBundle.fromJson(json['extracted'] as Map<String, dynamic>?),
        rawText: json['rawText']?.toString(),
      );

  final DocumentSummary document;
  final ExtractedBundle? extracted;
  final String? rawText;
}

/// Small helper for payload builders.
String encodeJson(Map<String, dynamic> map) => jsonEncode(map);