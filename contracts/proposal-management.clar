;; proposal-management
;; Management system for governance proposals and execution
;; Multi-tiered proposal approval processes

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_PROPOSAL_NOT_FOUND (err u201))
(define-constant ERR_INVALID_PROPOSAL (err u202))
(define-constant ERR_PROPOSAL_EXPIRED (err u203))
(define-constant ERR_ALREADY_EXECUTED (err u204))

;; data vars
(define-data-var next-proposal-id uint u1)
(define-data-var total-proposals uint u0)
(define-data-var min-proposal-threshold uint u1000)

;; data maps
(define-map proposals
    { proposal-id: uint }
    {
        title: (string-ascii 256),
        description: (string-ascii 1024),
        proposer: principal,
        created-at: uint,
        voting-start: uint,
        voting-end: uint,
        status: uint, ;; 0=pending, 1=active, 2=passed, 3=failed, 4=executed
        execution-block: uint
    }
)

(define-map proposal-metadata
    { proposal-id: uint }
    {
        category: (string-ascii 64),
        required-quorum: uint,
        approval-threshold: uint,
        execution-delay: uint
    }
)

;; private functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

;; public functions

;; Create a new proposal
(define-public (create-proposal 
    (title (string-ascii 256))
    (description (string-ascii 1024))
    (category (string-ascii 64))
    (voting-duration uint)
    (required-quorum uint)
    (approval-threshold uint)
)
    (let (
        (proposal-id (var-get next-proposal-id))
        (current-block u1)
        (voting-start (+ current-block u144)) ;; 1 day delay
        (voting-end (+ voting-start voting-duration))
    )
        (asserts! (> voting-duration u0) ERR_INVALID_PROPOSAL)
        (asserts! (> required-quorum u0) ERR_INVALID_PROPOSAL)
        (asserts! (<= approval-threshold u10000) ERR_INVALID_PROPOSAL)
        
        (map-set proposals { proposal-id: proposal-id }
            {
                title: title,
                description: description,
                proposer: tx-sender,
                created-at: current-block,
                voting-start: voting-start,
                voting-end: voting-end,
                status: u0, ;; pending
                execution-block: u0
            }
        )
        
        (map-set proposal-metadata { proposal-id: proposal-id }
            {
                category: category,
                required-quorum: required-quorum,
                approval-threshold: approval-threshold,
                execution-delay: u1440 ;; 10 days
            }
        )
        
        (var-set next-proposal-id (+ proposal-id u1))
        (var-set total-proposals (+ (var-get total-proposals) u1))
        
        (ok proposal-id)
    )
)

;; Activate proposal for voting
(define-public (activate-proposal (proposal-id uint))
    (let (
        (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
    )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status proposal-data) u0) ERR_INVALID_PROPOSAL)
        
        (map-set proposals { proposal-id: proposal-id }
            (merge proposal-data { status: u1 })
        )
        
        (ok true)
    )
)

;; Finalize proposal with results
(define-public (finalize-proposal (proposal-id uint) (passed bool))
    (let (
        (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (new-status (if passed u2 u3))
    )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status proposal-data) u1) ERR_INVALID_PROPOSAL)
        
        (map-set proposals { proposal-id: proposal-id }
            (merge proposal-data { status: new-status })
        )
        
        (ok new-status)
    )
)

;; Execute approved proposal
(define-public (execute-proposal (proposal-id uint))
    (let (
        (proposal-data (unwrap! (map-get? proposals { proposal-id: proposal-id }) ERR_PROPOSAL_NOT_FOUND))
        (current-block u1)
    )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (is-eq (get status proposal-data) u2) ERR_INVALID_PROPOSAL)
        (asserts! (is-eq (get execution-block proposal-data) u0) ERR_ALREADY_EXECUTED)
        
        (map-set proposals { proposal-id: proposal-id }
            (merge proposal-data { 
                status: u4,
                execution-block: current-block
            })
        )
        
        (ok true)
    )
)

;; Get proposal information
(define-read-only (get-proposal-info (proposal-id uint))
    (map-get? proposals { proposal-id: proposal-id })
)

;; Get proposal metadata
(define-read-only (get-proposal-metadata (proposal-id uint))
    (map-get? proposal-metadata { proposal-id: proposal-id })
)

;; Get platform statistics
(define-read-only (get-proposal-stats)
    {
        total-proposals: (var-get total-proposals),
        next-proposal-id: (var-get next-proposal-id),
        min-proposal-threshold: (var-get min-proposal-threshold)
    }
)

;; Update minimum proposal threshold
(define-public (update-min-threshold (new-threshold uint))
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (var-set min-proposal-threshold new-threshold)
        (ok true)
    )
)
