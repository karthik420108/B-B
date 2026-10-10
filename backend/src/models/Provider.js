'use strict';
const mongoose = require('mongoose');

const PROVIDER_TYPES = ['clinic', 'hospital', 'laboratory', 'pharmacy', 'imaging', 'other'];

const providerSchema = new mongoose.Schema(
  {
    name: { type: String, required: true, trim: true, index: true },
    type: { type: String, enum: PROVIDER_TYPES, default: 'other', index: true },
    address: { type: String, trim: true },
    phone: { type: String, trim: true },
    /** Marks the bundled synthetic demo providers (never real facility). */
    fictional: { type: Boolean, default: false },
    createdBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
  },
  { timestamps: true }
);

providerSchema.index({ name: 'text', address: 'text' });

module.exports = mongoose.model('Provider', providerSchema);
module.exports.PROVIDER_TYPES = PROVIDER_TYPES;
