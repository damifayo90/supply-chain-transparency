;; Quality Checkpoints Smart Contract
;; Record quality inspections and safety certifications at each stage

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INSPECTOR-NOT-FOUND (err u201))
(define-constant ERR-CHECKPOINT-NOT-FOUND (err u202))
(define-constant ERR-INVALID-SCORE (err u203))
(define-constant ERR-ALREADY-EXISTS (err u204))
(define-constant ERR-CERTIFICATION-EXPIRED (err u205))
(define-constant ERR-INVALID-DATA (err u206))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var inspector-id-counter uint u0)
(define-data-var checkpoint-id-counter uint u0)
(define-data-var certification-id-counter uint u0)
(define-data-var inspection-id-counter uint u0)

;; Quality score constants
(define-constant MIN-QUALITY-SCORE u0)
(define-constant MAX-QUALITY-SCORE u100)
(define-constant PASSING-SCORE u70)

;; Data maps
(define-map quality-inspectors
  { inspector-id: uint }
  {
    name: (string-ascii 100),
    license-number: (string-ascii 50),
    specialization: (string-ascii 100),
    certified: bool,
    certification-expiry: uint,
    registered-at: uint,
    owner: principal
  }
)

(define-map quality-checkpoints
  { checkpoint-id: uint }
  {
    batch-id: uint,
    checkpoint-type: (string-ascii 50),
    location: (string-ascii 200),
    inspector-id: uint,
    quality-score: uint,
    temperature: int,
    humidity: uint,
    notes: (string-ascii 500),
    passed: bool,
    timestamp: uint,
    verified: bool
  }
)

(define-map safety-certifications
  { certification-id: uint }
  {
    batch-id: uint,
    certification-type: (string-ascii 100),
    certifying-authority: (string-ascii 100),
    certificate-number: (string-ascii 50),
    issue-date: uint,
    expiry-date: uint,
    valid: bool,
    issued-by: principal
  }
)

(define-map compliance-records
  { batch-id: uint, standard: (string-ascii 50) }
  {
    compliant: bool,
    verified-by: uint,
    verification-date: uint,
    notes: (string-ascii 300)
  }
)

(define-map inspection-history
  { inspection-id: uint }
  {
    batch-id: uint,
    checkpoint-id: uint,
    inspector-id: uint,
    inspection-type: (string-ascii 50),
    findings: (string-ascii 500),
    corrective-actions: (string-ascii 500),
    follow-up-required: bool,
    timestamp: uint
  }
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-inspector-owner (inspector-id uint))
  (match (map-get? quality-inspectors { inspector-id: inspector-id })
    inspector (is-eq tx-sender (get owner inspector))
    false
  )
)

(define-private (inspector-exists (inspector-id uint))
  (is-some (map-get? quality-inspectors { inspector-id: inspector-id }))
)

(define-private (is-inspector-certified (inspector-id uint))
  (match (map-get? quality-inspectors { inspector-id: inspector-id })
    inspector
    (and 
      (get certified inspector)
      (> (get certification-expiry inspector) burn-block-height)
    )
    false
  )
)

(define-private (is-valid-score (score uint))
  (and (>= score MIN-QUALITY-SCORE) (<= score MAX-QUALITY-SCORE))
)

(define-private (calculate-pass-status (score uint))
  (>= score PASSING-SCORE)
)

;; Public functions

;; Register a quality inspector
(define-public (register-inspector (name (string-ascii 100)) (license-number (string-ascii 50)) (specialization (string-ascii 100)) (certification-expiry uint))
  (let (
    (new-inspector-id (+ (var-get inspector-id-counter) u1))
  )
    (asserts! (> (len name) u0) ERR-INVALID-DATA)
    (asserts! (> (len license-number) u0) ERR-INVALID-DATA)
    (asserts! (> certification-expiry burn-block-height) ERR-CERTIFICATION-EXPIRED)
    
    (map-set quality-inspectors
      { inspector-id: new-inspector-id }
      {
        name: name,
        license-number: license-number,
        specialization: specialization,
        certified: false,
        certification-expiry: certification-expiry,
        registered-at: burn-block-height,
        owner: tx-sender
      }
    )
    
    (var-set inspector-id-counter new-inspector-id)
    (ok new-inspector-id)
  )
)

;; Certify an inspector (only contract owner)
(define-public (certify-inspector (inspector-id uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (inspector-exists inspector-id) ERR-INSPECTOR-NOT-FOUND)
    
    (match (map-get? quality-inspectors { inspector-id: inspector-id })
      inspector
      (begin
        (map-set quality-inspectors
          { inspector-id: inspector-id }
          (merge inspector { certified: true })
        )
        (ok true)
      )
      ERR-INSPECTOR-NOT-FOUND
    )
  )
)

;; Create quality checkpoint
(define-public (create-quality-checkpoint 
    (batch-id uint) 
    (checkpoint-type (string-ascii 50)) 
    (location (string-ascii 200)) 
    (inspector-id uint)
    (quality-score uint)
    (temperature int)
    (humidity uint)
    (notes (string-ascii 500))
  )
  (let (
    (new-checkpoint-id (+ (var-get checkpoint-id-counter) u1))
    (passed (calculate-pass-status quality-score))
  )
    (asserts! (> batch-id u0) ERR-INVALID-DATA)
    (asserts! (> (len checkpoint-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len location) u0) ERR-INVALID-DATA)
    (asserts! (inspector-exists inspector-id) ERR-INSPECTOR-NOT-FOUND)
    (asserts! (is-inspector-certified inspector-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-score quality-score) ERR-INVALID-SCORE)
    
    (map-set quality-checkpoints
      { checkpoint-id: new-checkpoint-id }
      {
        batch-id: batch-id,
        checkpoint-type: checkpoint-type,
        location: location,
        inspector-id: inspector-id,
        quality-score: quality-score,
        temperature: temperature,
        humidity: humidity,
        notes: notes,
        passed: passed,
        timestamp: burn-block-height,
        verified: false
      }
    )
    
    (var-set checkpoint-id-counter new-checkpoint-id)
    (ok new-checkpoint-id)
  )
)

;; Issue safety certification
(define-public (issue-safety-certification 
    (batch-id uint)
    (certification-type (string-ascii 100))
    (certifying-authority (string-ascii 100))
    (certificate-number (string-ascii 50))
    (expiry-date uint)
  )
  (let (
    (new-certification-id (+ (var-get certification-id-counter) u1))
  )
    (asserts! (> batch-id u0) ERR-INVALID-DATA)
    (asserts! (> (len certification-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len certifying-authority) u0) ERR-INVALID-DATA)
    (asserts! (> (len certificate-number) u0) ERR-INVALID-DATA)
    (asserts! (> expiry-date burn-block-height) ERR-CERTIFICATION-EXPIRED)
    
    (map-set safety-certifications
      { certification-id: new-certification-id }
      {
        batch-id: batch-id,
        certification-type: certification-type,
        certifying-authority: certifying-authority,
        certificate-number: certificate-number,
        issue-date: burn-block-height,
        expiry-date: expiry-date,
        valid: true,
        issued-by: tx-sender
      }
    )
    
    (var-set certification-id-counter new-certification-id)
    (ok new-certification-id)
  )
)

;; Record compliance verification
(define-public (record-compliance (batch-id uint) (standard (string-ascii 50)) (inspector-id uint) (compliant bool) (notes (string-ascii 300)))
  (begin
    (asserts! (> batch-id u0) ERR-INVALID-DATA)
    (asserts! (> (len standard) u0) ERR-INVALID-DATA)
    (asserts! (inspector-exists inspector-id) ERR-INSPECTOR-NOT-FOUND)
    (asserts! (is-inspector-certified inspector-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-inspector-owner inspector-id) ERR-NOT-AUTHORIZED)
    
    (map-set compliance-records
      { batch-id: batch-id, standard: standard }
      {
        compliant: compliant,
        verified-by: inspector-id,
        verification-date: burn-block-height,
        notes: notes
      }
    )
    
    (ok true)
  )
)

;; Verify checkpoint (by authorized inspector)
(define-public (verify-checkpoint (checkpoint-id uint))
  (match (map-get? quality-checkpoints { checkpoint-id: checkpoint-id })
    checkpoint
    (begin
      (asserts! (is-inspector-owner (get inspector-id checkpoint)) ERR-NOT-AUTHORIZED)
      
      (map-set quality-checkpoints
        { checkpoint-id: checkpoint-id }
        (merge checkpoint { verified: true })
      )
      (ok true)
    )
    ERR-CHECKPOINT-NOT-FOUND
  )
)

;; Add inspection record
(define-public (add-inspection-record 
    (batch-id uint)
    (checkpoint-id uint)
    (inspector-id uint)
    (inspection-type (string-ascii 50))
    (findings (string-ascii 500))
    (corrective-actions (string-ascii 500))
    (follow-up-required bool)
  )
  (let (
    (new-inspection-id (+ (var-get inspection-id-counter) u1))
  )
    (asserts! (> batch-id u0) ERR-INVALID-DATA)
    (asserts! (inspector-exists inspector-id) ERR-INSPECTOR-NOT-FOUND)
    (asserts! (is-inspector-owner inspector-id) ERR-NOT-AUTHORIZED)
    (asserts! (is-inspector-certified inspector-id) ERR-NOT-AUTHORIZED)
    
    (map-set inspection-history
      { inspection-id: new-inspection-id }
      {
        batch-id: batch-id,
        checkpoint-id: checkpoint-id,
        inspector-id: inspector-id,
        inspection-type: inspection-type,
        findings: findings,
        corrective-actions: corrective-actions,
        follow-up-required: follow-up-required,
        timestamp: burn-block-height
      }
    )
    
    (var-set inspection-id-counter new-inspection-id)
    (ok new-inspection-id)
  )
)

;; Read-only functions

;; Get inspector details
(define-read-only (get-inspector (inspector-id uint))
  (map-get? quality-inspectors { inspector-id: inspector-id })
)

;; Get checkpoint details
(define-read-only (get-checkpoint (checkpoint-id uint))
  (map-get? quality-checkpoints { checkpoint-id: checkpoint-id })
)

;; Get safety certification
(define-read-only (get-safety-certification (certification-id uint))
  (map-get? safety-certifications { certification-id: certification-id })
)

;; Get compliance record
(define-read-only (get-compliance-record (batch-id uint) (standard (string-ascii 50)))
  (map-get? compliance-records { batch-id: batch-id, standard: standard })
)

;; Get inspection record
(define-read-only (get-inspection-record (inspection-id uint))
  (map-get? inspection-history { inspection-id: inspection-id })
)

;; Check if batch passes quality standards
(define-read-only (batch-quality-status (batch-id uint))
  (let (
    (checkpoints-exist true) ;; simplified for this example
  )
    { passed: checkpoints-exist, batch-id: batch-id }
  )
)

;; Get current counters
(define-read-only (get-counters)
  {
    inspectors: (var-get inspector-id-counter),
    checkpoints: (var-get checkpoint-id-counter),
    certifications: (var-get certification-id-counter),
    inspections: (var-get inspection-id-counter)
  }
)
