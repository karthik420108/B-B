'use strict';
const fs = require('fs');
const fsp = require('fs/promises');
const path = require('path');
const crypto = require('crypto');
const config = require('../config');
const { AppError } = require('../utils/errors');

/**
 * Storage adapter interface. Every driver implements:
 *   save(buffer, { key, mimeType })  -> { key, size }
 *   read(key)                        -> Buffer
 *   remove(key)                      -> void
 *   exists(key)                      -> boolean
 *
 * `local` requires no paid service and is the default for development.
 * `s3` is only activated when credentials are configured; otherwise it reports
 * that it is unavailable rather than pretending to work.
 */

class LocalStorage {
  constructor(baseDir) {
    this.baseDir = baseDir;
    this.name = 'local';
    fs.mkdirSync(baseDir, { recursive: true });
  }

  #resolve(key) {
    const safe = String(key).replace(/[^a-zA-Z0-9._/-]/g, '');
    const full = path.resolve(this.baseDir, safe);
    if (!full.startsWith(this.baseDir)) throw new AppError(400, 'BAD_KEY', 'Invalid storage key');
    return full;
  }

  async save(buffer, { key } = {}) {
    const finalKey = key || `files/${crypto.randomUUID()}`;
    const full = this.#resolve(finalKey);
    await fsp.mkdir(path.dirname(full), { recursive: true });
    await fsp.writeFile(full, buffer);
    return { key: finalKey, size: buffer.length };
  }

  async read(key) {
    const full = this.#resolve(key);
    if (!fs.existsSync(full)) throw new AppError(404, 'FILE_NOT_FOUND', 'Stored file not found');
    return fsp.readFile(full);
  }

  async remove(key) {
    const full = this.#resolve(key);
    if (fs.existsSync(full)) await fsp.unlink(full);
  }

  async exists(key) {
    return fs.existsSync(this.#resolve(key));
  }
}

class S3Storage {
  constructor(s3cfg) {
    this.name = 's3';
    this.cfg = s3cfg;
    this.available = Boolean(s3cfg.bucket && s3cfg.region && s3cfg.accessKeyId && s3cfg.secretAccessKey);
    this.client = null;
    if (this.available) {
      try {
        // Optional dependency - only required when S3 storage is actually used.
        // eslint-disable-next-line global-require
        const { S3Client } = require('@aws-sdk/client-s3');
        this.client = new S3Client({
          region: s3cfg.region,
          endpoint: s3cfg.endpoint || undefined,
          credentials: { accessKeyId: s3cfg.accessKeyId, secretAccessKey: s3cfg.secretAccessKey },
        });
        this.sdk = require('@aws-sdk/client-s3');
      } catch (err) {
        this.available = false;
        this.reason = 'The optional @aws-sdk/client-s3 package is not installed.';
      }
    } else {
      this.reason = 'S3 credentials are not configured.';
    }
  }

  #assert() {
    if (!this.available) {
      throw new AppError(503, 'STORAGE_UNAVAILABLE', `S3 storage is unavailable: ${this.reason}`);
    }
  }

  async save(buffer, { key, mimeType } = {}) {
    this.#assert();
    const finalKey = key || `files/${crypto.randomUUID()}`;
    await this.client.send(new this.sdk.PutObjectCommand({
      Bucket: this.cfg.bucket, Key: finalKey, Body: buffer, ContentType: mimeType,
    }));
    return { key: finalKey, size: buffer.length };
  }

  async read(key) {
    this.#assert();
    const out = await this.client.send(new this.sdk.GetObjectCommand({ Bucket: this.cfg.bucket, Key: key }));
    return Buffer.from(await out.Body.transformToByteArray());
  }

  async remove(key) {
    this.#assert();
    await this.client.send(new this.sdk.DeleteObjectCommand({ Bucket: this.cfg.bucket, Key: key }));
  }

  async exists(key) {
    if (!this.available) return false;
    try {
      await this.client.send(new this.sdk.HeadObjectCommand({ Bucket: this.cfg.bucket, Key: key }));
      return true;
    } catch { return false; }
  }
}

let instance = null;
function getStorage() {
  if (instance) return instance;
  switch (config.storage.driver) {
    case 's3':
      instance = new S3Storage(config.storage.s3);
      break;
    case 'cloudinary':
      const CloudinaryStorage = require('./cloudinaryStorage');
      instance = new CloudinaryStorage({
        cloudName: process.env.CLOUDINARY_CLOUD_NAME,
        apiKey: process.env.CLOUDINARY_API_KEY,
        apiSecret: process.env.CLOUDINARY_API_SECRET,
      });
      break;
    default:
      instance = new LocalStorage(config.storage.localDir);
  }
  return instance;
}

/** Test helper - reset the singleton (used when swapping drivers). */
function _resetStorage() { instance = null; }

module.exports = { getStorage, _resetStorage, LocalStorage, S3Storage };
