'use strict';

const config = require('../config');
const {
  MedicationSchedule, MedicationDose, Document,
} = require('../models');
const { getStorage } = require('../storage');
const { badRequest, notFound, conflict, unprocessable } = require('../utils/errors');
const { parsePagination } = require('../utils/http');
const auditService = require('./auditService');
const notificationService = require('./notificationService');
const extractionService = require('./extractionService');
const { extractStructured } = require('./extraction/structuredExtractor');
const logger = require('../utils/logger');

const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;
const FREQUENCY_COUNT = { once_daily: 1, twice_daily: 2, three_times_daily: 3 };
const SOURCE_TYPES = ['MANUAL', 'PRESCRIPTION'];
const SCHEDULE_STATUSES = ['ACTIVE', 'PAUSED', 'COMPLETED', 'DISCONTINUED'];
const ACTIONABLE_ACTIONS = ['TAKEN', 'SKIPPED'];
const DAY_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Timezone-aware date helpers
// ---------------------------------------------------------------------------

/** Offset in ms such that (wall clock in zone) = utc + offset. */
function zoneOffsetMs(timeZone, date) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: timeZone || 'UTC', hour12: false,
    year: 'numeric', month: '2-digit', day: '2-digit',
    hour: '2-digit', minute: '2-digit', second: '2-digit',
  });
  const map = {};
  for (const p of dtf.formatToParts(date)) map[p.type] = p.value;
  let hour = parseInt(map.hour, 10);
  if (hour === 24) hour = 0;
  const asUTC = Date.UTC(
    parseInt(map.year, 10), parseInt(map.month, 10) - 1, parseInt(map.day, 10),
    hour, parseInt(map.minute, 10), parseInt(map.second, 10)
  );
  return asUTC - date.getTime();
}

/**
 * Resolve a wall-clock date/time in an IANA timezone to the corresponding UTC
 * instant. Re-evaluates the offset at the candidate instant so DST boundaries
 * resolve to the correct side.
 */
function zonedWallTimeToUtc(year, month, day, hour, minute, timeZone) {
  const guess = Date.UTC(year, month - 1, day, hour, minute, 0);
  const offset = zoneOffsetMs(timeZone, new Date(guess));
  let ts = guess - offset;
  const offset2 = zoneOffsetMs(timeZone, new Date(ts));
  if (offset2 !== offset) ts = guess - offset2;
  return new Date(ts);
}

/** Calendar {year,month,day} of an instant as observed in a timezone. */
function datePartsInZone(date, timeZone) {
  const dtf = new Intl.DateTimeFormat('en-CA', {
    timeZone: timeZone || 'UTC', year: 'numeric', month: '2-digit', day: '2-digit',
  });
  const map = {};
  for (const p of dtf.formatToParts(date)) map[p.type] = p.value;
  return { year: parseInt(map.year, 10), month: parseInt(map.month, 10), day: parseInt(map.day, 10) };
}

/** UTC calendar date of a stored Date (dates are persisted as UTC midnight). */
function utcParts(date) {
  return { year: date.getUTCFullYear(), month: date.getUTCMonth() + 1, day: date.getUTCDate() };
}

function dayNumber(parts) { return Date.UTC(parts.year, parts.month - 1, parts.day); }

/**
 * Coerce a client-supplied date string/Date into a UTC-midnight calendar date.
 * Accepts "YYYY-MM-DD" (preferred) or any parseable date.
 */
function toCalendarDate(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value)) {
    const [y, m, d] = value.split('-').map((n) => parseInt(n, 10));
    const dt = new Date(Date.UTC(y, m - 1, d));
    if (Number.isNaN(dt.getTime())) throw badRequest(`Invalid date: ${value}`);
    return dt;
  }
  const dt = new Date(value);
  if (Number.isNaN(dt.getTime())) throw badRequest(`Invalid date: ${value}`);
  return new Date(Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()));
}

/** Validate an IANA timezone id, falling back to UTC. */
function normalizeTimeZone(tz) {
  if (!tz || typeof tz !== 'string') return 'UTC';
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    return tz;
  } catch {
    return 'UTC';
  }
}

// ---------------------------------------------------------------------------
// Input validation
// ---------------------------------------------------------------------------

function normalizeTimes(times) {
  if (!Array.isArray(times) || times.length === 0) throw badRequest('At least one reminder time is required.');
  if (times.length > 8) throw badRequest('A schedule can have at most 8 reminder times per day.');
  const cleaned = [];
  for (const raw of times) {
    const t = String(raw || '').trim();
    if (!TIME_RE.test(t)) throw badRequest(`"${raw}" is not a valid time. Use 24-hour HH:mm.`);
    cleaned.push(t);
  }
  const unique = [...new Set(cleaned)];
  if (unique.length !== cleaned.length) throw badRequest('Reminder times must be unique within a schedule.');
  return unique.sort();
}

function normalizeWeekdays(days) {
  if (days == null) return null;
  if (!Array.isArray(days) || days.length === 0) return null;
  const cleaned = [...new Set(days.map((d) => parseInt(d, 10)))];
  if (cleaned.some((d) => !Number.isInteger(d) || d < 0 || d > 6)) {
    throw badRequest('Weekdays must be integers 0 (Sunday) to 6 (Saturday).');
  }
  if (cleaned.length === 7) return null; // every day === no restriction
  return cleaned.sort();
}

function validateFrequency(frequency, times) {
  const freq = FREQUENCY_COUNT[frequency] ? frequency : 'custom';
  const expected = FREQUENCY_COUNT[freq];
  if (expected && times.length !== expected) {
    throw badRequest(`Frequency "${freq}" needs exactly ${expected} reminder time(s); received ${times.length}.`);
  }
  return freq;
}

function normalizeScheduleInput(payload = {}) {
  const name = String(payload.name || '').trim();
  if (!name) throw badRequest('Medicine name is required.');
  if (name.length > 160) throw badRequest('Medicine name is too long.');

  const reminderTimes = normalizeTimes(payload.reminderTimes);
  const frequency = validateFrequency(payload.frequency, reminderTimes);
  const startDate = toCalendarDate(payload.startDate) || toCalendarDate(new Date().toISOString().slice(0, 10));
  const endDate = toCalendarDate(payload.endDate);
  if (endDate && endDate.getTime() < startDate.getTime()) {
    throw badRequest('End date must be on or after the start date.');
  }
  const weekdays = normalizeWeekdays(payload.weekdays);
  const sourceType = SOURCE_TYPES.includes(payload.sourceType) ? payload.sourceType : 'MANUAL';

  return {
    name,
    strength: payload.strength ? String(payload.strength).trim().slice(0, 80) : null,
    doseInstructions: payload.doseInstructions ? String(payload.doseInstructions).trim().slice(0, 160) : null,
    route: payload.route ? String(payload.route).trim().slice(0, 40) : null,
    frequency,
    reminderTimes,
    weekdays,
    startDate,
    endDate,
    timezone: normalizeTimeZone(payload.timezone),
    instructions: payload.instructions ? String(payload.instructions).trim().slice(0, 400) : null,
    notes: payload.notes ? String(payload.notes).trim().slice(0, 1000) : null,
    sourceType,
  };
}

// ---------------------------------------------------------------------------
// Occurrence generation + status
// ---------------------------------------------------------------------------

/**
 * Generate (idempotently) every dose occurrence for a schedule within the
 * rolling horizon. Uses a unique index on (schedule, scheduledFor) plus
 * `$setOnInsert` upserts so repeated calls never duplicate rows.
 */
async function syncOccurrences(schedule, { fromDate = null, horizonDays = null } = {}) {
  if (!schedule) return 0;
  const now = new Date();
  const tz = schedule.timezone || 'UTC';
  const horizonEnd = new Date(now.getTime() + (horizonDays || config.medication.horizonDays) * DAY_MS);
  const earliest = fromDate || new Date(now.getTime() - config.medication.trackingWindowMinutes * 60000);

  // Bound by schedule start and (if present) end.
  const startParts = utcParts(schedule.startDate);
  const fromParts = datePartsInZone(earliest, tz);
  let cursor = Math.max(dayNumber(startParts), dayNumber(fromParts));
  const endLimit = schedule.endDate
    ? Math.min(dayNumber(utcParts(schedule.endDate)), dayNumber(utcParts(horizonEnd)))
    : dayNumber(utcParts(horizonEnd));

  const weekdays = schedule.weekdays && schedule.weekdays.length ? new Set(schedule.weekdays) : null;
  const ops = [];
  for (; cursor <= endLimit; cursor += DAY_MS) {
    const d = new Date(cursor);
    const weekday = d.getUTCDay();
    if (weekdays && !weekdays.has(weekday)) continue;
    const y = d.getUTCFullYear(); const m = d.getUTCMonth() + 1; const day = d.getUTCDate();
    for (const t of schedule.reminderTimes) {
      const [hh, mm] = t.split(':').map((n) => parseInt(n, 10));
      const instant = zonedWallTimeToUtc(y, m, day, hh, mm, tz);
      if (instant.getTime() < earliest.getTime()) continue;
      if (instant.getTime() > horizonEnd.getTime()) continue;
      ops.push({
        updateOne: {
          filter: { schedule: schedule._id, scheduledFor: instant },
          update: {
            $setOnInsert: {
              schedule: schedule._id,
              patient: schedule.patient,
              scheduledFor: instant,
              status: 'UPCOMING',
            },
          },
          upsert: true,
        },
      });
    }
  }
  if (!ops.length) return 0;
  try {
    const res = await MedicationDose.bulkWrite(ops, { ordered: false });
    return res.upsertedCount || 0;
  } catch (err) {
    // Concurrent generators can race on the unique index - the duplicate simply
    // means the occurrence already exists, which is the desired outcome.
    if (err && (err.code === 11000 || (err.writeErrors && err.writeErrors.every((e) => e.err && e.err.code === 11000)))) {
      return 0;
    }
    throw err;
  }
}

/** Derive the effective status of a dose at read time. */
function effectiveStatus(recordedStatus, scheduledFor, now) {
  if (recordedStatus === 'TAKEN' || recordedStatus === 'SKIPPED') return recordedStatus;
  const t = new Date(scheduledFor).getTime();
  const nowMs = now.getTime();
  if (nowMs >= t + config.medication.trackingWindowMinutes * 60000) return 'MISSED';
  if (nowMs >= t - config.medication.dueWindowMinutes * 60000) return 'DUE';
  return 'UPCOMING';
}

/**
 * Persist MISSED for overdue unrecorded doses. Only UPCOMING/DUE rows are
 * touched, so a TAKEN or SKIPPED action is never overwritten. This runs on
 * read endpoints and is therefore server-driven, not dependent on any device.
 */
async function markMissed(patientId) {
  const cutoff = new Date(Date.now() - config.medication.trackingWindowMinutes * 60000);
  await MedicationDose.updateMany(
    { patient: patientId, status: { $in: ['UPCOMING', 'DUE'] }, scheduledFor: { $lte: cutoff } },
    { $set: { status: 'MISSED', missedAt: new Date(), actionSource: 'SYSTEM' } }
  );
}

async function syncActiveSchedules(patientId) {
  const active = await MedicationSchedule.find({ patient: patientId, status: 'ACTIVE' });
  await Promise.all(active.map((s) => syncOccurrences(s).catch((e) => {
    logger.warn('Occurrence sync failed for schedule %s: %s', s._id, e.message);
    return 0;
  })));
}

function serializeDose(dose, schedule, now = new Date()) {
  const s = schedule || dose.schedule;
  return {
    id: dose._id,
    scheduleId: dose.schedule,
    scheduleName: s ? s.name : null,
    scheduledFor: dose.scheduledFor,
    status: effectiveStatus(dose.status, dose.scheduledFor, now),
    recordedStatus: dose.status,
    actedAt: dose.actedAt || null,
    actionSource: dose.actionSource || null,
    note: dose.note || null,
    strength: s ? s.strength : null,
    doseInstructions: s ? s.doseInstructions : null,
    frequency: s ? s.frequency : null,
    sourceType: s ? s.sourceType : null,
    sourceDocument: s ? s.sourceDocument : null,
    endDate: s ? s.endDate : null,
    timezone: s ? s.timezone : null,
    scheduleStatus: s ? s.status : null,
  };
}

async function nextDoseFor(schedule) {
  const now = new Date();
  const dose = await MedicationDose.findOne({ schedule: schedule._id, scheduledFor: { $gte: now } })
    .sort({ scheduledFor: 1 }).lean();
  return dose ? dose.scheduledFor : null;
}

async function serializeSchedule(schedule, { includeNext = true } = {}) {
  const client = schedule.toClient ? schedule.toClient() : schedule;
  if (includeNext && schedule.status === 'ACTIVE') {
    client.nextDoseAt = await nextDoseFor(schedule);
  }
  return client;
}

// ---------------------------------------------------------------------------
// Schedule CRUD
// ---------------------------------------------------------------------------

async function findOwnedSchedule(patientId, id) {
  const schedule = await MedicationSchedule.findOne({ _id: id, patient: patientId });
  if (!schedule) throw notFound('Medication schedule not found.');
  return schedule;
}

async function createScheduleInternal(patientId, payload, { req = null, sourceDocument = null } = {}) {
  const input = normalizeScheduleInput(payload);

  // Idempotency key: replay a prior successful submission.
  if (payload.clientRequestId) {
    const existing = await MedicationSchedule.findOne({ patient: patientId, clientRequestId: payload.clientRequestId });
    if (existing) {
      await syncOccurrences(existing);
      return { schedule: await serializeSchedule(existing), idempotent: true, dosesCreated: 0 };
    }
  }

  // Guard against accidental duplicate submissions (same medicine + times + start day).
  const duplicate = await MedicationSchedule.findOne({
    patient: patientId,
    name: new RegExp(`^${input.name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}$`, 'i'),
    reminderTimes: input.reminderTimes,
    startDate: input.startDate,
    status: { $in: ['ACTIVE', 'PAUSED'] },
  });
  if (duplicate) {
    throw conflict('A medication schedule for this medicine with the same times and start date already exists.', [
      { path: 'name', message: 'Duplicate schedule.' },
    ]);
  }

  let schedule;
  try {
    schedule = await MedicationSchedule.create({
      ...input,
      patient: patientId,
      createdBy: patientId,
      sourceDocument,
      confirmed: input.sourceType === 'MANUAL' ? true : Boolean(payload.confirmed),
      clientRequestId: payload.clientRequestId || null,
      extraction: payload.extraction ? {
        snippet: payload.extraction.snippet ? String(payload.extraction.snippet).slice(0, 2000) : null,
        extractedAt: payload.extraction.extractedAt ? new Date(payload.extraction.extractedAt) : (sourceDocument ? new Date() : null),
        documentName: payload.extraction.documentName ? String(payload.extraction.documentName).slice(0, 250) : null,
      } : undefined,
    });
  } catch (err) {
    if (err && err.code === 11000 && payload.clientRequestId) {
      const existing = await MedicationSchedule.findOne({ patient: patientId, clientRequestId: payload.clientRequestId });
      if (existing) return { schedule: await serializeSchedule(existing), idempotent: true, dosesCreated: 0 };
    }
    throw err;
  }

  const dosesCreated = schedule.status === 'ACTIVE' ? await syncOccurrences(schedule) : 0;
  await auditService.record(req, {
    action: 'medication.schedule_created', patient: patientId,
    entityType: 'MedicationSchedule', entityId: schedule._id,
    metadata: { sourceType: schedule.sourceType, frequency: schedule.frequency },
  });
  try {
    await notificationService.notify(patientId, {
      type: 'medication',
      title: 'Medication reminder created',
      body: `${schedule.name} is now on your reminder list.`,
      refType: 'MedicationSchedule', refId: schedule._id,
    });
  } catch (e) { logger.debug('notify skipped: %s', e.message); }

  return { schedule: await serializeSchedule(schedule), idempotent: false, dosesCreated };
}

async function createSchedule(patientId, payload, { req = null } = {}) {
  return createScheduleInternal(patientId, payload, { req });
}

async function listSchedules(patientId, query = {}) {
  if (query.status && !SCHEDULE_STATUSES.includes(query.status)) {
    throw badRequest('Unknown schedule status filter.');
  }
  // Replenish the rolling occurrence window for active schedules on read.
  await syncActiveSchedules(patientId);
  await markMissed(patientId);
  const filter = { patient: patientId };
  if (query.status) filter.status = query.status;
  const schedules = await MedicationSchedule.find(filter).sort({ status: 1, name: 1, createdAt: -1 });
  const items = await Promise.all(schedules.map((s) => serializeSchedule(s)));
  return { items, total: items.length };
}

async function getSchedule(patientId, id) {
  const schedule = await findOwnedSchedule(patientId, id);
  if (schedule.status === 'ACTIVE') await syncOccurrences(schedule);
  await markMissed(patientId);
  const history = await MedicationDose.find({ schedule: schedule._id, status: { $in: ['TAKEN', 'SKIPPED', 'MISSED'] } })
    .sort({ scheduledFor: -1 }).limit(30).lean();
  const client = await serializeSchedule(schedule);
  client.recentHistory = history.map((d) => serializeDose(d, schedule));
  return client;
}

const UPDATABLE_FIELDS = ['name', 'strength', 'doseInstructions', 'route', 'frequency',
  'reminderTimes', 'weekdays', 'startDate', 'endDate', 'timezone', 'instructions', 'notes'];

async function updateSchedule(patientId, id, patch = {}, { req = null } = {}) {
  const schedule = await findOwnedSchedule(patientId, id);
  if (schedule.status === 'DISCONTINUED') {
    throw conflict('A discontinued schedule cannot be edited. Reopen it first.');
  }

  // Build the candidate values from the merged schedule.
  const merged = {
    name: patch.name !== undefined ? patch.name : schedule.name,
    strength: patch.strength !== undefined ? patch.strength : schedule.strength,
    doseInstructions: patch.doseInstructions !== undefined ? patch.doseInstructions : schedule.doseInstructions,
    route: patch.route !== undefined ? patch.route : schedule.route,
    frequency: patch.frequency !== undefined ? patch.frequency : schedule.frequency,
    reminderTimes: patch.reminderTimes !== undefined ? patch.reminderTimes : schedule.reminderTimes,
    weekdays: patch.weekdays !== undefined ? patch.weekdays : schedule.weekdays,
    startDate: patch.startDate !== undefined ? patch.startDate : schedule.startDate,
    endDate: patch.endDate !== undefined ? patch.endDate : schedule.endDate,
    timezone: patch.timezone !== undefined ? patch.timezone : schedule.timezone,
    instructions: patch.instructions !== undefined ? patch.instructions : schedule.instructions,
    notes: patch.notes !== undefined ? patch.notes : schedule.notes,
  };

  const before = JSON.stringify({
    times: schedule.reminderTimes, weekdays: schedule.weekdays,
    start: schedule.startDate, end: schedule.endDate,
  });

  const input = normalizeScheduleInput(merged);
  for (const key of UPDATABLE_FIELDS) {
    if (key in input) schedule[key] = input[key];
  }
  await schedule.save();

  const after = JSON.stringify({
    times: schedule.reminderTimes, weekdays: schedule.weekdays,
    start: schedule.startDate, end: schedule.endDate,
  });
  const scheduleChanged = before !== after;

  if (scheduleChanged && schedule.status === 'ACTIVE') {
    // Only future, not-yet-recorded occurrences are regenerated. Past actions
    // and history are preserved.
    await MedicationDose.deleteMany({
      schedule: schedule._id, status: 'UPCOMING', scheduledFor: { $gte: new Date() },
    });
    await syncOccurrences(schedule, { fromDate: new Date() });
  }

  await auditService.record(req, {
    action: 'medication.schedule_updated', patient: patientId,
    entityType: 'MedicationSchedule', entityId: schedule._id,
    metadata: { scheduleChanged, fields: Object.keys(patch) },
  });

  return { schedule: await serializeSchedule(schedule), scheduleChanged };
}

async function setStatus(patientId, id, action, { req = null, confirmReopen = false } = {}) {
  const schedule = await findOwnedSchedule(patientId, id);
  const now = new Date();

  if (action === 'pause') {
    if (schedule.status === 'PAUSED') return { schedule: await serializeSchedule(schedule, { includeNext: false }) };
    if (schedule.status !== 'ACTIVE') throw conflict('Only an active schedule can be paused.');
    schedule.status = 'PAUSED';
    await schedule.save();
    await MedicationDose.deleteMany({ schedule: schedule._id, status: 'UPCOMING', scheduledFor: { $gte: now } });
  } else if (action === 'resume') {
    if (schedule.status === 'ACTIVE') return { schedule: await serializeSchedule(schedule) };
    if (['COMPLETED', 'DISCONTINUED'].includes(schedule.status) && !confirmReopen) {
      throw conflict('This medication is completed or discontinued. Confirm reopening to restart reminders.');
    }
    schedule.status = 'ACTIVE';
    await schedule.save();
    await syncOccurrences(schedule, { fromDate: now });
  } else if (action === 'discontinue') {
    if (schedule.status === 'DISCONTINUED') return { schedule: await serializeSchedule(schedule, { includeNext: false }) };
    schedule.status = 'DISCONTINUED';
    await schedule.save();
    await MedicationDose.deleteMany({ schedule: schedule._id, status: 'UPCOMING', scheduledFor: { $gte: now } });
  } else {
    throw badRequest('Unknown schedule action.');
  }

  await auditService.record(req, {
    action: `medication.schedule_${action}`, patient: patientId,
    entityType: 'MedicationSchedule', entityId: schedule._id,
  });
  return { schedule: await serializeSchedule(schedule, { includeNext: schedule.status === 'ACTIVE' }) };
}

// ---------------------------------------------------------------------------
// Doses
// ---------------------------------------------------------------------------

async function dosesInRange(patientId, { from, to, tz } = {}) {
  await markMissed(patientId);
  const timeZone = normalizeTimeZone(tz);
  const now = new Date();
  const todayParts = datePartsInZone(now, timeZone);
  const defaultFrom = zonedWallTimeToUtc(todayParts.year, todayParts.month, todayParts.day, 0, 0, timeZone);
  const defaultTo = new Date(zonedWallTimeToUtc(todayParts.year, todayParts.month, todayParts.day, 0, 0, timeZone).getTime() + DAY_MS);

  const fromDate = from ? new Date(from) : defaultFrom;
  const toDate = to ? new Date(to) : defaultTo;
  if (Number.isNaN(fromDate.getTime()) || Number.isNaN(toDate.getTime())) throw badRequest('Invalid date range.');

  const doses = await MedicationDose.find({ patient: patientId, scheduledFor: { $gte: fromDate, $lt: toDate } })
    .populate('schedule')
    .sort({ scheduledFor: 1 }).limit(500);
  return doses.map((d) => serializeDose(d, d.schedule, now));
}

async function todayDoses(patientId, { tz } = {}) {
  const timeZone = normalizeTimeZone(tz);
  const parts = datePartsInZone(new Date(), timeZone);
  const from = zonedWallTimeToUtc(parts.year, parts.month, parts.day, 0, 0, timeZone);
  const to = new Date(from.getTime() + DAY_MS);
  const items = await dosesInRange(patientId, { from: from.toISOString(), to: to.toISOString(), tz: timeZone });
  return { items, timezone: timeZone, serverTime: new Date() };
}

async function upcomingDoses(patientId, { limit = 20 } = {}) {
  await markMissed(patientId);
  const now = new Date();
  const doses = await MedicationDose.find({
    patient: patientId,
    scheduledFor: { $gte: now },
    status: { $in: ['UPCOMING', 'DUE'] },
  }).populate('schedule').sort({ scheduledFor: 1 }).limit(Math.min(Math.max(limit, 1), 100));

  const items = doses
    .filter((d) => d.schedule && d.schedule.status === 'ACTIVE')
    .map((d) => serializeDose(d, d.schedule, now));

  // De-duplicate defensively on (scheduleId, scheduledFor) so a dose never
  // appears twice even if legacy data slipped through.
  const seen = new Set();
  const deduped = [];
  for (const d of items) {
    const key = `${d.scheduleId}|${new Date(d.scheduledFor).toISOString()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    deduped.push(d);
  }
  return { items: deduped, total: deduped.length };
}

async function recordDoseAction(patientId, doseId, action, { note = null, req = null } = {}) {
  if (!ACTIONABLE_ACTIONS.includes(action)) {
    throw badRequest('A dose action must be either TAKEN or SKIPPED.');
  }
  const dose = await MedicationDose.findOne({ _id: doseId, patient: patientId }).populate('schedule');
  if (!dose) throw notFound('Dose not found.');

  if (dose.status === action) {
    return { dose: serializeDose(dose, dose.schedule), idempotent: true };
  }
  if (ACTIONABLE_ACTIONS.includes(dose.status) && dose.status !== action) {
    throw conflict(`This dose was already recorded as ${dose.status}. It cannot be changed to ${action}.`);
  }

  dose.status = action;
  dose.actedAt = new Date();
  dose.actionSource = 'PATIENT';
  dose.note = note ? String(note).trim().slice(0, 300) : null;
  dose.missedAt = null;
  await dose.save();

  await auditService.record(req, {
    action: `medication.dose_${action.toLowerCase()}`, patient: patientId,
    entityType: 'MedicationDose', entityId: dose._id,
    metadata: { scheduleId: String(dose.schedule && dose.schedule._id ? dose.schedule._id : dose.schedule) },
  });

  return { dose: serializeDose(dose, dose.schedule), idempotent: false };
}

async function getHistory(patientId, query = {}) {
  await markMissed(patientId);
  const { page, limit, skip } = parsePagination(query, { defaultLimit: 50, maxLimit: 200 });
  const filter = { patient: patientId, status: { $in: ['TAKEN', 'SKIPPED', 'MISSED'] } };
  const from = query.from ? new Date(query.from) : null;
  const to = query.to ? new Date(query.to) : null;
  if ((from && Number.isNaN(from.getTime())) || (to && Number.isNaN(to.getTime()))) throw badRequest('Invalid date range.');
  if (from || to) filter.scheduledFor = { ...(from ? { $gte: from } : {}), ...(to ? { $lt: to } : {}) };

  const [items, total] = await Promise.all([
    MedicationDose.find(filter).populate('schedule').sort({ scheduledFor: -1 }).skip(skip).limit(limit),
    MedicationDose.countDocuments(filter),
  ]);
  const now = new Date();
  return {
    items: items.map((d) => serializeDose(d, d.schedule, now)),
    total,
    page,
    limit,
    disclaimer: 'A "Missed" entry means no Taken or Skipped action was recorded in this app within the tracking window. '
      + 'It is not proof that the medicine was not taken.',
  };
}

// ---------------------------------------------------------------------------
// Prescription extraction (review-then-confirm)
// ---------------------------------------------------------------------------

function snippetForMedication(text, name) {
  if (!text || !name) return null;
  const needle = name.toLowerCase();
  const line = String(text).split(/\r?\n/).find((l) => l.toLowerCase().includes(needle));
  return line ? line.replace(/\s+/g, ' ').trim().slice(0, 240) : null;
}

async function readDocumentText(doc) {
  if (doc.extractionStatus === 'extracted' || doc.rawText) {
    const withText = await Document.findById(doc._id).select('+rawText');
    if (withText && withText.rawText && withText.rawText.trim().length >= 3) {
      return { text: withText.rawText, source: withText.textSource || 'pdf-text', ocrConfidence: null };
    }
  }
  try {
    const storage = getStorage();
    const buffer = await storage.read(doc.storageKey);
    const recovered = await extractionService.recoverText(buffer, doc.mimeType);
    return { text: recovered.text || '', source: recovered.source, ocrConfidence: recovered.ocrConfidence, warnings: recovered.warnings };
  } catch (e) {
    logger.warn('Prescription text recovery failed: %s', e.message);
    return { text: '', source: 'none', ocrConfidence: null, warnings: ['Could not read the stored file.'] };
  }
}

async function extractFromDocument(patientId, documentId, { req = null } = {}) {
  if (!documentId) throw badRequest('A prescription document id is required.');
  const doc = await Document.findOne({ _id: documentId, patient: patientId, deletedAt: null });
  if (!doc) throw notFound('Prescription not found or not accessible.');

  const recovered = await readDocumentText(doc);
  const text = (recovered.text || '').trim();
  if (text.length < 3) {
    throw unprocessable('We could not read any text from this prescription. You can add the medicine manually.', [
      { path: 'documentId', message: 'Document text could not be recovered.' },
    ]);
  }

  let structured;
  try {
    structured = extractStructured(text);
  } catch (e) {
    throw unprocessable('Prescription extraction failed. You can add the medicine manually.');
  }

  const meds = structured.medications || [];
  if (!meds.length) {
    throw unprocessable('No medication information was detected in this prescription. You can add the medicine manually.', [
      { path: 'documentId', message: 'No medications detected.' },
    ]);
  }

  const candidates = meds.map((m) => {
    const uncertainFields = ['strength', 'dose', 'frequency', 'route'].filter((f) => !m[f]);
    return {
      name: m.name,
      strength: m.strength || null,
      dose: m.dose || null,
      frequency: m.frequency || null,
      route: m.route || null,
      form: m.form || null,
      instructions: null,
      uncertainFields,
      confidence: 0.6,
      sourceSnippet: snippetForMedication(text, m.name),
    };
  });

  await auditService.record(req, {
    action: 'medication.extraction_previewed', patient: patientId,
    entityType: 'Document', entityId: doc._id,
    metadata: { candidates: candidates.length },
  });

  return {
    document: {
      id: doc._id,
      originalName: doc.originalName,
      category: doc.category,
      eventDate: doc.eventDate || null,
      extractionStatus: doc.extractionStatus,
    },
    extractedAt: new Date(),
    textSource: recovered.source,
    ocrConfidence: recovered.ocrConfidence || null,
    prescriptionDate: structured.eventDate || null,
    prescriber: structured.providerName || doc.providerName || null,
    reviewNotes: structured.reviewNotes || [],
    candidates,
    rawTextExcerpt: text.slice(0, 2000),
    note: 'Extraction is a suggestion only. Review every field and confirm the dose and reminder times before saving. '
      + 'No schedule is created until you confirm.',
  };
}

async function confirmExtraction(patientId, payload = {}, { req = null } = {}) {
  if (!payload.documentId) throw badRequest('A source prescription document id is required.');
  const doc = await Document.findOne({ _id: payload.documentId, patient: patientId, deletedAt: null });
  if (!doc) throw notFound('Prescription not found or not accessible.');
  if (payload.confirmed !== true) {
    throw badRequest('You must explicitly confirm the extracted dose and schedule before saving.');
  }

  const medication = payload.medication || {};
  const result = await createScheduleInternal(
    patientId,
    {
      ...medication,
      sourceType: 'PRESCRIPTION',
      confirmed: true,
      clientRequestId: payload.clientRequestId,
      extraction: {
        snippet: payload.snippet || null,
        extractedAt: new Date(),
        documentName: doc.originalName,
      },
    },
    { req, sourceDocument: doc._id }
  );

  await auditService.record(req, {
    action: 'medication.confirmed_from_prescription', patient: patientId,
    entityType: 'MedicationSchedule', entityId: result.schedule.id,
    metadata: { documentId: String(doc._id) },
  });
  return result;
}

module.exports = {
  // validation / helpers (exported for tests)
  normalizeScheduleInput,
  normalizeTimes,
  normalizeWeekdays,
  validateFrequency,
  zonedWallTimeToUtc,
  datePartsInZone,
  effectiveStatus,
  // operations
  createSchedule,
  listSchedules,
  getSchedule,
  updateSchedule,
  setStatus,
  dosesInRange,
  todayDoses,
  upcomingDoses,
  recordDoseAction,
  getHistory,
  extractFromDocument,
  confirmExtraction,
  syncOccurrences,
  markMissed,
};
