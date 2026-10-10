'use strict';

/** Wrap an async route handler so rejections reach the error middleware. */
const asyncHandler = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

/** Standard pagination parser. */
function parsePagination(query, { defaultLimit = 20, maxLimit = 100 } = {}) {
  const page = Math.max(1, parseInt(query.page || '1', 10) || 1);
  const limit = Math.min(maxLimit, Math.max(1, parseInt(query.limit || String(defaultLimit), 10) || defaultLimit));
  return { page, limit, skip: (page - 1) * limit };
}

/** Uniform success envelope. */
function ok(res, data, extra = {}) {
  return res.json({ success: true, data, ...extra });
}

/** Uniform paginated envelope. */
function paginated(res, items, total, { page, limit }) {
  return res.json({
    success: true,
    data: items,
    pagination: {
      page,
      limit,
      total,
      pages: Math.max(1, Math.ceil(total / limit)),
    },
  });
}

module.exports = { asyncHandler, parsePagination, ok, paginated };
