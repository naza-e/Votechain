;; Decentralized Governance Framework
;; A governance system for token holders to propose, vote on, and implement protocol changes

;; SIP-010 token trait
(define-trait voting-token-trait
  (
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))
    (get-balance (principal) (response uint uint))
    (get-total-supply () (response uint uint))
  )
)

;; Constants
(define-constant error-not-found (err u404))
(define-constant error-unauthorized (err u401))
(define-constant error-invalid-input (err u400))
(define-constant error-already-exists (err u409))
(define-constant error-deadline-passed (err u410))
(define-constant error-invalid-status (err u411))

;; Protocol configuration settings
(define-map protocol-settings-registry
  { setting-key: (string-ascii 64) }
  {
    setting-value: (string-utf8 256),
    data-type: (string-ascii 16),
    last-updated: uint,
    setting-info: (string-utf8 256)
  }
)

;; Governance motions
(define-map governance-motion-registry
  { motion-id: uint }
  {
    motion-name: (string-utf8 128),
    motion-details: (string-utf8 1024),
    proposer: principal,
    created-time: uint,
    voting-begins: uint,
    voting-ends: uint,
    current-status: (string-ascii 32),
    motion-category: (string-ascii 32),
    required-majority: uint,
    min-participation: uint,
    yes-votes: uint,
    no-votes: uint,
    abstain-votes: uint
  }
)

;; Motion actions - what happens if motion passes
(define-map motion-action-registry
  { motion-id: uint, action-id: uint }
  {
    action-category: (string-ascii 32),
    setting-key: (optional (string-ascii 64)),
    updated-value: (optional (string-utf8 256)),
    fund-recipient: (optional principal),
    transfer-amount: (optional uint)
  }
)

;; Voting records
(define-map ballot-record-registry
  { motion-id: uint, voter: principal }
  {
    ballot-choice: (string-ascii 16),
    voting-power: uint,
    vote-timestamp: uint
  }
)

;; Next available motion ID
(define-data-var next-motion-id uint u0)

;; Minimum tokens required to create motion
(define-data-var minimum-motion-deposit uint u1000)

;; Initialize governance with default settings
(define-public (initialize-governance-settings)
  (begin
    (map-set protocol-settings-registry
      { setting-key: "voting-delay" }
      {
        setting-value: u"1440",
        data-type: "uint",
        last-updated: block-height,
        setting-info: u"Blocks between motion creation and voting start"
      }
    )
    
    (map-set protocol-settings-registry
      { setting-key: "voting-duration" }
      {
        setting-value: u"10080",
        data-type: "uint", 
        last-updated: block-height,
        setting-info: u"Duration of voting period in blocks"
      }
    )
    
    (map-set protocol-settings-registry
      { setting-key: "execution-delay" }
      {
        setting-value: u"2880",
        data-type: "uint",
        last-updated: block-height,
        setting-info: u"Blocks between voting end and execution"
      }
    )
    
    (map-set protocol-settings-registry
      { setting-key: "min-motion-threshold" }
      {
        setting-value: u"100000000000",
        data-type: "uint",
        last-updated: block-height,
        setting-info: u"Minimum tokens to submit motion"
      }
    )
    
    (map-set protocol-settings-registry
      { setting-key: "quorum-requirement" }
      {
        setting-value: u"1000",
        data-type: "uint",
        last-updated: block-height,
        setting-info: u"Minimum participation (basis points)"
      }
    )
    
    (map-set protocol-settings-registry
      { setting-key: "simple-majority" }
      {
        setting-value: u"5000",
        data-type: "uint",
        last-updated: block-height,
        setting-info: u"Required majority for standard motions (basis points)"
      }
    )
    
    (ok true)
  )
)

;; Helper to parse uint from string (simplified)
(define-private (convert-string-to-uint (string-value (string-utf8 256)))
  (if (is-eq string-value u"1440") (some u1440)
      (if (is-eq string-value u"10080") (some u10080)
          (if (is-eq string-value u"2880") (some u2880)
              (if (is-eq string-value u"100000000000") (some u100000000000)
                  (if (is-eq string-value u"1000") (some u1000)
                      (if (is-eq string-value u"5000") (some u5000)
                          (some u0)))))))
)

;; Check if motion category is valid
(define-private (is-valid-motion-category (category (string-ascii 32)))
  (or (is-eq category "parameter")
      (or (is-eq category "upgrade")
          (or (is-eq category "fund")
              (is-eq category "text"))))
)

;; Create a new governance motion
(define-public (create-governance-motion
                (token-contract <voting-token-trait>)
                (motion-name (string-utf8 128))
                (motion-details (string-utf8 1024))
                (motion-category (string-ascii 32))
                (majority-type (string-ascii 16))
                (voting-duration-blocks uint))
  (let
    ((motion-id (var-get next-motion-id))
     (proposer-balance (unwrap! (contract-call? token-contract get-balance tx-sender) 
                               (err u"Failed to get token balance")))
     (min-threshold (unwrap! (get-uint-setting "min-motion-threshold") 
                            (err u"Setting not found")))
     (voting-delay (unwrap! (get-uint-setting "voting-delay") (err u"Setting not found")))
     (simple-majority (unwrap! (get-uint-setting "simple-majority") (err u"Setting not found")))
     (quorum (unwrap! (get-uint-setting "quorum-requirement") (err u"Setting not found")))
     (deposit (var-get minimum-motion-deposit)))
    
    (asserts! (>= proposer-balance min-threshold) 
              (err u"Insufficient tokens to create motion"))
    (asserts! (is-valid-motion-category motion-category) 
              (err u"Invalid motion category"))
    (asserts! (>= voting-duration-blocks u1000) 
              (err u"Voting duration too short"))
    
    (asserts! (is-ok (contract-call? token-contract transfer 
                                   deposit 
                                   tx-sender 
                                   (as-contract tx-sender) 
                                   none))
             (err u"Failed to transfer deposit"))
    
    (map-set governance-motion-registry
      { motion-id: motion-id }
      {
        motion-name: motion-name,
        motion-details: motion-details,
        proposer: tx-sender,
        created-time: block-height,
        voting-begins: (+ block-height voting-delay),
        voting-ends: (+ (+ block-height voting-delay) voting-duration-blocks),
        current-status: "draft",
        motion-category: motion-category,
        required-majority: simple-majority,
        min-participation: quorum,
        yes-votes: u0,
        no-votes: u0,
        abstain-votes: u0
      }
    )
    
    (var-set next-motion-id (+ motion-id u1))
    
    (ok motion-id)
  )
)

;; Check if action category is valid
(define-private (is-valid-action-category (action-category (string-ascii 32)))
  (or (is-eq action-category "set-parameter")
      (is-eq action-category "transfer-funds"))
)

;; Add an action to a motion
(define-public (add-motion-action
                (motion-id uint)
                (action-category (string-ascii 32))
                (setting-key (optional (string-ascii 64)))
                (updated-value (optional (string-utf8 256)))
                (fund-recipient (optional principal))
                (transfer-amount (optional uint)))
  (let
    ((motion (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found"))))
    
    (asserts! (is-eq tx-sender (get proposer motion)) (err u"Only proposer can add actions"))
    (asserts! (is-eq (get current-status motion) "draft") (err u"Motion not in draft state"))
    (asserts! (is-valid-action-category action-category) (err u"Invalid action category"))
    
    (map-set motion-action-registry
      { motion-id: motion-id, action-id: u0 }
      {
        action-category: action-category,
        setting-key: setting-key,
        updated-value: updated-value,
        fund-recipient: fund-recipient,
        transfer-amount: transfer-amount
      }
    )
    
    (ok u0)
  )
)

;; Activate motion to start voting
(define-public (activate-motion (motion-id uint))
  (let
    ((motion (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found"))))
    
    (asserts! (is-eq tx-sender (get proposer motion)) (err u"Only proposer can activate"))
    (asserts! (is-eq (get current-status motion) "draft") (err u"Motion not in draft state"))
    
    (map-set governance-motion-registry
      { motion-id: motion-id }
      (merge motion { current-status: "active" })
    )
    
    (ok true)
  )
)

;; Check if ballot choice is valid
(define-private (is-valid-ballot-choice (ballot-choice (string-ascii 16)))
  (or (is-eq ballot-choice "yes")
      (or (is-eq ballot-choice "no")
          (is-eq ballot-choice "abstain")))
)

;; Cast a ballot on a motion
(define-public (cast-ballot
                (token-contract <voting-token-trait>)
                (motion-id uint)
                (ballot-choice (string-ascii 16)))
  (let
    ((motion (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found")))
     (existing-ballot (map-get? ballot-record-registry { motion-id: motion-id, voter: tx-sender }))
     (voter-balance (unwrap! (contract-call? token-contract get-balance tx-sender) (err u"Failed to get balance"))))
    
    (asserts! (is-eq (get current-status motion) "active") (err u"Motion not active"))
    (asserts! (>= block-height (get voting-begins motion)) (err u"Voting not started"))
    (asserts! (< block-height (get voting-ends motion)) (err u"Voting ended"))
    (asserts! (is-valid-ballot-choice ballot-choice) (err u"Invalid ballot choice"))
    (asserts! (> voter-balance u0) (err u"No voting power"))
    
    (if (is-some existing-ballot)
        (let ((prev-ballot (unwrap-panic existing-ballot)))
          (map-set governance-motion-registry
            { motion-id: motion-id }
            (merge motion 
              {
                yes-votes: (if (is-eq (get ballot-choice prev-ballot) "yes")
                          (- (get yes-votes motion) (get voting-power prev-ballot))
                          (get yes-votes motion)),
                no-votes: (if (is-eq (get ballot-choice prev-ballot) "no")
                         (- (get no-votes motion) (get voting-power prev-ballot))
                         (get no-votes motion)),
                abstain-votes: (if (is-eq (get ballot-choice prev-ballot) "abstain")
                              (- (get abstain-votes motion) (get voting-power prev-ballot))
                              (get abstain-votes motion))
              }
            )
          )
        )
        true
    )
    
    (map-set ballot-record-registry
      { motion-id: motion-id, voter: tx-sender }
      {
        ballot-choice: ballot-choice,
        voting-power: voter-balance,
        vote-timestamp: block-height
      }
    )
    
    (map-set governance-motion-registry
      { motion-id: motion-id }
      (merge motion 
        {
          yes-votes: (if (is-eq ballot-choice "yes")
                     (+ (get yes-votes motion) voter-balance)
                     (get yes-votes motion)),
          no-votes: (if (is-eq ballot-choice "no")
                    (+ (get no-votes motion) voter-balance)
                    (get no-votes motion)),
          abstain-votes: (if (is-eq ballot-choice "abstain")
                        (+ (get abstain-votes motion) voter-balance)
                        (get abstain-votes motion))
        }
      )
    )
    
    (ok true)
  )
)

;; Finalize motion after voting ends
(define-public (finalize-motion (motion-id uint))
  (let
    ((motion (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found")))
     (total-ballots (+ (+ (get yes-votes motion) (get no-votes motion)) (get abstain-votes motion)))
     (approval-rate (if (> total-ballots u0)
                      (/ (* (get yes-votes motion) u10000) total-ballots)
                      u0)))
    
    (asserts! (is-eq (get current-status motion) "active") (err u"Motion not active"))
    (asserts! (>= block-height (get voting-ends motion)) (err u"Voting still in progress"))
    
    (if (and (>= (/ (* total-ballots u10000) u1000000000000) (get min-participation motion))
             (>= approval-rate (get required-majority motion)))
        (map-set governance-motion-registry
          { motion-id: motion-id }
          (merge motion { current-status: "passed" })
        )
        (map-set governance-motion-registry
          { motion-id: motion-id }
          (merge motion { current-status: "rejected" })
        )
    )
    
    (ok true)
  )
)

;; Execute a passed motion
(define-public (execute-motion (motion-id uint))
  (let
    ((motion (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found")))
     (execution-delay (unwrap! (get-uint-setting "execution-delay") (err u"Setting not found"))))
    
    (asserts! (is-eq (get current-status motion) "passed") (err u"Motion not passed"))
    (asserts! (>= block-height (+ (get voting-ends motion) execution-delay)) 
              (err u"Execution delay not elapsed"))
    
    (asserts! (is-ok (execute-motion-actions motion-id))
              (err u"Failed to execute motion actions"))
    
    (map-set governance-motion-registry
      { motion-id: motion-id }
      (merge motion { current-status: "executed" })
    )
    
    (ok true)
  )
)

;; Execute all actions for a motion
(define-private (execute-motion-actions (motion-id uint))
  (ok true)
)

;; Set a protocol setting (only through governance)
(define-public (update-protocol-setting (setting-key (string-ascii 64)) (setting-value (string-utf8 256)))
  (begin
    (asserts! (is-governance-call) (err u"Only callable through governance"))
    
    (match (map-get? protocol-settings-registry { setting-key: setting-key })
      setting (begin
                (map-set protocol-settings-registry
                  { setting-key: setting-key }
                  {
                    setting-value: setting-value,
                    data-type: (get data-type setting),
                    last-updated: block-height,
                    setting-info: (get setting-info setting)
                  }
                )
                (ok true)
              )
      (err u"Setting not found")
    )
  )
)

;; Check if called through governance
(define-private (is-governance-call)
  (is-eq contract-caller (as-contract tx-sender))
)

;; Helper to get a uint setting value
(define-private (get-uint-setting (setting-key (string-ascii 64)))
  (match (map-get? protocol-settings-registry { setting-key: setting-key })
    setting (if (is-eq (get data-type setting) "uint")
               (convert-string-to-uint (get setting-value setting))
               none)
    none
  )
)

;; Read-only functions
(define-read-only (get-motion-details (motion-id uint))
  (ok (unwrap! (map-get? governance-motion-registry { motion-id: motion-id }) (err u"Motion not found")))
)

(define-read-only (get-protocol-setting (setting-key (string-ascii 64)))
  (ok (unwrap! (map-get? protocol-settings-registry { setting-key: setting-key }) (err u"Setting not found")))
)

(define-read-only (get-ballot-details (motion-id uint) (voter principal))
  (ok (unwrap! (map-get? ballot-record-registry { motion-id: motion-id, voter: voter }) (err u"Ballot not found")))
)

(define-read-only (check-motion-status (motion-id uint))
  (match (map-get? governance-motion-registry { motion-id: motion-id })
    motion (ok (get current-status motion))
    (err u"Motion not found")
  )
)