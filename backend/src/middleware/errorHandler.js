'use strict';

const config = require('../config');
const { AppError } = require('../utils/errors');
const logger = require('../utils/logger');

function notFoundHandler(req, res, next) {
  next(new AppError(404, 'NOT_FOUND', `Route ${req.method} ${req.path} not found.`));
}

/**
 * Central error handler. Produces a consistent envelope and never leaks stack
 * traces, internal file paths or database details to clients.
 */
// eslint-disable-next-line no-unused-vars
function errorHandler(err, req, res, next) {
  let status = 500;
  let code = 'INTERNAL_ERROR';
  let message = 'Something went wrong.';
  let details;

  if (err instanceof AppError) {
    status = err.status; code = err.code; message = err.message; details = err.details;
  } else if (err.name === 'ValidationError') {
    status = 400; code = 'VALIDATION_ERROR'; message = 'The submitted data is invalid.';
    details = Object.values(err.errors || {}).map((e) => ({ path: e.path, message: e.message }));
  } else if (err.name === 'CastError') {
    status = 400; code = 'INVALID_ID'; message = 'A provided identifier is not valid.';
  } else if (err.code === 11000) {
    status = 409; code = 'CONFLICT'; message = 'A record with these values already exists.';
  } else if (err.type === 'entity.too.large' || err.status === 413) {
    status = 413; code = 'PAYLOAD_TOO_LARGE'; message = 'Request payload is too large.';
  } else if (err.type === 'entity.parse.failed') {
    status = 400; code = 'BAD_JSON'; message = 'The request body is not valid JSON.';
  }

  if (status >= 500) {
    logger.error('Unhandled error on %s %s: %s', req.method, req.path, err.message);
  }

  const body = { success: false, error: { code, message } };
  if (details) body.error.details = details;
  if (config.env === 'development' && status >= 500) body.error.debug = err.message;

  res.status(status).json(body);
}

module.exports = { errorHandler, notFoundHandler };
