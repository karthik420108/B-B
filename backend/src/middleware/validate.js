'use strict';

const { ZodError } = require('zod');
const { badRequest } = require('../utils/errors');

/**
 * Validate request parts against zod schemas. On success the parsed (and
 * coerced/stripped) values replace the originals so handlers only ever see
 * validated data.
 */
function validate(schemas = {}) {
  return (req, res, next) => {
    try {
      if (schemas.params) req.params = schemas.params.parse(req.params);
      if (schemas.query) req.validatedQuery = schemas.query.parse(req.query);
      if (schemas.body) req.body = schemas.body.parse(req.body || {});
      next();
    } catch (err) {
      if (err instanceof ZodError) {
        const details = err.issues.map((i) => ({ path: i.path.join('.'), message: i.message }));
        return next(badRequest('Validation failed.', details));
      }
      return next(err);
    }
  };
}

module.exports = { validate };
