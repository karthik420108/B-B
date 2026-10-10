'use strict';
const mongoose = require('mongoose');

/**
 * Server-side doctor AI conversation for one share grant.
 *
 * Scoped by (grant, doctor) so that:
 *  - switching patients can never leak the previous patient's context,
 *  - the conversation dies with the grant (access is re-validated on every
 *    request regardless of what is stored here),
 *  - the doctor cannot supply or read another doctor's thread.
 *
 * Only the question text and the generated answer summary are kept, capped to
 * the most recent turns. Full medical records are never stored in this
 * collection - answers always cite the underlying records instead.
 */
const doctorConversationSchema = new mongoose.Schema(
  {
    grant: { type: mongoose.Schema.Types.ObjectId, ref: 'ShareGrant', required: true, index: true },
    doctor: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    patient: { type: mongoose.Schema.Types.ObjectId, ref: 'User', required: true },
    messages: {
      type: [{
        role: { type: String, enum: ['doctor', 'assistant'], required: true },
        content: { type: String, required: true },
        citations: { type: [{ type: String }], default: [] },
        at: { type: Date, default: Date.now },
      }],
      default: [],
    },
    lastQuestionAt: { type: Date },
  },
  { timestamps: true }
);

doctorConversationSchema.index({ grant: 1, doctor: 1 }, { unique: true });

/** Keep only the most recent turns so a long thread cannot grow unbounded. */
doctorConversationSchema.methods.trimMessages = function trimMessages(max = 12) {
  if (this.messages.length > max) this.messages = this.messages.slice(-max);
};

module.exports = mongoose.model('DoctorConversation', doctorConversationSchema);
