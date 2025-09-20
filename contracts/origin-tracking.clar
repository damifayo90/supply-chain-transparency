;; Origin Tracking Smart Contract
;; Track food products from farm to consumer with origin verification

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-PRODUCT-NOT-FOUND (err u101))
(define-constant ERR-PRODUCER-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STEP (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-BATCH-NOT-FOUND (err u105))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var product-id-counter uint u0)
(define-data-var producer-id-counter uint u0)
(define-data-var batch-id-counter uint u0)
(define-data-var tracking-step-counter uint u0)

;; Data maps
(define-map producers 
  { producer-id: uint }
  { 
    name: (string-ascii 100),
    location: (string-ascii 200),
    certification: (string-ascii 100),
    verified: bool,
    registered-at: uint,
    owner: principal
  }
)

(define-map products
  { product-id: uint }
  {
    name: (string-ascii 100),
    category: (string-ascii 50),
    producer-id: uint,
    created-at: uint,
    origin-verified: bool
  }
)

(define-map batches
  { batch-id: uint }
  {
    product-id: uint,
    producer-id: uint,
    quantity: uint,
    harvest-date: uint,
    expiry-date: uint,
    batch-code: (string-ascii 50),
    current-location: (string-ascii 200),
    created-at: uint
  }
)

(define-map tracking-steps
  { step-id: uint }
  {
    batch-id: uint,
    step-type: (string-ascii 50),
    location: (string-ascii 200),
    timestamp: uint,
    handler: principal,
    notes: (string-ascii 500),
    verified: bool
  }
)

(define-map producer-authorization
  { producer-id: uint, authorized-by: principal }
  { authorized: bool, timestamp: uint }
)

;; Private functions
(define-private (is-contract-owner)
  (is-eq tx-sender (var-get contract-owner))
)

(define-private (is-producer-owner (producer-id uint))
  (match (map-get? producers { producer-id: producer-id })
    producer (is-eq tx-sender (get owner producer))
    false
  )
)

(define-private (producer-exists (producer-id uint))
  (is-some (map-get? producers { producer-id: producer-id }))
)

(define-private (product-exists (product-id uint))
  (is-some (map-get? products { product-id: product-id }))
)

(define-private (batch-exists (batch-id uint))
  (is-some (map-get? batches { batch-id: batch-id }))
)

;; Public functions

;; Register a new producer
(define-public (register-producer (name (string-ascii 100)) (location (string-ascii 200)) (certification (string-ascii 100)))
  (let (
    (new-producer-id (+ (var-get producer-id-counter) u1))
  )
    (asserts! (> (len name) u0) ERR-INVALID-STEP)
    (asserts! (> (len location) u0) ERR-INVALID-STEP)
    
    (map-set producers
      { producer-id: new-producer-id }
      {
        name: name,
        location: location,
        certification: certification,
        verified: false,
        registered-at: burn-block-height,
        owner: tx-sender
      }
    )
    
    (var-set producer-id-counter new-producer-id)
    (ok new-producer-id)
  )
)

;; Verify a producer (only contract owner)
(define-public (verify-producer (producer-id uint))
  (begin
    (asserts! (is-contract-owner) ERR-NOT-AUTHORIZED)
    (asserts! (producer-exists producer-id) ERR-PRODUCER-NOT-FOUND)
    
    (match (map-get? producers { producer-id: producer-id })
      producer
      (begin
        (map-set producers
          { producer-id: producer-id }
          (merge producer { verified: true })
        )
        (ok true)
      )
      ERR-PRODUCER-NOT-FOUND
    )
  )
)

;; Register a new product
(define-public (register-product (name (string-ascii 100)) (category (string-ascii 50)) (producer-id uint))
  (let (
    (new-product-id (+ (var-get product-id-counter) u1))
  )
    (asserts! (> (len name) u0) ERR-INVALID-STEP)
    (asserts! (> (len category) u0) ERR-INVALID-STEP)
    (asserts! (producer-exists producer-id) ERR-PRODUCER-NOT-FOUND)
    (asserts! (is-producer-owner producer-id) ERR-NOT-AUTHORIZED)
    
    (map-set products
      { product-id: new-product-id }
      {
        name: name,
        category: category,
        producer-id: producer-id,
        created-at: burn-block-height,
        origin-verified: true
      }
    )
    
    (var-set product-id-counter new-product-id)
    (ok new-product-id)
  )
)

;; Create a new batch
(define-public (create-batch (product-id uint) (quantity uint) (harvest-date uint) (expiry-date uint) (batch-code (string-ascii 50)))
  (let (
    (new-batch-id (+ (var-get batch-id-counter) u1))
  )
    (asserts! (product-exists product-id) ERR-PRODUCT-NOT-FOUND)
    (asserts! (> quantity u0) ERR-INVALID-STEP)
    (asserts! (> expiry-date harvest-date) ERR-INVALID-STEP)
    (asserts! (> (len batch-code) u0) ERR-INVALID-STEP)
    
    (match (map-get? products { product-id: product-id })
      product
      (begin
        (asserts! (is-producer-owner (get producer-id product)) ERR-NOT-AUTHORIZED)
        
        (map-set batches
          { batch-id: new-batch-id }
          {
            product-id: product-id,
            producer-id: (get producer-id product),
            quantity: quantity,
            harvest-date: harvest-date,
            expiry-date: expiry-date,
            batch-code: batch-code,
            current-location: "Farm",
            created-at: burn-block-height
          }
        )
        
        (var-set batch-id-counter new-batch-id)
        (ok new-batch-id)
      )
      ERR-PRODUCT-NOT-FOUND
    )
  )
)

;; Add tracking step
(define-public (add-tracking-step (batch-id uint) (step-type (string-ascii 50)) (location (string-ascii 200)) (notes (string-ascii 500)))
  (let (
    (new-step-id (+ (var-get tracking-step-counter) u1))
  )
    (asserts! (batch-exists batch-id) ERR-BATCH-NOT-FOUND)
    (asserts! (> (len step-type) u0) ERR-INVALID-STEP)
    (asserts! (> (len location) u0) ERR-INVALID-STEP)
    
    (map-set tracking-steps
      { step-id: new-step-id }
      {
        batch-id: batch-id,
        step-type: step-type,
        location: location,
        timestamp: burn-block-height,
        handler: tx-sender,
        notes: notes,
        verified: false
      }
    )
    
    ;; Update batch current location
    (match (map-get? batches { batch-id: batch-id })
      batch
      (map-set batches
        { batch-id: batch-id }
        (merge batch { current-location: location })
      )
      false
    )
    
    (var-set tracking-step-counter new-step-id)
    (ok new-step-id)
  )
)

;; Verify tracking step (by producer or authorized party)
(define-public (verify-tracking-step (step-id uint))
  (match (map-get? tracking-steps { step-id: step-id })
    step
    (match (map-get? batches { batch-id: (get batch-id step) })
      batch
      (begin
        (asserts! (is-producer-owner (get producer-id batch)) ERR-NOT-AUTHORIZED)
        
        (map-set tracking-steps
          { step-id: step-id }
          (merge step { verified: true })
        )
        (ok true)
      )
      ERR-BATCH-NOT-FOUND
    )
    ERR-INVALID-STEP
  )
)

;; Read-only functions

;; Get producer details
(define-read-only (get-producer (producer-id uint))
  (map-get? producers { producer-id: producer-id })
)

;; Get product details
(define-read-only (get-product (product-id uint))
  (map-get? products { product-id: product-id })
)

;; Get batch details
(define-read-only (get-batch (batch-id uint))
  (map-get? batches { batch-id: batch-id })
)

;; Get tracking step details
(define-read-only (get-tracking-step (step-id uint))
  (map-get? tracking-steps { step-id: step-id })
)

;; Get current counters
(define-read-only (get-counters)
  {
    producers: (var-get producer-id-counter),
    products: (var-get product-id-counter),
    batches: (var-get batch-id-counter),
    steps: (var-get tracking-step-counter)
  }
)
