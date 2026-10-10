'use strict';

/** Application error with an HTTP status and a machine-readable code. */
class AppError extends Error {
  constructor(status, code, message, details) {
    super(message);
    this.name = 'AppError';
    this.status = status;
    this.code = code;
    this.details = details;
    this.expose = true;
  }
}

const badRequest = (msg, details) => new AppError(400, 'BAD_REQUEST', msg, details);
const unauthorized = (msg = 'Authentication required') => new AppError(401, 'UNAUTHORIZED', msg);
const forbidden = (msg = 'You are not allowed to perform this action') => new AppError(403, 'FORBIDDEN', msg);
const notFound = (msg = 'Resource not found') => new AppError(404, 'NOT_FOUND', msg);
const conflict = (msg, details) => new AppError(409, 'CONFLICT', msg, details);
const tooMany = (msg = 'Too many requests') => new AppError(429, 'RATE_LIMITED', msg);
const unprocessable = (msg, details) => new AppError(422, 'UNPROCESSABLE', msg, details);

module.exports = {
  AppError,
  badRequest,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  tooMany,
  unprocessable,
};
