const { v2: cloudinary } = require('cloudinary');
const fetch = require('node-fetch');
const { AppError } = require('../utils/errors');

class CloudinaryStorage {
  constructor({ cloudName, apiKey, apiSecret }) {
    this.name = 'cloudinary';
    cloudinary.config({
      cloud_name: cloudName,
      api_key: apiKey,
      api_secret: apiSecret,
    });
  }

  /** Upload a buffer; returns public_id (key) and size */
  async save(buffer, { key, mimeType } = {}) {
    const uploadOpts = {
      resource_type: mimeType && mimeType.startsWith('image/') ? 'image' : 'raw',
      public_id: key,
      folder: 'uploads',
    };
    try {
      const result = await new Promise((resolve, reject) => {
        const stream = cloudinary.uploader.upload_stream(uploadOpts, (error, result) => {
          if (error) return reject(error);
          resolve(result);
        });
        stream.end(buffer);
      });
      return { key: result.public_id, size: buffer.length, url: result.secure_url };
    } catch (e) {
      throw new AppError(500, 'CLOUDINARY_UPLOAD_FAILED', e.message);
    }
  }

  /** Download the raw bytes from Cloudinary */
  async read(publicId) {
    try {
      const url = cloudinary.url(publicId, { resource_type: 'raw', type: 'upload', download: true });
      const resp = await fetch(url);
      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const arrayBuffer = await resp.arrayBuffer();
      return Buffer.from(arrayBuffer);
    } catch (e) {
      throw new AppError(404, 'CLOUDINARY_NOT_FOUND', e.message);
    }
  }

  async remove(publicId) {
    try {
      await cloudinary.uploader.destroy(publicId, { resource_type: 'raw' });
    } catch (_) {}
  }

  async exists(publicId) {
    try {
      await cloudinary.api.resource(publicId, { resource_type: 'raw' });
      return true;
    } catch (_) {
      return false;
    }
  }
}

module.exports = CloudinaryStorage;
