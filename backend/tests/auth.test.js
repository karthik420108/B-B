'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

test('registers a patient and returns tokens (never the password hash)', async () => {
  const res = await h.request(h.app).post('/api/auth/register').send({
    email: h.uniqueEmail('p'), password: h.PASSWORD, name: 'Pat One', role: 'patient',
  });
  assert.equal(res.status, 201);
  assert.ok(res.body.data.accessToken);
  assert.ok(res.body.data.refreshToken);
  assert.equal(res.body.data.user.role, 'patient');
  assert.equal(res.body.data.user.passwordHash, undefined);
});

test('rejects weak passwords and duplicate emails', async () => {
  const weak = await h.request(h.app).post('/api/auth/register').send({ email: h.uniqueEmail(), password: 'short', name: 'X Y', role: 'patient' });
  assert.equal(weak.status, 400);

  const u = await h.register('patient');
  const dup = await h.request(h.app).post('/api/auth/register').send({ email: u.email, password: h.PASSWORD, name: 'Dup', role: 'patient' });
  assert.equal(dup.status, 409);
});

test('login rejects wrong password and accepts correct', async () => {
  const u = await h.register('patient');
  const bad = await h.request(h.app).post('/api/auth/login').send({ email: u.email, password: 'WrongPass123!' });
  assert.equal(bad.status, 401);
  const good = await h.request(h.app).post('/api/auth/login').send({ email: u.email, password: h.PASSWORD });
  assert.equal(good.status, 200);
});

test('protected routes require a valid bearer token', async () => {
  const noToken = await h.request(h.app).get('/api/patient/profile');
  assert.equal(noToken.status, 401);
  const badToken = await h.request(h.app).get('/api/patient/profile').set('Authorization', 'Bearer not-a-jwt');
  assert.equal(badToken.status, 401);
});

test('refresh rotates tokens and invalidates the old refresh token', async () => {
  const u = await h.register('patient');
  const first = await h.request(h.app).post('/api/auth/refresh').send({ refreshToken: u.refreshToken });
  assert.equal(first.status, 200);
  assert.ok(first.body.data.accessToken);
  const reuse = await h.request(h.app).post('/api/auth/refresh').send({ refreshToken: u.refreshToken });
  assert.equal(reuse.status, 401, 'rotated refresh token must not be reusable');
});

test('logout revokes the refresh token', async () => {
  const u = await h.register('patient');
  await h.request(h.app).post('/api/auth/logout').set('Authorization', `Bearer ${u.accessToken}`).send({ refreshToken: u.refreshToken });
  const after = await h.request(h.app).post('/api/auth/refresh').send({ refreshToken: u.refreshToken });
  assert.equal(after.status, 401);
});

test('role-based authorization blocks patients from the doctor area', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).get('/api/doctor/shares').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(res.status, 403);
});

test('password reset flow works with a dev token', async () => {
  const u = await h.register('patient');
  const forgot = await h.request(h.app).post('/api/auth/forgot-password').send({ email: u.email });
  assert.equal(forgot.status, 200);
  const token = forgot.body.data.developmentResetToken;
  assert.ok(token, 'dev build returns a reset token');
  const reset = await h.request(h.app).post('/api/auth/reset-password').send({ token, password: 'BrandNewPass123!' });
  assert.equal(reset.status, 200);
  const login = await h.request(h.app).post('/api/auth/login').send({ email: u.email, password: 'BrandNewPass123!' });
  assert.equal(login.status, 200);
});
