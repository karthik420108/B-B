'use strict';

/* eslint-disable no-console */
/**
 * Synthetic hackathon demo data.
 *
 * Everything created here is FICTIONAL. It exercises the real pipeline:
 * generated PDF/PNG files are processed by the genuine OCR + extraction
 * pipeline, and the resulting FHIR-ish resources drive the timeline, AI
 * assistant, duplicate detection and medication alerts.
 *
 * Usage:
 *   npm run seed          # add demo data (fails if already seeded)
 *   npm run seed:reset    # wipe demo collections, then seed
 */

const config = require('../config');
const db = require('../config/db');
const {
  User, PatientProfile, DoctorProfile, Provider, Document, Observation, Condition,
  AllergyIntolerance, MedicationStatement, Encounter, ShareGrant, AuditEvent,
  Notification, Appointment, ExtractionJob,
} = require('../models');
const authService = require('../services/authService');
const patientService = require('../services/patientService');
const documentsService = require('../services/documentsService');
const { makePdf, makeReportPng, makePlainText } = require('./documentFactory');
const { normalizeTestName } = require('../utils/clinical');
const logger = require('../utils/logger');

const PATIENT_EMAIL = 'patient@demo.health';
const DOCTOR_EMAIL = 'doctor@demo.health';
const DOCTOR2_EMAIL = 'doctor2@demo.health';
const DEMO_PASSWORD = 'DemoPass123!';

const PROVIDERS = [
  { name: 'Meridian Primary Care Clinic', type: 'clinic' },
  { name: 'Northlake Diagnostic Laboratory', type: 'laboratory' },
  { name: 'Riverside City Hospital', type: 'hospital' },
  { name: 'GreenCross Pharmacy', type: 'pharmacy' },
];

const COLLECTIONS = [
  User, PatientProfile, DoctorProfile, Provider, Document, Observation, Condition,
  AllergyIntolerance, MedicationStatement, Encounter, ShareGrant, AuditEvent,
  Notification, Appointment, ExtractionJob,
];

async function reset() {
  await Promise.all(COLLECTIONS.map((m) => m.deleteMany({})));
  logger.info('Demo collections cleared.');
}

async function ensureProviders() {
  const map = new Map();
  for (const p of PROVIDERS) {
    // eslint-disable-next-line no-await-in-loop
    const existing = await Provider.findOneAndUpdate(
      { name: p.name },
      { $set: { type: p.type, fictional: true } },
      { upsert: true, new: true, setDefaultsOnInsert: true }
    );
    map.set(p.name, existing);
  }
  return map;
}

/** A document definition used by the seeder. */
function buildDocuments() {
  return [
    {
      providerName: 'Meridian Primary Care Clinic',
      category: 'consultation_note',
      eventDate: '2026-01-15',
      originalName: 'Consultation-2026-01-15-Meridian.pdf',
      kind: 'pdf',
      title: 'Meridian Primary Care Clinic',
      lines: [
        'Consultation Note',
        'Date: 15 Jan 2026',
        'Patient: Aarav Sharma',
        'Chief Complaint: Increased thirst and fatigue for 3 weeks.',
        'Examination: BP 148/92 mmHg, pulse 88/min, weight 82 kg.',
        '',
        'Diagnosis:',
        'Type 2 Diabetes Mellitus',
        'Essential Hypertension',
        '',
        'Medications:',
        'Metformin 500 mg twice daily',
        'Amlodipine 5 mg once daily',
        '',
        'Advice: Low sugar diet, 30 minutes walking daily. Follow up after 4 weeks with HbA1c.',
      ],
    },
    {
      providerName: 'Northlake Diagnostic Laboratory',
      category: 'laboratory',
      eventDate: '2026-01-16',
      originalName: 'Lab-Report-2026-01-16-Northlake.png',
      kind: 'png',
      title: 'Northlake Diagnostic Laboratory',
      lines: [
        'Patient: Aarav Sharma    Date: 16 Jan 2026',
        'Specimen: Fasting blood',
        '',
        'Laboratory Results:',
        'Fasting Glucose 138 mg/dL (70 - 100) H',
        'HbA1c 7.6 % (4.0 - 5.6) H',
        'Total Cholesterol 210 mg/dL (125 - 200) H',
        'Creatinine 0.9 mg/dL (0.7 - 1.3)',
        'TSH 2.4 mIU/L (0.4 - 4.0)',
      ],
    },
    {
      providerName: 'GreenCross Pharmacy',
      category: 'prescription',
      eventDate: '2026-02-10',
      originalName: 'Prescription-2026-02-10-GreenCross.pdf',
      kind: 'pdf',
      title: 'GreenCross Pharmacy',
      lines: [
        'Prescription',
        'Date: 10 Feb 2026',
        'Rx:',
        'Metformin 500 mg twice daily',
        'Amlodipine 5 mg once daily',
        'Atorvastatin 10 mg at bedtime',
      ],
    },
    {
      providerName: 'Northlake Diagnostic Laboratory',
      category: 'laboratory',
      eventDate: '2026-04-02',
      originalName: 'Lab-Report-2026-04-02-Northlake.pdf',
      kind: 'pdf',
      title: 'Northlake Diagnostic Laboratory',
      lines: [
        'Laboratory Results',
        'Date: 02 Apr 2026',
        'Specimen: Fasting blood',
        'Fasting Glucose 121 mg/dL (70 - 100) H',
        'HbA1c 7.1 % (4.0 - 5.6) H',
      ],
    },
    {
      providerName: 'Riverside City Hospital',
      category: 'discharge_summary',
      eventDate: '2026-05-12',
      originalName: 'Discharge-Summary-2026-05-12-Riverside.pdf',
      kind: 'pdf',
      title: 'Riverside City Hospital',
      lines: [
        'Discharge Summary',
        'Admission Date: 08 May 2026',
        'Discharge Date: 12 May 2026',
        'Reason for admission: Palpitations and irregular pulse.',
        'Diagnosis:',
        'Atrial Fibrillation',
        'Type 2 Diabetes Mellitus',
        '',
        'Allergies:',
        'Sulfa drugs - hives',
        '',
        'Medications:',
        'Warfarin 5 mg once daily',
        'Metformin 500 mg twice daily',
        '',
        'Follow up in cardiology clinic after 2 weeks for INR check.',
      ],
    },
    {
      providerName: 'GreenCross Pharmacy',
      category: 'prescription',
      eventDate: '2026-06-05',
      originalName: 'Prescription-2026-06-05-GreenCross.pdf',
      kind: 'pdf',
      title: 'GreenCross Pharmacy',
      lines: [
        'Prescription',
        'Date: 05 Jun 2026',
        'Complaint: Right knee pain.',
        'Rx:',
        'Ibuprofen 400 mg twice daily',
      ],
    },
    {
      providerName: 'Northlake Diagnostic Laboratory',
      category: 'laboratory',
      eventDate: '2026-07-18',
      originalName: 'Lab-Report-2026-07-18-Northlake.png',
      kind: 'png',
      title: 'Northlake Diagnostic Laboratory',
      lines: [
        'Patient: Aarav Sharma   Date: 18 Jul 2026',
        'Specimen: Fasting blood',
        '',
        'Laboratory Results:',
        'Fasting Glucose 108 mg/dL (70 - 100) H',
        'HbA1c 6.9 % (4.0 - 5.6) H',
        'TSH 3.1 mIU/L (0.4 - 4.0)',
        'Creatinine 1.0 mg/dL (0.7 - 1.3)',
      ],
    },
    {
      providerName: 'GreenCross Pharmacy',
      category: 'prescription',
      eventDate: '2026-08-22',
      originalName: 'Prescription-2026-08-22-GreenCross.txt',
      kind: 'text',
      title: 'GreenCross Pharmacy',
      lines: [
        'Prescription',
        'Date: 22 Aug 2026',
        'Diagnosis:',
        'Hypothyroidism',
        'Medications:',
        'Levothyroxine 50 mcg once daily',
        'Omeprazole 20 mg once daily',
      ],
    },
  ];
}

/** Build the real file buffer + mime type for a document definition. */
async function buildFile(def) {
  if (def.kind === 'png') return { buffer: makeReportPng(def.title, def.lines), mimetype: 'image/png' };
  if (def.kind === 'text') return { buffer: makePlainText([def.title, ...def.lines]), mimetype: 'text/plain' };
  return { buffer: await makePdf(def.title, def.lines), mimetype: 'application/pdf' };
}

async function seed() {
  await ensureProviders();

  // ---- Users --------------------------------------------------------------
  const patientReg = await authService.register({
    email: PATIENT_EMAIL, password: DEMO_PASSWORD, name: 'Aarav Sharma', role: 'patient', phone: '+1-555-0142',
  });
  const patient = await User.findById(patientReg.user.id);

  await authService.register({
    email: DOCTOR_EMAIL, password: DEMO_PASSWORD, name: 'Dr. Maya Rao', role: 'doctor',
    doctorProfile: { specialty: 'Cardiology', clinicName: 'Riverside City Hospital', licenseNumber: 'DEMO-CARD-1024' },
  });
  const doctor = await User.findOne({ email: DOCTOR_EMAIL });
  await DoctorProfile.updateOne({ user: doctor._id }, { $set: { verification: { status: 'development', method: 'seed-script', verifiedAt: new Date() } } });

  await authService.register({
    email: DOCTOR2_EMAIL, password: DEMO_PASSWORD, name: 'Dr. Idris Khan', role: 'doctor',
    doctorProfile: { specialty: 'General Medicine', clinicName: 'Meridian Primary Care Clinic' },
  });
  const doctor2 = await User.findOne({ email: DOCTOR2_EMAIL });
  await DoctorProfile.updateOne({ user: doctor2._id }, { $set: { verification: { status: 'development', method: 'seed-script', verifiedAt: new Date() } } });

  // ---- Patient medical profile -------------------------------------------
  await patientService.updateProfile(patient._id, {
    dateOfBirth: '1979-06-11',
    sex: 'male',
    bloodGroup: 'B+',
    address: '14 Lakeview Road, Springfield (fictional)',
    chronicConditions: ['Type 2 Diabetes Mellitus', 'Essential Hypertension', 'Atrial Fibrillation'],
    medicalHistory: ['Appendectomy (2008)', 'Right knee osteoarthritis (2024)'],
    emergencyContacts: [{ name: 'Priya Sharma', relation: 'Spouse', phone: '+1-555-0143' }],
    onboardingComplete: true,
  });
  await patientService.addAllergy(patient._id, { substance: 'Penicillin', reaction: 'Rash', severity: 'moderate' });
  await patientService.updateEmergencyCard(patient._id, {
    enabled: true, shareConditions: true, shareAllergies: true, shareMedications: true,
    shareEmergencyContact: true, shareRecentResults: true,
  });

  // ---- Documents (real extraction pipeline) -------------------------------
  const defs = buildDocuments();
  const createdDocs = [];
  for (const def of defs) {
    // eslint-disable-next-line no-await-in-loop
    const built = await buildFile(def);
    const file = {
      buffer: built.buffer,
      originalname: def.originalName,
      mimetype: built.mimetype,
      size: built.buffer.length,
    };
    // eslint-disable-next-line no-await-in-loop
    const result = await documentsService.createDocument(patient, file, {
      originalName: def.originalName,
      category: def.category,
      providerName: def.providerName,
      eventDate: def.eventDate,
      source: def.kind === 'png' ? 'camera' : 'upload',
      tags: [def.providerName.split(' ')[0]],
    }, { req: null, extract: true });
    createdDocs.push({ def, doc: result.document, extraction: result.extraction });
    console.log(`  • ${def.originalName} -> ${result.extraction && result.extraction.status}`);
  }

  // Duplicate upload demo: re-import the exact stored bytes of the 2026-04-02
  // lab report so the content hash matches and duplicate detection fires.
  const dupeDoc = await Document.findOne({ patient: patient._id, originalName: 'Lab-Report-2026-04-02-Northlake.pdf' });
  const dupeFile = await documentsService.readDocumentFile(patient._id, dupeDoc._id);
  await documentsService.createDocument(patient, {
    buffer: dupeFile.buffer, originalname: 'lab-report-copy.pdf', mimetype: 'application/pdf', size: dupeFile.buffer.length,
  }, { originalName: 'lab-report-copy.pdf', category: 'laboratory', providerName: 'Northlake Diagnostic Laboratory', eventDate: '2026-04-02', source: 'upload', tags: ['duplicate-demo'] }, { req: null, extract: false });
  console.log('  • duplicate lab report imported (duplicate-detection demo)');

  // ---- Promote extracted data to a realistic reviewed state ---------------
  // The extraction marks everything `unverified / ai-extracted`. The patient has
  // since reviewed and confirmed the core items, so we reflect that here.
  const ACTIVE_MEDS = ['metformin', 'amlodipine', 'warfarin', 'ibuprofen', 'levothyroxine', 'omeprazole', 'atorvastatin'];
  const meds = await MedicationStatement.find({ patient: patient._id });
  for (const m of meds) {
    if (ACTIVE_MEDS.includes(m.normalizedName)) m.status = 'active';
  }
  // Atorvastatin, per the Feb prescription, was stopped in May (discontinued).
  await MedicationStatement.updateMany({ patient: patient._id, normalizedName: 'atorvastatin' }, { $set: { status: 'discontinued', endDate: new Date('2026-05-12') } });
  await Promise.all(meds.map((m) => m.save()));

  const ACTIVE_CONDITIONS = ['type 2 diabetes mellitus', 'essential hypertension', 'atrial fibrillation', 'hypothyroidism'];
  const conditions = await Condition.find({ patient: patient._id });
  for (const c of conditions) {
    if (ACTIVE_CONDITIONS.includes((c.normalizedName || c.name.toLowerCase()))) c.status = 'active';
  }
  await Promise.all(conditions.map((c) => c.save()));

  // Verify a representative subset so the UI shows a mix of verified/unverified.
  await Observation.updateMany(
    { patient: patient._id, normalizedTestName: { $in: ['hba1c', 'glucose fasting', 'tsh', 'creatinine'] } },
    { $set: { verification: 'verified' } }
  );
  await Condition.updateMany({ patient: patient._id }, { $set: { verification: 'verified' } });
  await MedicationStatement.updateMany({ patient: patient._id }, { $set: { verification: 'verified' } });
  await Document.updateMany({ patient: patient._id }, { $set: { extractionStatus: 'extracted' } });

  // ---- Appointments -------------------------------------------------------
  const now = Date.now();
  await Appointment.create({
    patient: patient._id, title: 'Cardiology follow-up', providerName: 'Riverside City Hospital',
    dateTime: new Date(now + 6 * 86400000), reason: 'INR review and anticoagulation follow-up', reminder: true, reminderMinutesBefore: 120,
  });
  await Appointment.create({
    patient: patient._id, title: 'Diabetes review', providerName: 'Meridian Primary Care Clinic',
    dateTime: new Date(now + 20 * 86400000), reason: 'HbA1c and blood pressure review', reminder: true, reminderMinutesBefore: 60,
  });

  // ---- Summary ------------------------------------------------------------
  const counts = {
    documents: await Document.countDocuments({ patient: patient._id, deletedAt: null }),
    observations: await Observation.countDocuments({ patient: patient._id, deletedAt: null }),
    conditions: await Condition.countDocuments({ patient: patient._id, deletedAt: null }),
    allergies: await AllergyIntolerance.countDocuments({ patient: patient._id, deletedAt: null }),
    medications: await MedicationStatement.countDocuments({ patient: patient._id, deletedAt: null }),
    encounters: await Encounter.countDocuments({ patient: patient._id, deletedAt: null }),
  };

  return { patient, doctor, doctor2, counts, docs: createdDocs };
}

async function main() {
  const shouldReset = process.argv.includes('--reset');
  await db.connect();
  if (shouldReset) await reset();

  const existing = await User.findOne({ email: PATIENT_EMAIL });
  if (existing && !shouldReset) {
    console.log('\nDemo data already present. Re-run with --reset to rebuild, or use `npm run seed:reset`.');
    await db.disconnect();
    return;
  }

  console.log('\nSeeding synthetic demo data (all records are fictional)...\n');
  const result = await seed();

  console.log('\n──────────── DEMO READY ────────────');
  console.log('Patient  : %s  /  %s', PATIENT_EMAIL, DEMO_PASSWORD);
  console.log('Doctor   : %s  /  %s  (Dr. Maya Rao, Cardiology)', DOCTOR_EMAIL, DEMO_PASSWORD);
  console.log('Doctor 2 : %s  /  %s  (Dr. Idris Khan, General Medicine)', DOCTOR2_EMAIL, DEMO_PASSWORD);
  console.log('Records  : %o', result.counts);
  console.log('Providers: Meridian Clinic · Northlake Lab · Riverside Hospital · GreenCross Pharmacy');
  console.log('Highlights: repeated HbA1c/glucose results, Warfarin + Ibuprofen interaction, duplicate lab upload.');
  console.log('────────────────────────────────────\n');

  await db.disconnect();
}

if (require.main === module) {
  main().catch(async (err) => {
    console.error('Seed failed:', err);
    try { await db.disconnect(); } catch { /* ignore */ }
    process.exit(1);
  });
}

module.exports = { main, seed, reset, PATIENT_EMAIL, DOCTOR_EMAIL, DEMO_PASSWORD };
