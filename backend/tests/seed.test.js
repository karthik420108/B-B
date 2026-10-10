'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { test, before, after } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');
const seedModule = require('../src/seed/seed');
const {
  User, Provider, Document, Observation, MedicationStatement, Condition, Appointment,
} = require('../src/models');

before(h.connect);
after(h.disconnect);

let result;

test('demo seed creates fictional providers, users and a rich record set', async (t) => {
  await h.clearDatabase();
  result = await seedModule.seed();

  const providers = await Provider.find({ fictional: true });
  assert.ok(providers.length >= 4, 'four fictional providers');
  const types = providers.map((p) => p.type);
  assert.ok(types.includes('clinic'));
  assert.ok(types.includes('laboratory'));
  assert.ok(types.includes('hospital'));
  assert.ok(types.includes('pharmacy'));

  const patient = await User.findOne({ email: seedModule.PATIENT_EMAIL });
  assert.ok(patient, 'demo patient exists');

  const docs = await Document.find({ patient: patient._id, deletedAt: null });
  assert.ok(docs.length >= 8, 'multiple documents');
  const mimes = new Set(docs.map((d) => d.mimeType));
  assert.ok(mimes.size >= 2, 'different document formats (pdf + image)');

  t.diagnostic(`seeded ${docs.length} documents, ${result.counts.observations} observations`);
});

test('demo includes repeated tests and a medication interaction, and no real credentials', async () => {
  const patient = await User.findOne({ email: seedModule.PATIENT_EMAIL });

  // Repeated test: more than one HbA1c observation.
  const hba1c = await Observation.find({ patient: patient._id, normalizedTestName: 'hba1c' });
  assert.ok(hba1c.length >= 2, 'repeated HbA1c for duplicate-test demo');

  // Interaction: warfarin + ibuprofen both active.
  const meds = await MedicationStatement.find({ patient: patient._id });
  const norms = meds.map((m) => m.normalizedName);
  assert.ok(norms.includes('warfarin'));
  assert.ok(norms.includes('ibuprofen'));

  const conditions = await Condition.find({ patient: patient._id });
  assert.ok(conditions.length >= 3);

  const appts = await Appointment.find({ patient: patient._id });
  assert.ok(appts.length >= 1, 'upcoming appointments for reminders');

  // Safety: the demo seed must never contain real credentials. The original
  // check required an empty OPENAI_API_KEY in the test process, but local
  // development may legitimately configure a Gemini key in the gitignored
  // `.env`. Assert the same guarantee on the committed artifacts instead: the
  // seed source must not reference API keys, and the committed example must
  // leave every key empty.
  const seedSource = fs.readFileSync(path.join(__dirname, '../src/seed/seed.js'), 'utf8');
  assert.equal(/api[_-]?key/i.test(seedSource), false, 'seed source references no API keys');

  const example = fs.readFileSync(path.join(__dirname, '../.env.example'), 'utf8');
  const filledKeys = example.split('\n').filter(
    (l) => /^\s*[A-Z_]*API[_-]?KEY=/i.test(l.trim()) && /\S+/.test(l.split('=')[1] || '')
  );
  assert.deepEqual(filledKeys, [], 'example file leaves every API key empty');
});

test('demo database can be reset safely and idempotently', async () => {
  await seedModule.reset();
  const docs = await Document.countDocuments({});
  assert.equal(docs, 0, 'reset clears demo collections');
});
