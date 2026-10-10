'use strict';

module.exports = {
  User: require('./User'),
  PatientProfile: require('./PatientProfile'),
  DoctorProfile: require('./DoctorProfile'),
  Provider: require('./Provider'),
  Document: require('./Document'),
  ShareGrant: require('./ShareGrant'),
  AuditEvent: require('./AuditEvent'),
  Notification: require('./Notification'),
  Appointment: require('./Appointment'),
  ExtractionJob: require('./ExtractionJob'),
  ...require('./clinical'),
};
