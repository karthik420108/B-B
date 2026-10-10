'use strict';
const mongoose = require('mongoose');

const ROLES = ['patient', 'doctor', 'admin'];

const userSchema = new mongoose.Schema(
  {
    email: { type: String, required: true, unique: true, lowercase: true, trim: true, index: true },
    passwordHash: { type: String, required: true, select: false },
    role: { type: String, enum: ROLES, default: 'patient', index: true },
    name: { type: String, required: true, trim: true },
    status: { type: String, enum: ['active', 'disabled'], default: 'active' },
    phone: { type: String, trim: true },
    /** Hashed refresh tokens so a stolen DB dump cannot be replayed. */
    refreshTokens: {
      type: [{ tokenHash: String, createdAt: Date, expiresAt: Date, userAgent: String }],
      default: [],
      select: false,
    },
    passwordReset: {
      tokenHash: { type: String, select: false },
      expiresAt: { type: Date, select: false },
      requestedAt: Date,
    },
    lastLoginAt: Date,
  },
  { timestamps: true }
);

userSchema.methods.toSafeJSON = function toSafeJSON() {
  return {
    id: this._id,
    email: this.email,
    role: this.role,
    name: this.name,
    phone: this.phone,
    status: this.status,
    createdAt: this.createdAt,
  };
};

module.exports = mongoose.model('User', userSchema);
module.exports.ROLES = ROLES;
