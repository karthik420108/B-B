'use strict';

const { z } = require('zod');

/**
 * Schema for extraction output. Every structured extraction is validated here
 * before it is written to the database. Nothing is silently invented - unknown
 * values are null and surfaced for patient review.
 */

const nullableDate = z.union([z.string().datetime(), z.null()]);
const nullableString = z.union([z.string().max(400), z.null()]);

const observationSchema = z.object({
  testName: z.string().min(1).max(120),
  value: z.union([z.number(), z.null()]),
  unit: nullableString,
  referenceRange: nullableString,
  abnormal: z.union([z.boolean(), z.null()]).default(null),
});

const medicationSchema = z.object({
  name: z.string().min(2).max(120),
  strength: nullableString,
  frequency: nullableString,
  route: nullableString,
  form: nullableString,
  dose: nullableString,
});

const allergySchema = z.object({
  substance: z.string().min(2).max(120),
  reaction: nullableString,
  severity: z.enum(['mild', 'moderate', 'severe', 'unknown']).default('unknown'),
});

const conditionSchema = z.object({
  name: z.string().min(2).max(160),
});

const extractionSchema = z.object({
  documentType: z.enum([
    'prescription', 'laboratory', 'imaging', 'discharge_summary',
    'consultation_note', 'vaccination', 'other',
  ]).default('other'),
  providerName: nullableString,
  eventDate: nullableDate,
  eventDateEstimated: z.union([z.boolean(), z.null()]).default(null),
  observations: z.array(observationSchema).max(200).default([]),
  medications: z.array(medicationSchema).max(100).default([]),
  allergies: z.array(allergySchema).max(50).default([]),
  conditions: z.array(conditionSchema).max(50).default([]),
  followUp: z.array(z.string().max(300)).max(30).default([]),
  reviewNotes: z.array(z.string().max(400)).max(30).default([]),
});

/** Validate and coerce extraction output. Throws a ZodError when invalid. */
function validateExtraction(raw) {
  return extractionSchema.parse(raw);
}

module.exports = { extractionSchema, validateExtraction };
