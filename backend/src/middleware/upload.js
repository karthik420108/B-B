'use strict';

const multer = require('multer');
const config = require('../config');
const { badRequest } = require('../utils/errors');

const ALLOWED = new Set([
  'application/pdf',
  'image/png', 'image/jpeg', 'image/jpg', 'image/webp', 'image/tiff', 'image/bmp',
  'text/plain',
]);

/**
 * Memory storage: the buffer is validated and immediately handed to the storage
 * adapter, so uploaded files never touch a publicly accessible path.
 */
const upload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: config.maxUploadBytes, files: 1, fields: 30 },
  fileFilter(req, file, cb) {
    if (!ALLOWED.has(file.mimetype)) {
      return cb(badRequest(`Unsupported file type "${file.mimetype}".`));
    }
    return cb(null, true);
  },
});

/** Wrap multer so its errors become our uniform AppError shape. */
function singleFile(field = 'file') {
  const handler = upload.single(field);
  return (req, res, next) => {
    handler(req, res, (err) => {
      if (err) {
        if (err.code === 'LIMIT_FILE_SIZE') {
          return next(badRequest(`File is too large. Maximum size is ${Math.round(config.maxUploadBytes / (1024 * 1024))} MB.`));
        }
        if (err.code === 'LIMIT_UNEXPECTED_FILE') {
          return next(badRequest(`Unexpected file field. Use "${field}".`));
        }
        return next(err);
      }
      return next();
    });
  };
}

module.exports = { singleFile, upload, ALLOWED };
