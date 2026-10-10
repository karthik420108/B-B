'use strict';

const jwt = require('jsonwebtoken');
const config = require('../config');
const { User, DoctorProfile } = require('../models');
const { AppError, unauthorized, forbidden } = require('../utils/errors');

/** Verify the access token and attach `req.user` (never the password hash). */
async function authenticate(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const [scheme, token] = header.split(' ');
    if (scheme !== 'Bearer' || !token) throw unauthorized('Missing bearer token.');
    let payload;
    try {
      payload = jwt.verify(token, config.jwt.accessSecret, { issuer: 'health-wallet' });
    } catch {
      throw unauthorized('Your session has expired. Please sign in again.');
    }
    const user = await User.findById(payload.sub).select('email role name status phone');
    if (!user || user.status !== 'active') throw unauthorized('Account unavailable.');
    req.user = user;
    req.tokenPayload = payload;
    next();
  } catch (err) {
    next(err);
  }
}

/** Attach req.user if a valid token is present, but never fail the request. */
async function optionalAuth(req, res, next) {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme === 'Bearer' && token) {
    try {
      const payload = jwt.verify(token, config.jwt.accessSecret, { issuer: 'health-wallet' });
      const user = await User.findById(payload.sub).select('email role name status phone');
      if (user && user.status === 'active') { req.user = user; req.tokenPayload = payload; }
    } catch { /* ignore */ }
  }
  next();
}

/** Role-based authorization enforced on the server. */
function requireRole(...roles) {
  return (req, res, next) => {
    if (!req.user) return next(unauthorized());
    if (!roles.includes(req.user.role)) return next(forbidden('Your account role cannot access this resource.'));
    return next();
  };
}

/**
 * Ensure the authenticated doctor's identity has been verified.
 * `development` is the status assigned by the dev-only seed script; production
 * verification must go through a real credentialing flow. Self-registered
 * doctors start as `unverified` and cannot access patient records until approved.
 */
async function requireVerifiedDoctor(req, res, next) {
  try {
    if (!req.user) return next(unauthorized());
    if (req.user.role !== 'doctor') return next(forbidden('Only verified doctors can access patient records.'));
    const profile = await DoctorProfile.findOne({ user: req.user._id }).select('verification.status');
    const status = profile && profile.verification ? profile.verification.status : 'unverified';
    if (status !== 'verified' && status !== 'development') {
      return next(forbidden('Your doctor account is pending verification. You cannot access patient records yet.'));
    }
    return next();
  } catch (err) {
    return next(err);
  }
}

/** Ensure the authenticated user IS the patient whose id is being requested. */
function requireSelf(paramName = 'patientId') {
  return (req, res, next) => {
    const id = req.params[paramName] || req.body[paramName] || req.query[paramName];
    if (!req.user) return next(unauthorized());
    if (req.user.role === 'admin') return next();
    if (String(req.user._id) !== String(id)) return next(forbidden('You can only access your own records.'));
    return next();
  };
}

module.exports = { authenticate, optionalAuth, requireRole, requireVerifiedDoctor, requireSelf, AppError };
