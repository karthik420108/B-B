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
  DoctorConversation: require('./DoctorConversation'),
  MedicationSchedule: require('./MedicationSchedule'),
  MedicationDose: require('./MedicationDose'),
  ...require('./clinical'),
};
