'use strict';
const mongoose = require('mongoose');

const doctorProfileSchema = new mongoose.Schema(
  {
    user: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true, unique: true, index: true },
    specialty: { type: String, trim: true },
    licenseNumber: { type: String, trim: true },
    clinicName: { type: String, trim: true },
    /**
     * Identity verification state. Seed scripts create `development` doctors.
     * Production verification must happen through a real credentialing flow -
     * never a hard-coded demo password.
     */
    verification: {
      status: { type: String, enum: ['unverified', 'development', 'verified'], default: 'unverified' },
      method: { type: String, default: 'none' },
      verifiedAt: Date,
      verifiedBy: { type: mongoose.Schema.Types.ObjectId, ref: 'User' },
    },
  },
  { timestamps: true }
);

module.exports = mongoose.model('DoctorProfile', doctorProfileSchema);
