'use strict';

/* Test bootstrap. Sets env BEFORE any app module is required. */
const path = require('path');
const os = require('os');

process.env.NODE_ENV = 'test';
process.env.MONGODB_URI = process.env.MONGODB_URI_TEST || 'mongodb://127.0.0.1:27017/health_wallet_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.JWT_ACCESS_TTL = '30m';
process.env.JWT_REFRESH_TTL = '1d';
process.env.STORAGE_LOCAL_DIR = path.join(os.tmpdir(), `hw-test-uploads-${process.pid}`);
process.env.AI_PROVIDER = 'local';
process.env.INTERACTION_DATASET = './data/interactions.json';

const mongoose = require('mongoose');
const request = require('supertest');
const { createApp } = require('../src/app');
const db = require('../src/config/db');

const app = createApp();

async function connect() {
  if (mongoose.connection.readyState !== 1) {
    await mongoose.connect(process.env.MONGODB_URI, { serverSelectionTimeoutMS: 8000 });
  }
}

async function clearDatabase() {
  const collections = await mongoose.connection.db.collections();
  await Promise.all(collections.map((c) => c.deleteMany({})));
}

async function disconnect() {
  await mongoose.connection.dropDatabase().catch(() => {});
  await mongoose.disconnect();
}

let counter = 0;
function uniqueEmail(prefix = 'user') {
  counter += 1;
  return `${prefix}${Date.now()}${counter}@test.health`;
}

const PASSWORD = 'TestPass123!';

async function register(role = 'patient', overrides = {}) {
  const email = overrides.email || uniqueEmail(role);
  const res = await request(app).post('/api/auth/register').send({
    email, password: PASSWORD, name: overrides.name || `${role} Test`, role, ...overrides,
  });
  if (res.status !== 201) throw new Error(`register failed: ${res.status} ${JSON.stringify(res.body)}`);
  return { ...res.body.data, email, password: PASSWORD };
}

async function login(email, password = PASSWORD) {
  const res = await request(app).post('/api/auth/login').send({ email, password });
  if (res.status !== 200) throw new Error(`login failed: ${res.status}`);
  return res.body.data;
}

/** Build a minimal valid text-layer PDF (pure JS, no deps). */
function makeTextPdf(lines) {
  const esc = (s) => String(s).replace(/([()\\])/g, '\\$1');
  const content = `BT /F1 12 Tf 50 760 Td 16 TL ${lines.map((l) => `(${esc(l)}) Tj T*`).join(' ')} ET`;
  const objs = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    `<< /Length ${content.length} >>\nstream\n${content}\nendstream`,
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  let pdf = '%PDF-1.4\n';
  const offsets = [];
  objs.forEach((o, i) => { offsets.push(pdf.length); pdf += `${i + 1} 0 obj\n${o}\nendobj\n`; });
  const xrefStart = pdf.length;
  pdf += `xref\n0 ${objs.length + 1}\n0000000000 65535 f \n`;
  offsets.forEach((off) => { pdf += `${String(off).padStart(10, '0')} 00000 n \n`; });
  pdf += `trailer\n<< /Size ${objs.length + 1} /Root 1 0 R >>\nstartxref\n${xrefStart}\n%%EOF`;
  return Buffer.from(pdf, 'latin1');
}

module.exports = { app, request, connect, clearDatabase, disconnect, register, login, makeTextPdf, uniqueEmail, PASSWORD, mongoose };
