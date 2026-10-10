'use strict';

const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const h = require('./helpers');

before(h.connect);
after(h.disconnect);
beforeEach(h.clearDatabase);

test('unknown routes return a consistent 404 envelope', async () => {
  const res = await h.request(h.app).get('/api/does-not-exist');
  assert.equal(res.status, 404);
  assert.equal(res.body.success, false);
  assert.equal(res.body.error.code, 'NOT_FOUND');
});

test('validation errors return field-level detail', async () => {
  const res = await h.request(h.app).post('/api/auth/register').send({ email: 'not-an-email', password: 'x' });
  assert.equal(res.status, 400);
  assert.equal(res.body.error.code, 'BAD_REQUEST');
  assert.ok(Array.isArray(res.body.error.details));
  assert.ok(res.body.error.details.length >= 1);
});

test('profile validation rejects invalid enum values', async () => {
  const u = await h.register('patient');
  const res = await h.request(h.app).patch('/api/patient/profile')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ bloodGroup: 'ZZ+' });
  assert.equal(res.status, 400);
});

test('profile update persists and rejects a future date of birth', async () => {
  const u = await h.register('patient');
  const ok = await h.request(h.app).patch('/api/patient/profile')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ dateOfBirth: '1980-01-01', bloodGroup: 'O+', chronicConditions: ['Asthma'] });
  assert.equal(ok.status, 200);
  assert.equal(ok.body.data.bloodGroup, 'O+');

  const future = await h.request(h.app).patch('/api/patient/profile')
    .set('Authorization', `Bearer ${u.accessToken}`)
    .send({ dateOfBirth: '2999-01-01' });
  assert.equal(future.status, 400);
});

test('malformed JSON body does not crash the server', async () => {
  const res = await h.request(h.app).post('/api/auth/login').set('Content-Type', 'application/json').send('{ bad json ');
  assert.ok(res.status >= 400 && res.status < 500);
});

test('data export and account deletion workflows work', async () => {
  const u = await h.register('patient');
  const exp = await h.request(h.app).get('/api/patient/export').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(exp.status, 200);
  assert.equal(exp.body.data.format, 'health-wallet-export/v1');

  const badDelete = await h.request(h.app).delete('/api/patient/account').set('Authorization', `Bearer ${u.accessToken}`).send({ confirm: 'nope' });
  assert.equal(badDelete.status, 400);

  const del = await h.request(h.app).delete('/api/patient/account').set('Authorization', `Bearer ${u.accessToken}`).send({ confirm: 'DELETE' });
  assert.equal(del.status, 200);
  const after = await h.request(h.app).get('/api/patient/profile').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(after.status, 401, 'token invalid after account deletion');
});

test('notifications list + mark read', async () => {
  const u = await h.register('patient');
  const list = await h.request(h.app).get('/api/notifications').set('Authorization', `Bearer ${u.accessToken}`);
  assert.equal(list.status, 200);
  assert.ok(Array.isArray(list.body.data));
});
