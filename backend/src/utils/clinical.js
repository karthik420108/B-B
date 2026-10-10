'use strict';

/**
 * Normalizes drug / test names so that the same substance described by
 * different providers is compared consistently.
 *
 * This is deliberately conservative: it lower-cases, strips dosage-form and
 * marketing noise, and applies a small synonym map. It never guesses a
 * generic name for an unknown brand - that would be unsafe.
 */

const DOSAGE_FORMS = [
  'tablet', 'tab', 'capsule', 'cap', 'syrup', 'suspension', 'injection', 'inj',
  'solution', 'drops', 'cream', 'ointment', 'gel', 'spray', 'inhaler', 'patch',
  'suppository', 'sachet', 'powder', 'er', 'xr', 'sr', 'cr', 'mr', 'forte',
];

const SALT_SUFFIXES = [
  'hydrochloride', 'hcl', 'sodium', 'potassium', 'calcium', 'magnesium',
  'sulfate', 'sulphate', 'tartrate', 'maleate', 'citrate', 'succinate',
  'fumarate', 'mesylate', 'besylate', 'dihydrate', 'monohydrate', 'bitartrate',
];

/** ingredient-level synonyms (brand or alternate spelling -> canonical generic). */
const DRUG_SYNONYMS = {
  'acetylsalicylic acid': 'aspirin',
  'asa': 'aspirin',
  'ecotrin': 'aspirin',
  'disprin': 'aspirin',
  'crocin': 'paracetamol',
  'tylenol': 'paracetamol',
  'acetaminophen': 'paracetamol',
  'calpol': 'paracetamol',
  'coumadin': 'warfarin',
  'glucophage': 'metformin',
  'zocor': 'simvastatin',
  'lipitor': 'atorvastatin',
  'norvasc': 'amlodipine',
  'lopressor': 'metoprolol',
  'zestril': 'lisinopril',
  'prinivil': 'lisinopril',
  'lasix': 'furosemide',
  'flagyl': 'metronidazole',
  'ventolin': 'salbutamol',
  'albuterol': 'salbutamol',
  'eliquis': 'apixaban',
  'xarelto': 'rivaroxaban',
  'plavix': 'clopidogrel',
  'advil': 'ibuprofen',
  'motrin': 'ibuprofen',
  'brufen': 'ibuprofen',
  'voltaren': 'diclofenac',
  'lipvas': 'atorvastatin',
  'glycomet': 'metformin',
  'thyronorm': 'levothyroxine',
  'synthroid': 'levothyroxine',
  'eltroxin': 'levothyroxine',
  'omez': 'omeprazole',
  'prilosec': 'omeprazole',
  'pantop': 'pantoprazole',
  'amoxil': 'amoxicillin',
  'augmentin': 'amoxicillin clavulanate',
  'zithromax': 'azithromycin',
  'azee': 'azithromycin',
  'cipro': 'ciprofloxacin',
  'monocef': 'ceftriaxone',
  'combiflam': 'ibuprofen paracetamol',
};

function stripDosage(text) {
  let out = ` ${text} `;
  for (const form of DOSAGE_FORMS) {
    out = out.replace(new RegExp(`\\b${form}\\b`, 'gi'), ' ');
  }
  return out;
}

function stripSalts(text) {
  let out = ` ${text} `;
  for (const salt of SALT_SUFFIXES) {
    out = out.replace(new RegExp(`\\b${salt}\\b`, 'gi'), ' ');
  }
  return out;
}

/**
 * @param {string} name raw medication name
 * @returns {string} canonical comparison key
 */
function normalizeDrugName(name) {
  if (!name) return '';
  let s = String(name).toLowerCase();
  s = s.replace(/\([^)]*\)/g, ' '); // remove parenthetical notes
  s = s.replace(/[0-9]+([.,][0-9]+)?\s*(mg|mcg|g|ml|iu|%)/gi, ' '); // strengths
  s = stripDosage(s);
  s = s.replace(/[^a-z\s-]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  if (DRUG_SYNONYMS[s]) return DRUG_SYNONYMS[s];
  const salted = stripSalts(s).replace(/\s+/g, ' ').trim();
  if (DRUG_SYNONYMS[salted]) return DRUG_SYNONYMS[salted];
  return salted || s;
}

/** Extract a strength string like "500 mg" if present. */
function extractStrength(name) {
  if (!name) return null;
  const m = String(name).match(/([0-9]+(?:[.,][0-9]+)?)\s*(mg|mcg|g|ml|iu|%)\b/i);
  return m ? `${m[1].replace(',', '.')} ${m[2].toLowerCase()}` : null;
}

/** Extract a numeric potency for strength comparison. */
function strengthValue(strength) {
  if (!strength) return null;
  const m = String(strength).match(/([0-9]+(?:[.,][0-9]+)?)\s*(mg|mcg|g|ml|iu|%)/i);
  if (!m) return null;
  let value = parseFloat(m[1].replace(',', '.'));
  const unit = m[2].toLowerCase();
  const toMg = { mg: 1, mcg: 0.001, g: 1000, ml: 1, iu: 1, '%': 1 };
  return { value: value * (toMg[unit] || 1), unit };
}

/** Detect the dosage form keyword, if present. */
function dosageForm(name) {
  if (!name) return null;
  const lower = String(name).toLowerCase();
  for (const form of DOSAGE_FORMS) {
    if (new RegExp(`\\b${form}\\b`).test(lower)) return form;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Test / observation name normalization
// ---------------------------------------------------------------------------

const TEST_SYNONYMS = {
  'fasting blood sugar': 'glucose fasting',
  'fasting glucose': 'glucose fasting',
  'fbs': 'glucose fasting',
  'fbg': 'glucose fasting',
  'fasting plasma glucose': 'glucose fasting',
  'random blood sugar': 'glucose random',
  'rbs': 'glucose random',
  'post prandial glucose': 'glucose postprandial',
  'ppbs': 'glucose postprandial',
  'ppg': 'glucose postprandial',
  'blood glucose': 'glucose',
  'sugar': 'glucose',
  'glycated hemoglobin': 'hba1c',
  'glycosylated hemoglobin': 'hba1c',
  'hb a1c': 'hba1c',
  'a1c': 'hba1c',
  'haemoglobin': 'hemoglobin',
  'hb': 'hemoglobin',
  'total cholesterol': 'cholesterol total',
  'cholesterol': 'cholesterol total',
  'thyroid stimulating hormone': 'tsh',
  'free t4': 'ft4',
  'free t3': 'ft3',
  't4': 'ft4',
  't3': 'ft3',
  'sgpt': 'alt',
  'serum glutamic pyruvic transaminase': 'alt',
  'sgot': 'ast',
  'serum glutamic oxaloacetic transaminase': 'ast',
  'creatinine serum': 'creatinine',
  'serum creatinine': 'creatinine',
  'bun': 'urea nitrogen',
  'blood urea': 'urea',
  'wbc count': 'wbc',
  'total leucocyte count': 'wbc',
  'tlc': 'wbc',
  'rbc count': 'rbc',
  'platelet count': 'platelets',
  'plt': 'platelets',
  'hematocrit': 'hct',
  'packed cell volume': 'pcv',
  'erythrocyte sedimentation rate': 'esr',
  'creatine kinase': 'ck',
  'vitamin d3': 'vitamin d',
  '25 hydroxy vitamin d': 'vitamin d',
};

function normalizeTestName(name) {
  if (!name) return '';
  let s = String(name).toLowerCase();
  s = s.replace(/\([^)]*\)/g, ' ');
  s = s.replace(/[^a-z0-9\s/-]/g, ' ');
  s = s.replace(/\s+/g, ' ').trim();
  if (TEST_SYNONYMS[s]) return TEST_SYNONYMS[s];
  return s;
}

module.exports = {
  normalizeDrugName,
  extractStrength,
  strengthValue,
  dosageForm,
  normalizeTestName,
  DRUG_SYNONYMS,
  TEST_SYNONYMS,
};
