'use strict';

/**
 * Curated clinical knowledge base providing outside medical context
 * to complement patient-specific uploaded records.
 *
 * Rules:
 * 1. Uploaded patient records always take primary precedence (cited with [n]).
 * 2. General clinical knowledge provides educational context, standard guidelines,
 *    reference ranges, and definitions thereafter.
 */

const KNOWLEDGE_TOPICS = [
  // --- Lab Tests & Biomarkers ---
  {
    keywords: ['hba1c', 'glycated hemoglobin', 'a1c', 'glycohemoglobin'],
    title: 'Hemoglobin A1c (HbA1c)',
    context: 'HbA1c reflects the average blood glucose concentration over the past 2 to 3 months (the lifespan of red blood cells). Standard clinical reference ranges:\n'
      + '• Normal (non-diabetic): Below 5.7%\n'
      + '• Prediabetes: 5.7% to 6.4%\n'
      + '• Diabetes: 6.5% or higher on two separate tests\n'
      + '• Common management target for adults with diabetes: Generally < 7.0%, tailored individually based on hypoglycemia risk and comorbidities.',
  },
  {
    keywords: ['glucose', 'blood sugar', 'fasting blood sugar', 'fbs', 'postprandial'],
    title: 'Blood Glucose',
    context: 'Blood glucose measures circulating sugar levels in the bloodstream. Typical clinical references:\n'
      + '• Fasting (8+ hours): Normal is 70–99 mg/dL; Prediabetes is 100–125 mg/dL; Diabetes is ≥ 126 mg/dL.\n'
      + '• Postprandial (2 hours post-meal): Normal is generally < 140 mg/dL; Diabetes is ≥ 200 mg/dL.\n'
      + 'Elevated glucose warrants evaluation of diet, activity, and metabolic health.',
  },
  {
    keywords: ['cholesterol', 'lipid', 'ldl', 'hdl', 'triglyceride'],
    title: 'Lipid Profile (Cholesterol & Triglycerides)',
    context: 'A lipid panel assesses cardiovascular risk markers:\n'
      + '• Total Cholesterol: Desirable is < 200 mg/dL.\n'
      + '• LDL ("bad" cholesterol): Optimal is < 100 mg/dL; for high cardiovascular risk patients, targets are often < 70 or < 55 mg/dL.\n'
      + '• HDL ("good" cholesterol): Protective is > 40 mg/dL (men) or > 50 mg/dL (women).\n'
      + '• Triglycerides: Normal is < 150 mg/dL.',
  },
  {
    keywords: ['blood pressure', 'bp', 'systolic', 'diastolic', 'hypertension', 'hypertensive'],
    title: 'Blood Pressure & Hypertension',
    context: 'Blood pressure is measured in mmHg (Systolic / Diastolic):\n'
      + '• Normal: Less than 120/80 mmHg.\n'
      + '• Elevated: Systolic 120–129 and Diastolic < 80 mmHg.\n'
      + '• Stage 1 Hypertension: Systolic 130–139 or Diastolic 80–89 mmHg.\n'
      + '• Stage 2 Hypertension: Systolic ≥ 140 or Diastolic ≥ 90 mmHg.\n'
      + 'Persistent hypertension increases risk of stroke, heart disease, and renal impairment.',
  },
  {
    keywords: ['creatinine', 'bun', 'egfr', 'kidney', 'renal'],
    title: 'Renal Function (Creatinine, BUN, eGFR)',
    context: 'Kidney function markers evaluate the glomerular filtration capacity:\n'
      + '• Serum Creatinine: Typical reference is 0.7–1.3 mg/dL (men), 0.6–1.1 mg/dL (women).\n'
      + '• eGFR (Estimated Glomerular Filtration Rate): Normal is > 90 mL/min/1.73m²; 60–89 indicates mildly decreased; < 60 for 3+ months indicates chronic kidney disease (CKD).\n'
      + '• BUN (Blood Urea Nitrogen): Typical reference is 7–20 mg/dL.',
  },
  {
    keywords: ['alt', 'ast', 'sgpt', 'sgot', 'bilirubin', 'liver', 'hepatic', 'alkaline phosphatase', 'alp'],
    title: 'Hepatic Function (Liver Enzymes)',
    context: 'Liver enzyme panels assess hepatocellular integrity and biliary excretion:\n'
      + '• ALT (Alanine Aminotransferase): Normal is roughly 7–56 U/L. ALT is highly specific to liver tissue.\n'
      + '• AST (Aspartate Aminotransferase): Normal is roughly 10–40 U/L. Found in liver, cardiac, and skeletal muscle.\n'
      + '• Total Bilirubin: Typical reference is 0.2–1.2 mg/dL.\n'
      + 'Elevated transaminases warrant investigation of viral hepatitis, fatty liver (MASLD/NAFLD), alcohol, or medications.',
  },
  {
    keywords: ['tsh', 'thyroid', 't3', 't4', 'hypothyroid', 'hyperthyroid', 'levothyroxine'],
    title: 'Thyroid Function (TSH, Free T4)',
    context: 'Thyroid hormones regulate baseline metabolic rate throughout the body:\n'
      + '• TSH (Thyroid Stimulating Hormone): Normal reference is typically 0.4–4.0 mIU/L.\n'
      + '• Elevated TSH with low Free T4 suggests primary hypothyroidism (common symptoms: fatigue, weight gain, cold intolerance).\n'
      + '• Suppressed TSH with elevated Free T4 suggests hyperthyroidism (symptoms: palpitations, weight loss, heat intolerance).',
  },
  {
    keywords: ['cbc', 'complete blood count', 'hemoglobin', 'haemoglobin', 'rbc', 'wbc', 'platelet', 'platelets', 'anemia', 'anaemia'],
    title: 'Complete Blood Count (CBC) & Anemia',
    context: 'CBC evaluates cellular blood components:\n'
      + '• Hemoglobin: Normal is roughly 13.5–17.5 g/dL (men), 12.0–15.5 g/dL (women). Low levels indicate anemia.\n'
      + '• White Blood Cells (WBC): Typical reference is 4,500–11,000 /µL. Elevation often reflects infection or inflammation.\n'
      + '• Platelets: Typical reference is 150,000–450,000 /µL, essential for blood clotting.',
  },
  {
    keywords: ['mri', 'brain mri', 'spine mri', 'magnetic resonance'],
    title: 'Magnetic Resonance Imaging (MRI)',
    context: 'MRI utilizes strong magnetic fields and radiofrequency waves to generate high-resolution cross-sectional images of soft tissues without ionizing radiation.\n'
      + '• Brain MRI is standard for assessing cerebrovascular events, demyelinating lesions (e.g. MS), intracranial neoplasms, or unexplained neurological symptoms.\n'
      + '• If a recent scan was performed, upload the official radiologist report to have its findings tracked and reviewed in your wallet.',
  },
  {
    keywords: ['ct scan', 'computed tomography', 'cat scan', 'x-ray', 'radiograph', 'ultrasound', 'sonogram'],
    title: 'Diagnostic Imaging (CT, X-Ray, Ultrasound)',
    context: 'Diagnostic imaging evaluates structural and anatomical changes:\n'
      + '• CT Scans provide rapid cross-sectional views with ionizing radiation, ideal for acute trauma, chest, or abdomen.\n'
      + '• Ultrasounds use high-frequency sound waves, ideal for abdominal organs, pelvic exams, and vascular doppler.\n'
      + '• Formal radiologist reports should be imported for verified clinical analysis.',
  },

  // --- Common Chronic Conditions ---
  {
    keywords: ['diabetes', 'diabetic', 'type 2 diabetes', 'type 1 diabetes'],
    title: 'Diabetes Mellitus',
    context: 'Diabetes is a metabolic disorder characterized by chronic hyperglycemia resulting from defects in insulin secretion, insulin action, or both.\n'
      + '• Key management pillars: Glycemic monitoring (HbA1c, daily glucose), medical nutrition therapy, physical activity, and pharmacotherapy (e.g. Metformin, SGLT2 inhibitors, GLP-1 agonists, Insulin).\n'
      + '• Preventative monitoring includes annual retinal exams, urine microalbumin-to-creatinine ratio for kidney health, and comprehensive foot exams.',
  },
  {
    keywords: ['asthma', 'copd', 'wheezing', 'inhaler', 'albuterol'],
    title: 'Respiratory Health (Asthma & COPD)',
    context: 'Obstructive airway diseases involve chronic airway inflammation and bronchial hyperresponsiveness:\n'
      + '• Reliever / Rescue: Short-acting beta agonists (e.g. Albuterol / Salbutamol) for acute bronchospasm.\n'
      + '• Controller / Maintenance: Inhaled corticosteroids (ICS) alone or with long-acting beta agonists (LABA) to reduce airway inflammation and exacerbation frequency.',
  },

  // --- Common Medications & Drug Classes ---
  {
    keywords: ['metformin', 'glucophage'],
    title: 'Metformin',
    context: 'Metformin is an oral biguanide and standard first-line medication for Type 2 Diabetes:\n'
      + '• Mechanism: Decreases hepatic glucose production, decreases intestinal absorption of glucose, and improves insulin sensitivity.\n'
      + '• Common side effects: Gastrointestinal upset (nausea, diarrhea, abdominal cramps); taking with meals or using extended-release formulations helps.\n'
      + '• Safety note: Renal function (eGFR) must be periodically evaluated; should be withheld prior to iodinated contrast procedures.',
  },
  {
    keywords: ['statin', 'atorvastatin', 'rosuvastatin', 'simvastatin', 'lipitor', 'crestor'],
    title: 'HMG-CoA Reductase Inhibitors (Statins)',
    context: 'Statins are the primary pharmacological therapy for lipid lowering and primary/secondary atherosclerotic cardiovascular risk reduction:\n'
      + '• Mechanism: Inhibits the rate-limiting enzyme in hepatic cholesterol synthesis, upregulating LDL receptors.\n'
      + '• Monitoring: Baseline liver enzymes and lipid response at 4–12 weeks. Report unexplained muscle soreness or weakness.',
  },
  {
    keywords: ['lisinopril', 'losartan', 'amlodipine', 'metoprolol', 'atenolol', 'ace inhibitor', 'arb'],
    title: 'Antihypertensive Medications',
    context: 'Common first-line antihypertensive classes include:\n'
      + '• ACE Inhibitors (e.g. Lisinopril) and ARBs (e.g. Losartan): Inhibit the renin-angiotensin system, protective for diabetic kidney disease. Require monitoring of serum potassium and creatinine.\n'
      + '• Calcium Channel Blockers (e.g. Amlodipine): Relax vascular smooth muscle. Watch for peripheral leg swelling.\n'
      + '• Beta Blockers (e.g. Metoprolol): Lower heart rate and cardiac workload, particularly indicated post-myocardial infarction or in heart failure.',
  },
  {
    keywords: ['warfarin', 'coumadin', 'apixaban', 'eliquis', 'rivaroxaban', 'xarelto', 'blood thinner', 'anticoagulant'],
    title: 'Anticoagulants (Blood Thinners)',
    context: 'Anticoagulants prevent thromboembolic events (deep vein thrombosis, pulmonary embolism, stroke in atrial fibrillation):\n'
      + '• Warfarin: Vitamin K antagonist requiring routine International Normalized Ratio (INR) monitoring (typically target 2.0–3.0) and attention to dietary vitamin K intake.\n'
      + '• DOACs (Apixaban, Rivaroxaban): Direct factor Xa inhibitors with fixed dosing without routine INR monitoring.\n'
      + '• Crucial Safety Rule: Avoid concurrent NSAIDs (ibuprofen, naproxen) without explicit physician direction due to severe bleeding risks.',
  },
  {
    keywords: ['ibuprofen', 'paracetamol', 'acetaminophen', 'tylenol', 'advil', 'nsaid', 'aspirin'],
    title: 'Analgesics & Anti-inflammatories',
    context: 'Common pain and fever medications:\n'
      + '• Paracetamol / Acetaminophen: First-line antipyretic/analgesic with low GI toxicity. Maximum recommended adult daily dose is 3,000–4,000 mg (less in liver disease) to avoid hepatotoxicity.\n'
      + '• NSAIDs (Ibuprofen, Naproxen): Non-steroidal anti-inflammatories. Use with caution in hypertension, renal impairment, peptic ulcer history, or when taking blood thinners.',
  },
];

/**
 * Find matching general clinical knowledge for a question and relevant keywords.
 *
 * @param {string} question
 * @param {boolean} [isDoctor=false]
 * @returns {string|null}
 */
function getGeneralMedicalKnowledge(question, isDoctor = false) {
  if (!question || typeof question !== 'string') return null;
  const qLower = question.toLowerCase();

  const matches = [];
  for (const item of KNOWLEDGE_TOPICS) {
    for (const kw of item.keywords) {
      // Word boundary match
      const regex = new RegExp(`\\b${kw.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
      if (regex.test(qLower)) {
        matches.push(item);
        break;
      }
    }
  }

  if (matches.length === 0) {
    // Fallback general guidance if question is medical in nature
    if (/\b(doctor|physician|medicine|health|symptom|hospital|checkup|test|lab|report|result|normal|disease|treat)\b/i.test(qLower)) {
      return isDoctor
        ? 'Clinical Reference: Correlate patient-reported concerns with comprehensive history, physical examination, and appropriate diagnostic modalities.'
        : 'General Health Advice: For questions regarding symptoms, test interpretation, or treatment decisions, consult with a qualified healthcare provider for personalized medical evaluation.';
    }
    return null;
  }

  // Deduplicate and assemble top matches
  const uniqueMatches = Array.from(new Set(matches)).slice(0, 2);
  const sections = uniqueMatches.map((m) => `[General Medical Knowledge: ${m.title}]\n${m.context}`);
  return sections.join('\n\n');
}

module.exports = {
  getGeneralMedicalKnowledge,
  KNOWLEDGE_TOPICS,
};
