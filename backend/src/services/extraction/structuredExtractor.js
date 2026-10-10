'use strict';

/**
 * Deterministic structured extractor.
 *
 * Given raw document text (from a PDF text layer or OCR) this module produces a
 * structured, schema-validated medical record using explicit rules. It NEVER
 * invents missing values: absent fields stay null and are marked for review.
 *
 * A cloud AI provider may be layered on top for phrasing, but its output is
 * validated against the same schema and this extractor remains the fallback so
 * extraction always works offline.
 */

const MONTHS = {
  jan: 0, feb: 1, mar: 2, apr: 3, may: 4, jun: 5, jul: 6, aug: 7, sep: 8, sept: 8,
  oct: 9, nov: 10, dec: 11,
};

const UNITS = [
  'mg/dl', 'g/dl', 'mg/l', 'g/l', 'mmol/l', 'umol/l', 'µmol/l', 'iu/l', 'u/l',
  'miu/l', 'miu/ml', 'ng/ml', 'pg/ml', 'ng/dl', 'pg/dl', 'mmol/mol', 'meq/l',
  'mmol', 'mg', 'g', 'kg', 'lb', 'mcg', 'ng', 'pg', '%', 'cells/µl', 'cells/ul',
  'x10^3/µl', 'x10^3/ul', '10^3/µl', 'lakh/µl', 'million/µl', 'fl', 'pg', 'iu/ml',
  'mm/hr', 'mm/hr', 'seconds', 's', 'ratio', 'ml/min', 'bpm', 'mmhg', 'f', 'c',
];

const UNIT_RE = new RegExp(
  `^(${UNITS.map((u) => u.replace(/[/^]/g, (c) => `\\${c}`)).join('|')})$`,
  'i'
);

const UNIT_PATTERN = UNITS.map((u) => u.replace(/[/^]/g, (c) => `\\${c}`)).join('|');
const NUM = '[-+]?\\d+(?:[.,]\\d+)?';

function cleanLine(line) {
  return line.replace(/\s+/g, ' ').trim();
}

/** Parse a date from a short token; returns { date, estimated } or null. */
function parseDateToken(token) {
  if (!token) return null;
  const t = token.trim();

  // ISO yyyy-mm-dd
  let m = t.match(/^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$/);
  if (m) {
    const d = new Date(Date.UTC(+m[1], +m[2] - 1, +m[3]));
    if (!Number.isNaN(d.getTime())) return { date: d, estimated: false };
  }
  // dd/mm/yyyy or mm/dd/yyyy (ambiguous - assume day-first if first > 12)
  m = t.match(/^(\d{1,2})[-/.](\d{1,2})[-/.](\d{2,4})$/);
  if (m) {
    let a = +m[1]; let b = +m[2]; let y = +m[3];
    if (y < 100) y += 2000;
    let day; let month;
    if (a > 12 && b <= 12) { day = a; month = b; } else { day = a; month = b; }
    const d = new Date(Date.UTC(y, month - 1, day));
    if (!Number.isNaN(d.getTime())) return { date: d, estimated: true };
  }
  // 12-Mar-2024 or 12 March 2024
  m = t.match(/^(\d{1,2})[\s-]*([A-Za-z]{3,9})[\s-,]*(\d{2,4})$/);
  if (m) {
    const mon = MONTHS[m[2].slice(0, 4).toLowerCase()] ?? MONTHS[m[2].slice(0, 3).toLowerCase()];
    if (mon !== undefined) {
      let y = +m[3]; if (y < 100) y += 2000;
      const d = new Date(Date.UTC(y, mon, +m[1]));
      if (!Number.isNaN(d.getTime())) return { date: d, estimated: false };
    }
  }
  // March 12, 2024
  m = t.match(/^([A-Za-z]{3,9})[\s]+(\d{1,2})[\s,]+(\d{2,4})$/);
  if (m) {
    const mon = MONTHS[m[1].slice(0, 4).toLowerCase()] ?? MONTHS[m[1].slice(0, 3).toLowerCase()];
    if (mon !== undefined) {
      let y = +m[3]; if (y < 100) y += 2000;
      const d = new Date(Date.UTC(y, mon, +m[2]));
      if (!Number.isNaN(d.getTime())) return { date: d, estimated: false };
    }
  }
  return null;
}

/** Find the most likely document/event date in the text. */
function findDate(lines) {
  const labeled = /(date|dated|collected|reported|exam(?:ination)? date|visit date|encounter)\s*[:#]?\s*([0-9A-Za-z ,./-]{6,20})/i;
  for (const line of lines) {
    const m = line.match(labeled);
    if (m) {
      const p = parseDateToken(m[2].trim());
      if (p) return p;
    }
  }
  // fall back to first plausible date anywhere
  for (const line of lines) {
    const tokens = line.match(/\b(?:\d{4}[-/.]\d{1,2}[-/.]\d{1,2}|\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}|\d{1,2}[\s-]*[A-Za-z]{3,9}[\s-]*,?[\s-]*\d{2,4})\b/g);
    if (tokens) {
      for (const tk of tokens) {
        const p = parseDateToken(tk);
        if (p) return p;
      }
    }
  }
  return null;
}

const CATEGORY_RULES = [
  { category: 'prescription', re: /\b(prescription|rx|℞|dispense|medicine|drug chart|prescribed)\b/i },
  { category: 'laboratory', re: /\b(laboratory|lab report|haematology|hematology|biochemistry|serology|pathology|specimen|reference range|test report)\b/i },
  { category: 'imaging', re: /\b(x-?ray|mri|ct scan|ultrasound|sonograph|radiolog|impression:.*scan|imaging)\b/i },
  { category: 'discharge_summary', re: /\b(discharge summary|discharged on|date of discharge|admission|in-?patient)\b/i },
  { category: 'consultation_note', re: /\b(consultation|out-?patient|opd|chief complaint|history of present|physical examination|advice)\b/i },
  { category: 'vaccination', re: /\b(vaccin|immuniz|immunis|dose\s*\d+.*(?:hepatitis|tetanus|influenza|covid))\b/i },
];

function detectCategory(text) {
  for (const rule of CATEGORY_RULES) if (rule.re.test(text)) return rule.category;
  return 'other';
}

const PROVIDER_HINT = /^(?:[A-Z][A-Za-z&.']+\s+){0,6}(?:Clinic|Hospital|Laborator(?:y|ies)|Diagnostics?|Medical Cent(?:er|re)|Pharmacy|Health Cent(?:er|re)|Institute|Polyclinic|Nursing Home)\b/;

function detectProvider(lines) {
  const explicit = lines.find((l) => /(provider|facility|hospital|clinic|laboratory|lab|pharmacy)\s*[:\-]/i.test(l) && l.length < 90);
  if (explicit) {
    const val = explicit.split(/[:\-]/).slice(1).join(':').trim();
    if (val && val.length > 2) return val.replace(/[.\s]+$/, '');
  }
  for (const line of lines.slice(0, 12)) {
    if (PROVIDER_HINT.test(line) && line.length < 80) return cleanLine(line).replace(/[.\s]+$/, '');
  }
  return null;
}

function splitSections(text) {
  const lines = text.split(/\r?\n/).map(cleanLine).filter(Boolean);
  const sections = { medications: [], observations: [], allergies: [], diagnoses: [], notes: [] };
  let current = 'notes';
  const headingMap = [
    [/^(?:medications?|drugs?|rx|prescription|current medications?|medicines?)\b[:\-]?/i, 'medications'],
    [/^(?:laboratory|lab results?|test results?|investigations?|observations?|results?|biochemistry|haematology|hematology|complete blood count|cbc)\b[:\-]?/i, 'observations'],
    [/^(?:allerg(?:y|ies))\b[:\-]?/i, 'allergies'],
    [/^(?:diagnos(?:is|es)|impression|assessment|problem list)\b[:\-]?/i, 'diagnoses'],
    [/^(?:advice|recommendations?|follow[- ]?up|plan|notes?|findings?|history|complaints?|examination)\b[:\-]?/i, 'notes'],
  ];
  for (const line of lines) {
    let matched = false;
    for (const [re, key] of headingMap) {
      if (re.test(line)) {
        current = key;
        const rest = line.replace(re, '').replace(/^[:\-\s]+/, '').trim();
        if (rest) sections[key].push(rest);
        matched = true;
        break;
      }
    }
    if (!matched) sections[current].push(line);
  }
  return sections;
}

const MED_FREQ = /\b(once daily|twice daily|thrice daily|once a day|twice a day|at bedtime|hs|bd|b\.?i\.?d|tds|t\.?d\.?s|od|o\.?d|qid|q\.?i\.?d|qds|sos|prn|stat|weekly|every\s+\d+\s+hours?|\d+\s*[-x×]\s*\d+|1-0-1|0-0-1|1-0-0|morning|night)\b/i;
const MED_ROUTE = /\b(oral|orally|p\.?o\.?|by mouth|topical|iv|i\.?v\.?|im|i\.?m\.?|sc|s\.?c\.?|subcut(?:aneous)?|inhalation|inhaler|nasal|ophthalmic|otic|rectal)\b/i;
const MED_STRENGTH = new RegExp(`(${NUM})\\s*(mg|mcg|µg|g|ml|iu|units?|%)\\b`, 'i');

function parseMedicationLine(line) {
  const stripped = line
    .replace(/^\s*\d+[.)]\s*/, '')
    .replace(/^(?:tab(?:let)?|cap(?:sule)?|syp|syr(?:up)?|inj(?:ection)?|susp(?:ension)?|oint(?:ment)?|drops?|cr(?:eam)?|inhaler|spray)\.?\s+/i, '');
  const nameMatch = stripped.match(/^([A-Za-z][A-Za-z0-9\-/ ]{1,60}?)(?=\s*(?:\d|$|[-–(]))/);
  if (!nameMatch) return null;
  const name = nameMatch[1].trim().replace(/[.,;]+$/, '');
  if (name.length < 3) return null;
  if (/^(?:date|patient|name|age|sex|dr|doctor|hospital|clinic|laboratory|address|phone|ref|result)/i.test(name)) return null;

  const strengthM = stripped.match(MED_STRENGTH);
  const freqM = stripped.match(MED_FREQ);
  const routeM = stripped.match(MED_ROUTE);
  const formM = stripped.match(/^(tab(?:let)?|cap(?:sule)?|syp|syr(?:up)?|inj(?:ection)?|susp(?:ension)?|oint(?:ment)?|drops?|cr(?:eam)?|inhaler|spray)/i);

  return {
    name,
    strength: strengthM ? `${strengthM[1].replace(',', '.')} ${strengthM[2].toLowerCase()}` : null,
    frequency: freqM ? freqM[1].trim() : null,
    route: routeM ? routeM[1].trim() : null,
    form: formM ? formM[1].toLowerCase() : null,
    dose: null,
  };
}

function parseObservationLine(line) {
  // Normalize separators so "Glucose: 142 mg/dL" and "Glucose 142 mg/dL" both work.
  const normalized = line.replace(/[|]/g, ' ').replace(/\s*[:=]\s*/g, ' ');
  const upperValue = `(${NUM})\\s*(${UNIT_PATTERN})?`;
  const re = new RegExp(`^([A-Za-z][A-Za-z0-9 ()\\-/]{1,60}?)\\s+${upperValue}(?:\\s*\\(?\\s*(${NUM})\\s*(?:-|–|to)\\s*(${NUM})\\s*\\)?)?\\s*([HL]|high|low|abnormal|normal)?\\s*$`, 'i');
  const m = normalized.match(re);
  if (!m) return null;
  const testName = m[1].trim().replace(/[.,;:]+$/, '');
  if (testName.length < 2) return null;
  // Reject metadata/header lines ("Date 15 Jan", "Specimen: Fasting blood",
  // "Admission Date 08 May") that the value regex would otherwise swallow as
  // bogus lab results.
  if (/^(date|specimen|sample|patient|name|age|sex|gender|doctor|physician|dr\.?|address|phone|ref\.?|provider|accession|collected|received|reported|requested|admission|discharge|reason|chief complaint|diagnos|allerg)/i.test(testName)) return null;
  const value = parseFloat(m[2].replace(',', '.'));
  let unit = m[3] || null;
  if (unit && !UNIT_RE.test(unit)) unit = unit.toLowerCase();
  const refLow = m[4] != null ? parseFloat(m[4].replace(',', '.')) : null;
  const refHigh = m[5] != null ? parseFloat(m[5].replace(',', '.')) : null;
  const flag = m[6] ? m[6].toLowerCase() : null;
  let abnormal = null;
  if (flag) abnormal = /^(h|high|abnormal)$/.test(flag) ? true : (/^(l|low)$/.test(flag) ? true : (/^normal$/.test(flag) ? false : null));
  if (abnormal === null && refLow != null && refHigh != null) abnormal = value < refLow || value > refHigh;
  return {
    testName,
    value: Number.isFinite(value) ? value : null,
    unit,
    // Keep the source spelling ("4.0 - 5.6") rather than re-rendering floats
    // ("4 - 5.6") so precision and validity are preserved.
    referenceRange: refLow != null && refHigh != null ? `${m[4].replace(',', '.')} - ${m[5].replace(',', '.')}${unit ? ` ${unit}` : ''}` : null,
    abnormal,
  };
}

function parseAllergyLine(line) {
  const cleaned = line.replace(/^(?:allerg(?:y|ies)|known allergy)\s*[:\-]?\s*/i, '').trim();
  if (!cleaned) return null;
  // "Penicillin - rash", "Penicillin (rash)", "Penicillin: urticaria, severe"
  const m = cleaned.match(/^([A-Za-z][A-Za-z0-9 /-]{1,40}?)\s*(?:[:(]|\s-\s|\s–\s)\s*([^)]+?)\)?\s*$/);
  let substance = m ? m[1].trim() : cleaned.split(/[,;]/)[0].trim();
  let rest = m ? m[2].trim() : cleaned.slice(substance.length).replace(/^[,;:\s-]+/, '').trim();
  if (!substance || substance.length < 2 || substance.length > 40) return null;
  let severity = 'unknown';
  if (/\b(anaphyla|severe|life-?threat|swelling of throat|angioedema)\b/i.test(cleaned)) severity = 'severe';
  else if (/\b(moderate|hives|urticaria|swelling|vomiting)\b/i.test(cleaned)) severity = 'moderate';
  else if (/\b(mild|rash|itching|itchy|nausea|sneez)\b/i.test(cleaned)) severity = 'mild';
  return { substance, reaction: rest || null, severity };
}

function parseDiagnosisLine(line) {
  const cleaned = line.replace(/^(?:\d+[.)]\s*)?(?:diagnos(?:is|es)|impression|problem)\s*[:\-]?\s*/i, '').trim();
  const first = cleaned.split(/[;.]/)[0].trim();
  if (!first || first.length < 3 || first.length > 120) return null;
  if (/^(?:none|nil|no significant|normal|n\/a)$/i.test(first)) return null;
  return { name: first };
}

/**
 * @param {string} text raw document text
 * @returns {object} structured extraction result (schema-shaped)
 */
function extractStructured(text) {
  const safeText = String(text || '');
  const lines = safeText.split(/\r?\n/).map(cleanLine).filter(Boolean);
  const sections = splitSections(safeText);
  const dateInfo = findDate(lines);
  const category = detectCategory(safeText);
  const provider = detectProvider(lines);

  const observations = [];
  const seenObs = new Set();
  for (const line of sections.observations) {
    const obs = parseObservationLine(line);
    if (obs && !seenObs.has(obs.testName.toLowerCase())) {
      seenObs.add(obs.testName.toLowerCase());
      observations.push(obs);
    }
  }
  // Some reports have no explicit "results" heading; scan remaining lines too.
  if (observations.length === 0) {
    for (const line of lines) {
      const obs = parseObservationLine(line);
      if (obs && !seenObs.has(obs.testName.toLowerCase())) {
        seenObs.add(obs.testName.toLowerCase());
        observations.push(obs);
      }
    }
  }

  const medications = [];
  const seenMed = new Set();
  for (const line of sections.medications) {
    const med = parseMedicationLine(line);
    if (med && !seenMed.has(med.name.toLowerCase())) {
      seenMed.add(med.name.toLowerCase());
      medications.push(med);
    }
  }

  const allergies = [];
  for (const line of sections.allergies) {
    const a = parseAllergyLine(line);
    if (a) allergies.push(a);
  }

  const conditions = [];
  for (const line of sections.diagnoses) {
    const c = parseDiagnosisLine(line);
    if (c) conditions.push(c);
  }

  const followUp = [];
  for (const line of sections.notes) {
    if (/(follow[- ]?up|review after|repeat (?:test|scan)|next visit|come back|advice|recommend)/i.test(line) && line.length < 200) {
      followUp.push(line);
    }
  }

  return {
    documentType: category,
    providerName: provider,
    eventDate: dateInfo ? dateInfo.date.toISOString() : null,
    eventDateEstimated: dateInfo ? dateInfo.estimated : null,
    observations,
    medications,
    allergies,
    conditions,
    followUp: followUp.slice(0, 10),
    reviewNotes: [
      dateInfo ? null : 'No date could be determined from the document - please confirm the event date.',
      observations.length ? null : 'No laboratory values were detected - review the document manually.',
    ].filter(Boolean),
    textLength: safeText.length,
  };
}

module.exports = { extractStructured, parseDateToken, detectCategory, parseObservationLine, parseMedicationLine };
