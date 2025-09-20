;; Recall Management Smart Contract
;; Rapid product recall system with precise contamination source tracking

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-RECALL-NOT-FOUND (err u301))
(define-constant ERR-INVALID-SEVERITY (err u302))
(define-constant ERR-BATCH-NOT-FOUND (err u303))
(define-constant ERR-RECALL-ALREADY-RESOLVED (err u304))
(define-constant ERR-STAKEHOLDER-NOT-FOUND (err u305))
(define-constant ERR-INVALID-DATA (err u306))
(define-constant ERR-NOTIFICATION-FAILED (err u307))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var recall-id-counter uint u0)
(define-data-var stakeholder-id-counter uint u0)
(define-data-var notification-id-counter uint u0)
(define-data-var contamination-id-counter uint u0)

;; Recall severity levels
(define-constant SEVERITY-LOW u1)
(define-constant SEVERITY-MEDIUM u2)
(define-constant SEVERITY-HIGH u3)
(define-constant SEVERITY-CRITICAL u4)

;; Recall status
(define-constant STATUS-INITIATED u1)
(define-constant STATUS-IN-PROGRESS u2)
(define-constant STATUS-RESOLVED u3)
(define-constant STATUS-CANCELLED u4)

;; Data maps
(define-map recall-events
  { recall-id: uint }
  {
    batch-ids: (list 50 uint),
    reason: (string-ascii 500),
    severity: uint,
    status: uint,
    initiated-by: principal,
    initiated-at: uint,
    resolved-at: (optional uint),
    affected-quantity: uint,
    contamination-source: (optional uint),
    regulatory-notification: bool,
    public-notification: bool
  }
)

(define-map stakeholders
  { stakeholder-id: uint }
  {
    name: (string-ascii 100),
    stakeholder-type: (string-ascii 50),
    contact-info: (string-ascii 200),
    notification-method: (string-ascii 50),
    critical-contact: bool,
    registered-at: uint,
    owner: principal
  }
)

(define-map contamination-sources
  { contamination-id: uint }
  {
    source-type: (string-ascii 100),
    location: (string-ascii 200),
    contamination-date: uint,
    identified-at: uint,
    severity: uint,
    description: (string-ascii 500),
    affected-batches: (list 20 uint),
    contained: bool
  }
)

(define-map recall-notifications
  { notification-id: uint }
  {
    recall-id: uint,
    stakeholder-id: uint,
    message: (string-ascii 1000),
    notification-type: (string-ascii 50),
    sent-at: uint,
    acknowledged: bool,
    acknowledged-at: (optional uint)
  }
)

(define-map batch-recall-status
  { batch-id: uint }
  {
    recall-id: uint,
    recalled: bool,
    recall-date: uint,
    recovery-status: (string-ascii 50),
    quantity-recovered: uint,
    total-quantity: uint
  }
)

(define-map recall-effectiveness
  { recall-id: uint }
  {
    total-affected: uint,
    total-recovered: uint,
    recovery-percentage: uint,
    time-to-resolution: uint,
    stakeholder-response-rate: uint,
    success-score: uint
  }
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-stakeholder-owner (stakeholder-id uint))
  (match (map-get? stakeholders { stakeholder-id: stakeholder-id })
    stakeholder (is-eq tx-sender (get owner stakeholder))
    false
  )
)

(define-private (is-valid-severity (severity uint))
  (and (>= severity SEVERITY-LOW) (<= severity SEVERITY-CRITICAL))
)

(define-private (is-valid-status (status uint))
  (and (>= status STATUS-INITIATED) (<= status STATUS-CANCELLED))
)

(define-private (stakeholder-exists (stakeholder-id uint))
  (is-some (map-get? stakeholders { stakeholder-id: stakeholder-id }))
)

(define-private (recall-exists (recall-id uint))
  (is-some (map-get? recall-events { recall-id: recall-id }))
)

(define-private (calculate-recovery-percentage (recovered uint) (total uint))
  (if (> total u0)
    (/ (* recovered u100) total)
    u0
  )
)

;; Public functions

;; Register stakeholder
(define-public (register-stakeholder 
    (name (string-ascii 100))
    (stakeholder-type (string-ascii 50))
    (contact-info (string-ascii 200))
    (notification-method (string-ascii 50))
    (critical-contact bool)
  )
  (let (
    (new-stakeholder-id (+ (var-get stakeholder-id-counter) u1))
  )
    (asserts! (> (len name) u0) ERR-INVALID-DATA)
    (asserts! (> (len stakeholder-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len contact-info) u0) ERR-INVALID-DATA)
    
    (map-set stakeholders
      { stakeholder-id: new-stakeholder-id }
      {
        name: name,
        stakeholder-type: stakeholder-type,
        contact-info: contact-info,
        notification-method: notification-method,
        critical-contact: critical-contact,
        registered-at: burn-block-height,
        owner: tx-sender
      }
    )
    
    (var-set stakeholder-id-counter new-stakeholder-id)
    (ok new-stakeholder-id)
  )
)

;; Initiate product recall
(define-public (initiate-recall 
    (batch-ids (list 50 uint))
    (reason (string-ascii 500))
    (severity uint)
    (affected-quantity uint)
    (contamination-source (optional uint))
    (regulatory-notification bool)
  )
  (let (
    (new-recall-id (+ (var-get recall-id-counter) u1))
  )
    (asserts! (> (len batch-ids) u0) ERR-INVALID-DATA)
    (asserts! (> (len reason) u0) ERR-INVALID-DATA)
    (asserts! (is-valid-severity severity) ERR-INVALID-SEVERITY)
    (asserts! (> affected-quantity u0) ERR-INVALID-DATA)
    
    (map-set recall-events
      { recall-id: new-recall-id }
      {
        batch-ids: batch-ids,
        reason: reason,
        severity: severity,
        status: STATUS-INITIATED,
        initiated-by: tx-sender,
        initiated-at: burn-block-height,
        resolved-at: none,
        affected-quantity: affected-quantity,
        contamination-source: contamination-source,
        regulatory-notification: regulatory-notification,
        public-notification: false
      }
    )
    
    ;; Mark batches as recalled
    (map mark-batch-recalled batch-ids)
    
    (var-set recall-id-counter new-recall-id)
    (ok new-recall-id)
  )
)

;; Mark batch as recalled (private helper)
(define-private (mark-batch-recalled (batch-id uint))
  (map-set batch-recall-status
    { batch-id: batch-id }
    {
      recall-id: (var-get recall-id-counter),
      recalled: true,
      recall-date: burn-block-height,
      recovery-status: "initiated",
      quantity-recovered: u0,
      total-quantity: u0 ;; This would be fetched from origin-tracking in a real implementation
    }
  )
)

;; Record contamination source
(define-public (record-contamination-source
    (source-type (string-ascii 100))
    (location (string-ascii 200))
    (contamination-date uint)
    (severity uint)
    (description (string-ascii 500))
    (affected-batches (list 20 uint))
  )
  (let (
    (new-contamination-id (+ (var-get contamination-id-counter) u1))
  )
    (asserts! (> (len source-type) u0) ERR-INVALID-DATA)
    (asserts! (> (len location) u0) ERR-INVALID-DATA)
    (asserts! (is-valid-severity severity) ERR-INVALID-SEVERITY)
    (asserts! (> (len description) u0) ERR-INVALID-DATA)
    
    (map-set contamination-sources
      { contamination-id: new-contamination-id }
      {
        source-type: source-type,
        location: location,
        contamination-date: contamination-date,
        identified-at: burn-block-height,
        severity: severity,
        description: description,
        affected-batches: affected-batches,
        contained: false
      }
    )
    
    (var-set contamination-id-counter new-contamination-id)
    (ok new-contamination-id)
  )
)

;; Send recall notification
(define-public (send-recall-notification
    (recall-id uint)
    (stakeholder-id uint)
    (message (string-ascii 1000))
    (notification-type (string-ascii 50))
  )
  (let (
    (new-notification-id (+ (var-get notification-id-counter) u1))
  )
    (asserts! (recall-exists recall-id) ERR-RECALL-NOT-FOUND)
    (asserts! (stakeholder-exists stakeholder-id) ERR-STAKEHOLDER-NOT-FOUND)
    (asserts! (> (len message) u0) ERR-INVALID-DATA)
    (asserts! (> (len notification-type) u0) ERR-INVALID-DATA)
    
    (map-set recall-notifications
      { notification-id: new-notification-id }
      {
        recall-id: recall-id,
        stakeholder-id: stakeholder-id,
        message: message,
        notification-type: notification-type,
        sent-at: burn-block-height,
        acknowledged: false,
        acknowledged-at: none
      }
    )
    
    (var-set notification-id-counter new-notification-id)
    (ok new-notification-id)
  )
)

;; Acknowledge notification
(define-public (acknowledge-notification (notification-id uint))
  (match (map-get? recall-notifications { notification-id: notification-id })
    notification
    (begin
      (asserts! (is-stakeholder-owner (get stakeholder-id notification)) ERR-NOT-AUTHORIZED)
      
      (map-set recall-notifications
        { notification-id: notification-id }
        (merge notification {
          acknowledged: true,
          acknowledged-at: (some burn-block-height)
        })
      )
      (ok true)
    )
    ERR-NOTIFICATION-FAILED
  )
)

;; Update recall status
(define-public (update-recall-status (recall-id uint) (new-status uint))
  (match (map-get? recall-events { recall-id: recall-id })
    recall-event
    (begin
      (asserts! (or (is-contract-owner) (is-eq tx-sender (get initiated-by recall-event))) ERR-NOT-AUTHORIZED)
      (asserts! (is-valid-status new-status) ERR-INVALID-DATA)
      
      (map-set recall-events
        { recall-id: recall-id }
        (merge recall-event {
          status: new-status,
          resolved-at: (if (is-eq new-status STATUS-RESOLVED) 
                         (some burn-block-height) 
                         (get resolved-at recall-event))
        })
      )
      (ok true)
    )
    ERR-RECALL-NOT-FOUND
  )
)

;; Update batch recovery status
(define-public (update-batch-recovery (batch-id uint) (recovery-status (string-ascii 50)) (quantity-recovered uint))
  (match (map-get? batch-recall-status { batch-id: batch-id })
    batch-status
    (begin
      (asserts! (> (len recovery-status) u0) ERR-INVALID-DATA)
      
      (map-set batch-recall-status
        { batch-id: batch-id }
        (merge batch-status {
          recovery-status: recovery-status,
          quantity-recovered: quantity-recovered
        })
      )
      (ok true)
    )
    ERR-BATCH-NOT-FOUND
  )
)

;; Calculate recall effectiveness
(define-public (calculate-recall-effectiveness (recall-id uint) (total-affected uint) (total-recovered uint))
  (let (
    (recovery-percentage (calculate-recovery-percentage total-recovered total-affected))
    (time-to-resolution u0) ;; Simplified calculation
    (success-score (if (>= recovery-percentage u80) u90 (if (>= recovery-percentage u60) u70 u50)))
  )
    (asserts! (recall-exists recall-id) ERR-RECALL-NOT-FOUND)
    (asserts! (> total-affected u0) ERR-INVALID-DATA)
    
    (map-set recall-effectiveness
      { recall-id: recall-id }
      {
        total-affected: total-affected,
        total-recovered: total-recovered,
        recovery-percentage: recovery-percentage,
        time-to-resolution: time-to-resolution,
        stakeholder-response-rate: u85, ;; Simplified
        success-score: success-score
      }
    )
    
    (ok success-score)
  )
)

;; Read-only functions

;; Get recall details
(define-read-only (get-recall (recall-id uint))
  (map-get? recall-events { recall-id: recall-id })
)

;; Get stakeholder details
(define-read-only (get-stakeholder (stakeholder-id uint))
  (map-get? stakeholders { stakeholder-id: stakeholder-id })
)

;; Get contamination source details
(define-read-only (get-contamination-source (contamination-id uint))
  (map-get? contamination-sources { contamination-id: contamination-id })
)

;; Get notification details
(define-read-only (get-notification (notification-id uint))
  (map-get? recall-notifications { notification-id: notification-id })
)

;; Get batch recall status
(define-read-only (get-batch-recall-status (batch-id uint))
  (map-get? batch-recall-status { batch-id: batch-id })
)

;; Get recall effectiveness
(define-read-only (get-recall-effectiveness (recall-id uint))
  (map-get? recall-effectiveness { recall-id: recall-id })
)

;; Check if batch is recalled
(define-read-only (is-batch-recalled (batch-id uint))
  (match (map-get? batch-recall-status { batch-id: batch-id })
    batch-status (get recalled batch-status)
    false
  )
)

;; Get current counters
(define-read-only (get-counters)
  {
    recalls: (var-get recall-id-counter),
    stakeholders: (var-get stakeholder-id-counter),
    notifications: (var-get notification-id-counter),
    contamination-sources: (var-get contamination-id-counter)
  }
)
