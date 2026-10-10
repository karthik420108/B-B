'use strict';

const { Notification } = require('../models');

/**
 * Notifications intentionally carry no medical detail - only a title, a short
 * generic body and a reference to the entity the client should fetch.
 */
async function notify(userId, { type, title, body = '', refType, refId } = {}) {
  if (!userId) return null;
  return Notification.create({ user: userId, type, title, body, refType, refId });
}

async function listForUser(userId, { unreadOnly = false, limit = 50 } = {}) {
  const query = { user: userId };
  if (unreadOnly) query.read = false;
  return Notification.find(query).sort({ createdAt: -1 }).limit(Math.min(limit, 200)).lean();
}

async function markRead(userId, id) {
  return Notification.findOneAndUpdate({ _id: id, user: userId }, { read: true }, { new: true });
}

async function markAllRead(userId) {
  return Notification.updateMany({ user: userId, read: false }, { read: true });
}

async function unreadCount(userId) {
  return Notification.countDocuments({ user: userId, read: false });
}

module.exports = { notify, listForUser, markRead, markAllRead, unreadCount };
