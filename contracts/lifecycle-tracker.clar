;; lifecycle-tracker.clar
;; Lifecycle tracking for materials in a circular economy.
;; No cross-contract calls. No traits.

;; ==========================
;; Constants and error codes
;; ==========================

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-EXISTS (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-STATE (err u103))
(define-constant ERR-OWNER-MISMATCH (err u104))
(define-constant ERR-INPUT (err u105))

;; Lifecycle stages
(define-constant STAGE-CREATED u1)
(define-constant STAGE-IN-USE u2)
(define-constant STAGE-RECYCLED u3)
(define-constant STAGE-DISPOSED u4)

;; ==========================
;; Data types
;; ==========================

(define-data-var admin principal tx-sender)

(define-map materials
  { id: uint }
  {
    owner: principal,
    stage: uint,
    quality: uint,
    cycles: uint,
    created-at: uint,
    updated-at: uint
  }
)

(define-map history
  { id: uint, entry: uint }
  {
    actor: principal,
    stage: uint,
    note: (optional (string-ascii 200)),
    quality: uint,
    timestamp: uint
  }
)

;; Individual counter maps for each material
(define-map history-counters { id: uint } { count: uint })

;; ==========================
;; Utilities
;; ==========================

(define-read-only (get-admin)
  (ok (var-get admin))
)

(define-private (is-admin (who principal))
  (is-eq who (var-get admin))
)

(define-read-only (material-exists (id uint))
  (is-some (map-get? materials { id: id }))
)

(define-read-only (get-material (id uint))
  (match (map-get? materials { id: id })
    material (ok material)
    (err u404)
  )
)

(define-private (next-history-entry (id uint))
  (let ((current (default-to u0 (get count (map-get? history-counters { id: id })))))
    (begin
      (map-set history-counters { id: id } { count: (+ current u1) })
      (+ current u1)
    )
  )
)

(define-private (now)
  ;; Clarinet provides block-height/time in tests; we store block-height as time surrogate
  block-height
)

;; ==========================
;; Admin controls
;; ==========================

(define-public (set-admin (new-admin principal))
  (begin
    (if (not (is-admin tx-sender))
        ERR-NOT-AUTHORIZED
        (begin
          (var-set admin new-admin)
          (ok true)
        )
    )
  )
)

;; ==========================
;; Registration and updates
;; ==========================

(define-public (register-material (id uint) (owner principal) (quality uint) (note (optional (string-ascii 200))))
  (begin
    (if (or (<= id u0) (<= quality u0))
        ERR-INPUT
        (if (is-some (map-get? materials { id: id }))
            ERR-ALREADY-EXISTS
            (begin
              (map-set materials { id: id }
                {
                  owner: owner,
                  stage: STAGE-CREATED,
                  quality: quality,
                  cycles: u0,
                  created-at: (now),
                  updated-at: (now)
                }
              )
              (let ((entry (next-history-entry id)))
                (map-set history { id: id, entry: entry }
                  {
                    actor: tx-sender,
                    stage: STAGE-CREATED,
                    note: note,
                    quality: quality,
                    timestamp: (now)
                  }
                )
              )
              (ok true)
            )
        )
    )
  )
)

(define-public (transfer-ownership (id uint) (new-owner principal) (note (optional (string-ascii 200))))
  (match (map-get? materials { id: id })
    material
      (let ((current-owner (get owner material)))
        (if (is-eq tx-sender current-owner)
            (begin
              (map-set materials { id: id }
                (merge material { owner: new-owner, updated-at: (now) })
              )
              (let ((entry (next-history-entry id)))
                (map-set history { id: id, entry: entry }
                  { actor: tx-sender, stage: (get stage material), note: note, quality: (get quality material), timestamp: (now) }
                )
              )
              (ok true)
            )
            ERR-OWNER-MISMATCH
        )
      )
    ERR-NOT-FOUND
  )
)

(define-public (update-quality (id uint) (new-quality uint) (note (optional (string-ascii 200))))
  (match (map-get? materials { id: id })
    material
      (if (> new-quality u0)
          (begin
            (map-set materials { id: id } (merge material { quality: new-quality, updated-at: (now) }))
            (let ((entry (next-history-entry id)))
              (map-set history { id: id, entry: entry }
                { actor: tx-sender, stage: (get stage material), note: note, quality: new-quality, timestamp: (now) }
              )
            )
            (ok true)
          )
          ERR-INPUT
      )
    ERR-NOT-FOUND
  )
)

(define-private (set-stage (material { owner: principal, stage: uint, quality: uint, cycles: uint, created-at: uint, updated-at: uint }) (new-stage uint))
  (merge material { stage: new-stage, updated-at: (now) })
)

(define-public (advance-to-in-use (id uint) (note (optional (string-ascii 200))))
  (match (map-get? materials { id: id })
    material
      (if (is-eq (get stage material) STAGE-CREATED)
          (begin
            (let ((updated (set-stage material STAGE-IN-USE)))
              (map-set materials { id: id } updated)
              (let ((entry (next-history-entry id)))
                (map-set history { id: id, entry: entry }
                  { actor: tx-sender, stage: STAGE-IN-USE, note: note, quality: (get quality updated), timestamp: (now) }
                )
              )
              (ok true)
            )
          )
          ERR-INVALID-STATE
      )
    ERR-NOT-FOUND
  )
)

(define-public (mark-recycled (id uint) (quality-after uint) (note (optional (string-ascii 200))))
  (match (map-get? materials { id: id })
    material
      (if (and (is-eq (get stage material) STAGE-IN-USE) (> quality-after u0))
          (begin
            (let ((updated (merge (set-stage material STAGE-RECYCLED)
                                  { cycles: (+ (get cycles material) u1), quality: quality-after })))
              (map-set materials { id: id } updated)
              (let ((entry (next-history-entry id)))
                (map-set history { id: id, entry: entry }
                  { actor: tx-sender, stage: STAGE-RECYCLED, note: note, quality: quality-after, timestamp: (now) }
                )
              )
              (ok true)
            )
          )
          ERR-INVALID-STATE
      )
    ERR-NOT-FOUND
  )
)

(define-public (mark-disposed (id uint) (note (optional (string-ascii 200))))
  (match (map-get? materials { id: id })
    material
      (if (or (is-eq (get stage material) STAGE-IN-USE)
              (is-eq (get stage material) STAGE-RECYCLED))
          (begin
            (let ((updated (set-stage material STAGE-DISPOSED)))
              (map-set materials { id: id } updated)
              (let ((entry (next-history-entry id)))
                (map-set history { id: id, entry: entry }
                  { actor: tx-sender, stage: STAGE-DISPOSED, note: note, quality: (get quality updated), timestamp: (now) }
                )
              )
              (ok true)
            )
          )
          ERR-INVALID-STATE
      )
    ERR-NOT-FOUND
  )
)

;; ==========================
;; Read-only queries
;; ==========================

(define-read-only (get-stage (id uint))
  (match (map-get? materials { id: id })
    material (ok (get stage material))
    (err u404)
  )
)

(define-read-only (get-owner (id uint))
  (match (map-get? materials { id: id })
    material (ok (get owner material))
    (err u404)
  )
)

(define-read-only (get-quality (id uint))
  (match (map-get? materials { id: id })
    material (ok (get quality material))
    (err u404)
  )
)

(define-read-only (get-cycles (id uint))
  (match (map-get? materials { id: id })
    material (ok (get cycles material))
    (err u404)
  )
)

(define-read-only (get-history-entry (id uint) (entry uint))
  (match (map-get? history { id: id, entry: entry })
    rec (ok rec)
    (err u404)
  )
)

(define-read-only (get-history-length (id uint))
  (ok (default-to u0 (get count (map-get? history-counters { id: id }))))
)
