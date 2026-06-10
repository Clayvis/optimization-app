# M5 Biomarkers — build plan (executed 2026-06-10)

Scope (port of References/biomarker-tracker.html, validated logic, no redesign):
- Resources: biomarker_catalog.json (71 markers) + biomarker_aliases.json (183)
  extracted verbatim from the reference HTML via JXA evaluation.
- BiomarkerCatalog: loader, evaluate() port, normalizeName/aliasToKey port
  with sex remapping.
- PhenoAgeCalculator: Levine 2018 exact coefficients; pinned by tests
  (30.7 / 26.5 / 77.1 hand-computed expectations).
- BiomarkerInsights: HOMA-IR, first-to-latest trend %, 12 rule-based patterns.
- BiomarkerPDFParser: actor; PDFKit text + Vision OCR fallback; DOD MTF stanza
  + generic longest-alias strategies; 3-pattern date extraction.
- LabDrawStore: UTC-midnight day key, fetch-or-merge upsert (no .unique with
  CloudKit), reference-JSON import (sample_lab_dod.json regression).
- Views: BiomarkersView dashboard (PhenoAge crest, summary, patterns,
  categories, history), LabDrawEditorView (manual + parse-review), 
  MarkerDetailView (Swift Charts trend with optimal/normal bands).
- LabDraw model: already in SchemaV1; no schema bump needed.

Deferred (listed for user): Claude API interpretation of a draw (reference's
"Parse with Claude" / analysis call), wearable-overlay trend chart.

Regression target: sample_lab_dod.pdf NOT present yet (user supplies); JSON
fixture bundled into test target instead (project.yml buildPhase: resources).
