'use strict';

const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const config = require('../config');
const { User, PatientProfile, DoctorProfile } = require('../models');
const { randomToken, hashToken } = require('../utils/crypto');
const { AppError, badRequest, unauthorized, conflict, notFound } = require('../utils/errors');
const auditService = require('./auditService');
const logger = require('../utils/logger');

const BCRYPT_ROUNDS = 12;
const PASSWORD_MIN = 8;

function assertPassword(password) {
  if (!password || String(password).length < PASSWORD_MIN) {
    throw badRequest(`Password must be at least ${PASSWORD_MIN} characters.`);
  }
}

function signAccessToken(user) {
  return jwt.sign(
    { sub: String(user._id), role: user.role, name: user.name, jti: randomToken(10) },
    config.jwt.accessSecret,
    { expiresIn: config.jwt.accessTtl, issuer: 'health-wallet' }
  );
}

function signRefreshToken(user) {
  return jwt.sign(
    // `jti` guarantees rotation: jwt.sign only timestamps in whole seconds, so
    // signing twice within the same second would otherwise produce a byte-
    // identical token and the "old" one would stay valid forever.
    { sub: String(user._id), role: user.role, typ: 'refresh', jti: randomToken(10) },
    config.jwt.refreshSecret,
    { expiresIn: config.jwt.refreshTtl, issuer: 'health-wallet' }
  );
}

function refreshExpiryDate() {
  // Parse strings like "7d", "12h", "30m"; default 7 days.
  const ttl = config.jwt.refreshTtl;
  const m = String(ttl).match(/^(\d+)([smhd])$/);
  if (!m) return new Date(Date.now() + 7 * 86400000);
  const unit = { s: 1000, m: 60000, h: 3600000, d: 86400000 }[m[2]];
  return new Date(Date.now() + parseInt(m[1], 10) * unit);
}

async function issueTokens(user, userAgent) {
  const accessToken = signAccessToken(user);
  const refreshToken = signRefreshToken(user);
  await User.updateOne(
    { _id: user._id },
    {
      $push: {
        refreshTokens: {
          $each: [{ tokenHash: hashToken(refreshToken), createdAt: new Date(), expiresAt: refreshExpiryDate(), userAgent: String(userAgent || '').slice(0, 200) }],
          $slice: -10, // keep only the 10 most recent sessions
        },
      },
      $set: { lastLoginAt: new Date() },
    }
  );
  return { accessToken, refreshToken, expiresIn: config.jwt.accessTtl };
}

async function register({ email, password, name, role = 'patient', phone, doctorProfile } = {}, { req = null } = {}) {
  assertPassword(password);
  if (!email || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw badRequest('A valid email address is required.');
  if (!name || name.trim().length < 2) throw badRequest('A name is required.');
  if (!['patient', 'doctor'].includes(role)) throw badRequest('Role must be patient or doctor.');

  const existing = await User.findOne({ email: String(email).toLowerCase() });
  if (existing) throw conflict('An account with this email already exists.');

  const passwordHash = await bcrypt.hash(String(password), BCRYPT_ROUNDS);
  const user = await User.create({ email: String(email).toLowerCase(), passwordHash, name: name.trim(), role, phone });

  if (role === 'patient') {
    await PatientProfile.create({ user: user._id });
  } else {
    await DoctorProfile.create({
      user: user._id,
      specialty: doctorProfile?.specialty,
      licenseNumber: doctorProfile?.licenseNumber,
      clinicName: doctorProfile?.clinicName,
      // Self-registered doctors are NOT verified. Development seeds set `development`.
      verification: { status: 'unverified', method: 'self-registration' },
    });
  }

  await auditService.record(req, { action: 'auth.registered', actor: user._id, actorRole: user.role, metadata: { role } });
  const tokens = await issueTokens(user, req && req.headers && req.headers['user-agent']);
  return { user: user.toSafeJSON(), ...tokens };
}

async function login({ email, password } = {}, { req = null } = {}) {
  if (!email || !password) throw badRequest('Email and password are required.');
  const user = await User.findOne({ email: String(email).toLowerCase() }).select('+passwordHash');
  // Constant-ish behaviour: always run a bcrypt compare to reduce user enumeration timing.
  const hash = user ? user.passwordHash : '$2a$12$0000000000000000000000000000000000000000000000000000';
  const valid = await bcrypt.compare(String(password), hash);
  if (!user || !valid) {
    await auditService.record(req, { action: 'auth.login_failed', metadata: { emailDomain: String(email).split('@')[1] || 'unknown' } });
    throw unauthorized('Incorrect email or password.');
  }
  if (user.status !== 'active') throw unauthorized('This account is disabled. Contact support.');

  const tokens = await issueTokens(user, req && req.headers && req.headers['user-agent']);
  await auditService.record(req, { action: 'auth.login', actor: user._id, actorRole: user.role });
  const json = user.toSafeJSON();
  // Surface doctor verification status at login so the client can route
  // unverified doctors to a pending-verification screen.
  if (user.role === 'doctor') {
    const profile = await DoctorProfile.findOne({ user: user._id }).select('verification.status');
    json.doctorVerification = (profile && profile.verification && profile.verification.status) || 'unverified';
  }
  return { user: json, ...tokens };
}

async function refresh({ refreshToken } = {}, { req = null } = {}) {
  if (!refreshToken) throw unauthorized('A refresh token is required.');
  let payload;
  try {
    payload = jwt.verify(refreshToken, config.jwt.refreshSecret, { issuer: 'health-wallet' });
  } catch {
    throw unauthorized('The refresh token is invalid or expired.');
  }
  const user = await User.findById(payload.sub).select('+refreshTokens');
  if (!user || user.status !== 'active') throw unauthorized('Account unavailable.');

  const tokenHash = hashToken(refreshToken);
  const match = (user.refreshTokens || []).find((t) => t.tokenHash === tokenHash);
  if (!match) throw unauthorized('This refresh token has been revoked. Please sign in again.');
  if (match.expiresAt && new Date(match.expiresAt).getTime() < Date.now()) throw unauthorized('The refresh token has expired.');

  // Rotate: remove the used token from the DB, then issue a new pair so a
  // stolen/reused old token is never accepted again.
  await User.updateOne({ _id: user._id }, { $pull: { refreshTokens: { tokenHash } } });
  const tokens = await issueTokens(user, req && req.headers && req.headers['user-agent']);
  return { user: user.toSafeJSON(), ...tokens };
}

async function logout({ refreshToken, allDevices = false } = {}, { user, req = null } = {}) {
  if (!user) throw unauthorized();
  if (allDevices) {
    await User.updateOne({ _id: user._id }, { $set: { refreshTokens: [] } });
  } else if (refreshToken) {
    await User.updateOne({ _id: user._id }, { $pull: { refreshTokens: { tokenHash: hashToken(refreshToken) } } });
  } else {
    await User.updateOne({ _id: user._id }, { $set: { refreshTokens: [] } });
  }
  await auditService.record(req, { action: 'auth.logout', actor: user._id, actorRole: user.role });
  return { ok: true };
}

/**
 * Start a password reset. Always returns success to avoid account enumeration.
 * In development the reset token is returned so the flow is testable without
 * an email provider; in production it is only sent by email (adapter TBD).
 */
async function forgotPassword({ email }, { req = null } = {}) {
  const user = await User.findOne({ email: String(email || '').toLowerCase() });
  const response = { ok: true, message: 'If that account exists, a reset link has been created.' };
  if (!user) return response;
  const token = randomToken(24);
  user.passwordReset = { tokenHash: hashToken(token), expiresAt: new Date(Date.now() + 30 * 60 * 1000), requestedAt: new Date() };
  await user.save();
  await auditService.record(req, { action: 'auth.password_reset_requested', actor: user._id });
  if (config.env !== 'production') {
    response.developmentResetToken = token; // dev-only convenience; never set in production
    response.message += ' (Development mode: use the returned token to reset.)';
  } else {
    logger.info('Password reset requested for a user (email delivery adapter not configured in this build).');
  }
  return response;
}

async function resetPassword({ token, password }, { req = null } = {}) {
  assertPassword(password);
  if (!token) throw badRequest('A reset token is required.');
  const user = await User.findOne({ 'passwordReset.tokenHash': hashToken(token) })
    .select('+passwordReset.tokenHash +passwordReset.expiresAt');
  if (!user || !user.passwordReset || !user.passwordReset.expiresAt || new Date(user.passwordReset.expiresAt).getTime() < Date.now()) {
    throw badRequest('The reset token is invalid or has expired.');
  }
  user.passwordHash = await bcrypt.hash(String(password), BCRYPT_ROUNDS);
  user.passwordReset = undefined;
  user.refreshTokens = []; // invalidate existing sessions
  await user.save();
  await auditService.record(req, { action: 'auth.password_reset', actor: user._id });
  return { ok: true };
}

async function changePassword(user, { currentPassword, newPassword }, { req = null } = {}) {
  assertPassword(newPassword);
  const full = await User.findById(user._id).select('+passwordHash');
  const okPw = await bcrypt.compare(String(currentPassword || ''), full.passwordHash);
  if (!okPw) throw unauthorized('Your current password is incorrect.');
  full.passwordHash = await bcrypt.hash(String(newPassword), BCRYPT_ROUNDS);
  full.refreshTokens = [];
  await full.save();
  await auditService.record(req, { action: 'auth.password_changed', actor: user._id });
  return { ok: true };
}

async function getMe(userId) {
  const user = await User.findById(userId);
  if (!user) throw notFound('Account not found');
  let profile = null;
  if (user.role === 'patient') profile = await PatientProfile.findOne({ user: userId });
  if (user.role === 'doctor') profile = await DoctorProfile.findOne({ user: userId });
  return { user: user.toSafeJSON(), profile };
}

module.exports = {
  register, login, refresh, logout, forgotPassword, resetPassword, changePassword, getMe, assertPassword,
  hashPassword: (pw) => bcrypt.hash(String(pw), BCRYPT_ROUNDS),
};
