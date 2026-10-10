'use strict';

const { z } = require('zod');

/** Body schema for creating a share grant. */
const shareSchema = z.object({
  documentIds: z.array(z.string().min(5)).max(500).default([]),
  includeAll: z.boolean().default(false),
  includeSummary: z.boolean().default(true),
  includeTimeline: z.boolean().default(true),
  includeMedications: z.boolean().default(true),
  includeAllergies: z.boolean().default(true),
  includeObservations: z.boolean().default(true),
  includeDuplicateAlerts: z.boolean().default(true),
  expiresInMinutes: z.number().int().min(5).max(90 * 24 * 60).default(1440),
  maxAccesses: z.number().int().min(0).max(10000).default(0),
  doctorUserId: z.string().optional().nullable(),
  doctorEmail: z.string().email().optional().nullable(),
  doctorName: z.string().max(120).optional().nullable(),
  doctorSpecialty: z.string().max(120).optional().nullable(),
  label: z.string().max(120).optional().nullable(),
  approvedSummary: z.string().max(20000).optional().nullable(),
});

module.exports = { shareSchema };
