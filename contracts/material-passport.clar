;; material-passport.clar
;; Digital passport management for materials in a circular economy.
;; Each material gets a unique passport with metadata and compliance tracking.

;; ==========================
;; Constants and error codes
;; ==========================

(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-ALREADY-EXISTS (err u201))
(define-constant ERR-NOT-FOUND (err u202))
(define-constant ERR-INVALID-INPUT (err u203))
(define-constant ERR-UPDATE-DENIED (err u204))

;; Compliance status codes
(define-constant STATUS-PENDING u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-REJECTED u3)
(define-constant STATUS-EXPIRED u4)

;; Material types
(define-constant TYPE-PLASTIC u10)
(define-constant TYPE-METAL u20)
(define-constant TYPE-TEXTILE u30)
(define-constant TYPE-ELECTRONICS u40)
(define-constant TYPE-OTHER u99)

;; ==========================
;; Data structures
;; ==========================

(define-data-var passport-admin principal tx-sender)
(define-data-var next-passport-id uint u1)

(define-map passports
  { id: uint }
  {
    material-type: uint,
    manufacturer: principal,
    composition: (string-ascii 300),
    weight: uint,
    dimensions: (string-ascii 100),
    certifications: (list 5 (string-ascii 50)),
    compliance-status: uint,
    carbon-footprint: uint, ;; in grams CO2e
    recyclability-score: uint, ;; 0-100
    created-at: uint,
    updated-at: uint
  }
)

(define-map passport-metadata
  { id: uint }
  {
    product-name: (string-ascii 100),
    description: (string-ascii 500),
    origin-country: (string-ascii 50),
    batch-number: (string-ascii 50),
    manufacturing-date: uint,
    expiry-date: (optional uint)
  }
)

(define-map compliance-records
  { passport-id: uint, record-id: uint }
  {
    auditor: principal,
    standard: (string-ascii 100),
    score: uint, ;; 0-100
    notes: (string-ascii 300),
    audit-date: uint,
    valid-until: uint
  }
)

;; Individual counter maps for each passport
(define-map compliance-counters { passport-id: uint } { count: uint })

(define-map sustainability-metrics
  { id: uint }
  {
    water-usage: uint, ;; liters
    energy-consumption: uint, ;; kWh  
    waste-generated: uint, ;; grams
    renewable-content: uint, ;; percentage
    last-updated: uint
  }
)

;; ==========================
;; Administrative functions
;; ==========================

(define-read-only (get-passport-admin)
  (ok (var-get passport-admin))
)

(define-private (is-passport-admin (who principal))
  (is-eq who (var-get passport-admin))
)

(define-public (set-passport-admin (new-admin principal))
  (begin
    (if (not (is-passport-admin tx-sender))
        ERR-NOT-AUTHORIZED
        (begin
          (var-set passport-admin new-admin)
          (ok true)
        )
    )
  )
)

;; ==========================
;; Passport creation and management
;; ==========================

(define-private (get-next-id)
  (let ((current-id (var-get next-passport-id)))
    (begin
      (var-set next-passport-id (+ current-id u1))
      current-id
    )
  )
)

(define-public (create-passport 
  (material-type uint)
  (manufacturer principal)
  (composition (string-ascii 300))
  (weight uint)
  (dimensions (string-ascii 100))
  (certifications (list 5 (string-ascii 50)))
  (carbon-footprint uint)
  (recyclability-score uint)
  )
  (let ((passport-id (get-next-id)))
    (begin
      (if (or (<= weight u0) (> recyclability-score u100))
          ERR-INVALID-INPUT
          (begin
            (map-set passports { id: passport-id }
              {
                material-type: material-type,
                manufacturer: manufacturer,
                composition: composition,
                weight: weight,
                dimensions: dimensions,
                certifications: certifications,
                compliance-status: STATUS-PENDING,
                carbon-footprint: carbon-footprint,
                recyclability-score: recyclability-score,
                created-at: block-height,
                updated-at: block-height
              }
            )
            (ok passport-id)
          )
      )
    )
  )
)

(define-public (add-metadata
  (passport-id uint)
  (product-name (string-ascii 100))
  (description (string-ascii 500))
  (origin-country (string-ascii 50))
  (batch-number (string-ascii 50))
  (manufacturing-date uint)
  (expiry-date (optional uint))
  )
  (begin
    (if (is-none (map-get? passports { id: passport-id }))
        ERR-NOT-FOUND
        (begin
          (map-set passport-metadata { id: passport-id }
            {
              product-name: product-name,
              description: description,
              origin-country: origin-country,
              batch-number: batch-number,
              manufacturing-date: manufacturing-date,
              expiry-date: expiry-date
            }
          )
          (ok true)
        )
    )
  )
)

;; ==========================
;; Compliance management
;; ==========================

(define-private (next-compliance-record (passport-id uint))
  (let ((current (default-to u0 (get count (map-get? compliance-counters { passport-id: passport-id })))))
    (begin
      (map-set compliance-counters { passport-id: passport-id } { count: (+ current u1) })
      (+ current u1)
    )
  )
)

(define-public (add-compliance-record
  (passport-id uint)
  (auditor principal)
  (standard (string-ascii 100))
  (score uint)
  (notes (string-ascii 300))
  (valid-until uint)
  )
  (begin
    (if (or (is-none (map-get? passports { id: passport-id }))
            (> score u100)
            (<= valid-until block-height))
        ERR-INVALID-INPUT
        (let ((record-id (next-compliance-record passport-id)))
          (begin
            (map-set compliance-records { passport-id: passport-id, record-id: record-id }
              {
                auditor: auditor,
                standard: standard,
                score: score,
                notes: notes,
                audit-date: block-height,
                valid-until: valid-until
              }
            )
            (ok record-id)
          )
        )
    )
  )
)

(define-public (update-compliance-status (passport-id uint) (new-status uint))
  (match (map-get? passports { id: passport-id })
    passport
      (if (is-passport-admin tx-sender)
          (begin
            (map-set passports { id: passport-id }
              (merge passport { compliance-status: new-status, updated-at: block-height })
            )
            (ok true)
          )
          ERR-NOT-AUTHORIZED
      )
    ERR-NOT-FOUND
  )
)

;; ==========================
;; Sustainability metrics
;; ==========================

(define-public (update-sustainability-metrics
  (passport-id uint)
  (water-usage uint)
  (energy-consumption uint)
  (waste-generated uint)
  (renewable-content uint)
  )
  (begin
    (if (or (is-none (map-get? passports { id: passport-id }))
            (> renewable-content u100))
        ERR-INVALID-INPUT
        (begin
          (map-set sustainability-metrics { id: passport-id }
            {
              water-usage: water-usage,
              energy-consumption: energy-consumption,
              waste-generated: waste-generated,
              renewable-content: renewable-content,
              last-updated: block-height
            }
          )
          (ok true)
        )
    )
  )
)

;; ==========================
;; Read-only functions
;; ==========================

(define-read-only (get-passport (id uint))
  (match (map-get? passports { id: id })
    passport (ok passport)
    ERR-NOT-FOUND
  )
)

(define-read-only (get-passport-metadata (id uint))
  (match (map-get? passport-metadata { id: id })
    metadata (ok metadata)
    ERR-NOT-FOUND
  )
)

(define-read-only (get-compliance-record (passport-id uint) (record-id uint))
  (match (map-get? compliance-records { passport-id: passport-id, record-id: record-id })
    record (ok record)
    ERR-NOT-FOUND
  )
)

(define-read-only (get-sustainability-metrics (id uint))
  (match (map-get? sustainability-metrics { id: id })
    metrics (ok metrics)
    ERR-NOT-FOUND
  )
)

(define-read-only (get-compliance-count (passport-id uint))
  (ok (default-to u0 (get count (map-get? compliance-counters { passport-id: passport-id }))))
)

(define-read-only (is-compliant (id uint))
  (match (map-get? passports { id: id })
    passport (ok (is-eq (get compliance-status passport) STATUS-APPROVED))
    ERR-NOT-FOUND
  )
)

(define-read-only (get-carbon-footprint (id uint))
  (match (map-get? passports { id: id })
    passport (ok (get carbon-footprint passport))
    ERR-NOT-FOUND
  )
)

(define-read-only (get-recyclability-score (id uint))
  (match (map-get? passports { id: id })
    passport (ok (get recyclability-score passport))
    ERR-NOT-FOUND
  )
)
