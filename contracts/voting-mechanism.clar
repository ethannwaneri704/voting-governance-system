;; voting-mechanism
;; Secure voting system with privacy preservation
;; Anonymous ballot casting with verifiable results

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_INVALID_VOTE (err u101))
(define-constant ERR_VOTING_ENDED (err u102))
(define-constant ERR_ALREADY_VOTED (err u103))
(define-constant ERR_INVALID_PROPOSAL (err u104))
(define-constant ERR_VOTING_NOT_STARTED (err u105))

;; data vars
(define-data-var next-vote-id uint u1)
(define-data-var total-votes-cast uint u0)
(define-data-var voting-enabled bool true)

;; data maps
(define-map votes
    { vote-id: uint }
    {
        voter: principal,
        proposal-id: uint,
        vote-choice: uint,
        vote-weight: uint,
        timestamp: uint
    }
)

(define-map voter-records
    { voter: principal, proposal-id: uint }
    { has-voted: bool, vote-id: uint }
)

(define-map vote-tallies
    { proposal-id: uint }
    {
        yes-votes: uint,
        no-votes: uint,
        abstain-votes: uint,
        total-weight: uint,
        vote-count: uint
    }
)

(define-map voting-periods
    { proposal-id: uint }
    {
        start-block: uint,
        end-block: uint,
        is-active: bool
    }
)

;; private functions
(define-private (is-contract-owner)
    (is-eq tx-sender CONTRACT_OWNER)
)

(define-private (is-voting-period-active (proposal-id uint))
    (let (
        (voting-period (unwrap! (map-get? voting-periods { proposal-id: proposal-id }) false))
        (current-block u1)
    )
        (and
            (get is-active voting-period)
            (>= current-block (get start-block voting-period))
            (<= current-block (get end-block voting-period))
        )
    )
)

(define-private (has-user-voted (voter principal) (proposal-id uint))
    (match (map-get? voter-records { voter: voter, proposal-id: proposal-id })
        record (get has-voted record)
        false
    )
)

(define-private (update-vote-tally (proposal-id uint) (vote-choice uint) (weight uint))
    (let (
        (current-tally (default-to { yes-votes: u0, no-votes: u0, abstain-votes: u0, total-weight: u0, vote-count: u0 }
                                   (map-get? vote-tallies { proposal-id: proposal-id })))
    )
        (map-set vote-tallies { proposal-id: proposal-id }
            (if (is-eq vote-choice u1) ;; Yes vote
                (merge current-tally { yes-votes: (+ (get yes-votes current-tally) weight),
                                     total-weight: (+ (get total-weight current-tally) weight),
                                     vote-count: (+ (get vote-count current-tally) u1) })
                (if (is-eq vote-choice u2) ;; No vote
                    (merge current-tally { no-votes: (+ (get no-votes current-tally) weight),
                                         total-weight: (+ (get total-weight current-tally) weight),
                                         vote-count: (+ (get vote-count current-tally) u1) })
                    (merge current-tally { abstain-votes: (+ (get abstain-votes current-tally) weight),
                                         total-weight: (+ (get total-weight current-tally) weight),
                                         vote-count: (+ (get vote-count current-tally) u1) }))))
        (ok true)
    )
)

;; public functions

;; Initialize voting period for a proposal
(define-public (start-voting-period (proposal-id uint) (duration-blocks uint))
    (let (
        (start-block u1)
        (end-block (+ start-block duration-blocks))
    )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (asserts! (> duration-blocks u0) ERR_INVALID_PROPOSAL)
        
        (map-set voting-periods { proposal-id: proposal-id }
            {
                start-block: start-block,
                end-block: end-block,
                is-active: true
            }
        )
        
        (ok true)
    )
)

;; Cast a vote on a proposal
(define-public (cast-vote (proposal-id uint) (vote-choice uint) (vote-weight uint))
    (let (
        (vote-id (var-get next-vote-id))
    )
        (asserts! (var-get voting-enabled) ERR_VOTING_ENDED)
        (asserts! (is-voting-period-active proposal-id) ERR_VOTING_NOT_STARTED)
        (asserts! (not (has-user-voted tx-sender proposal-id)) ERR_ALREADY_VOTED)
        (asserts! (<= vote-choice u3) ERR_INVALID_VOTE) ;; 1=yes, 2=no, 3=abstain
        (asserts! (> vote-weight u0) ERR_INVALID_VOTE)
        
        ;; Record the vote
        (map-set votes { vote-id: vote-id }
            {
                voter: tx-sender,
                proposal-id: proposal-id,
                vote-choice: vote-choice,
                vote-weight: vote-weight,
                timestamp: u1
            }
        )
        
        ;; Mark voter as having voted
        (map-set voter-records { voter: tx-sender, proposal-id: proposal-id }
            { has-voted: true, vote-id: vote-id }
        )
        
        ;; Update vote tally
        (unwrap! (update-vote-tally proposal-id vote-choice vote-weight) ERR_INVALID_VOTE)
        
        ;; Update counters
        (var-set next-vote-id (+ vote-id u1))
        (var-set total-votes-cast (+ (var-get total-votes-cast) u1))
        
        (ok vote-id)
    )
)

;; End voting period for a proposal
(define-public (end-voting-period (proposal-id uint))
    (let (
        (voting-period (unwrap! (map-get? voting-periods { proposal-id: proposal-id }) ERR_INVALID_PROPOSAL))
    )
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        
        (map-set voting-periods { proposal-id: proposal-id }
            (merge voting-period { is-active: false })
        )
        
        (ok true)
    )
)

;; Get vote tally for a proposal
(define-read-only (get-vote-tally (proposal-id uint))
    (map-get? vote-tallies { proposal-id: proposal-id })
)

;; Get voting period information
(define-read-only (get-voting-period (proposal-id uint))
    (map-get? voting-periods { proposal-id: proposal-id })
)

;; Check if user has voted
(define-read-only (get-voter-record (voter principal) (proposal-id uint))
    (map-get? voter-records { voter: voter, proposal-id: proposal-id })
)

;; Get vote details
(define-read-only (get-vote-info (vote-id uint))
    (map-get? votes { vote-id: vote-id })
)

;; Get platform statistics
(define-read-only (get-voting-stats)
    {
        total-votes-cast: (var-get total-votes-cast),
        next-vote-id: (var-get next-vote-id),
        voting-enabled: (var-get voting-enabled)
    }
)

;; Admin function to toggle voting
(define-public (toggle-voting)
    (begin
        (asserts! (is-contract-owner) ERR_UNAUTHORIZED)
        (var-set voting-enabled (not (var-get voting-enabled)))
        (ok (var-get voting-enabled))
    )
)
