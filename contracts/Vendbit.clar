(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_VENDOR_NOT_FOUND (err u101))
(define-constant ERR_VENDOR_ALREADY_EXISTS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_INVALID_PAYMENT (err u104))
(define-constant ERR_PAYMENT_NOT_FOUND (err u105))
(define-constant ERR_PAYMENT_ALREADY_SETTLED (err u106))
(define-constant ERR_INVALID_REFUND (err u107))
(define-constant ERR_VENDOR_SUSPENDED (err u108))
(define-constant PLATFORM_FEE u25)
(define-constant MIN_PAYMENT u1000000)
(define-constant MAX_PAYMENT u1000000000000)

(define-data-var contract-enabled bool true)
(define-data-var total-vendors uint u0)
(define-data-var total-payments uint u0)
(define-data-var total-volume uint u0)
(define-data-var platform-treasury uint u0)

(define-map vendors
  { vendor-id: principal }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    qr-code: (string-ascii 100),
    status: (string-ascii 20),
    registration-block: uint,
    total-sales: uint,
    payment-count: uint,
    rating: uint,
    is-verified: bool
  }
)

(define-map payments
  { payment-id: uint }
  {
    vendor: principal,
    customer: principal,
    amount: uint,
    fee: uint,
    description: (string-ascii 100),
    qr-data: (string-ascii 150),
    status: (string-ascii 20),
    timestamp: uint,
    settlement-block: (optional uint)
  }
)

(define-map vendor-balances
  { vendor: principal }
  { available: uint, pending: uint }
)

(define-map customer-payments
  { customer: principal, payment-id: uint }
  { exists: bool }
)

(define-map payment-disputes
  { payment-id: uint }
  {
    disputed-by: principal,
    reason: (string-ascii 200),
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-public (register-vendor (name (string-ascii 50)) (description (string-ascii 200)) (qr-code (string-ascii 100)))
  (let (
    (vendor-id tx-sender)
    (current-block stacks-block-height)
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? vendors { vendor-id: vendor-id })) ERR_VENDOR_ALREADY_EXISTS)
    (asserts! (> (len name) u0) ERR_INVALID_PAYMENT)
    (asserts! (> (len qr-code) u0) ERR_INVALID_PAYMENT)
    
    (map-set vendors
      { vendor-id: vendor-id }
      {
        name: name,
        description: description,
        qr-code: qr-code,
        status: "active",
        registration-block: current-block,
        total-sales: u0,
        payment-count: u0,
        rating: u5000,
        is-verified: false
      }
    )
    
    (map-set vendor-balances
      { vendor: vendor-id }
      { available: u0, pending: u0 }
    )
    
    (var-set total-vendors (+ (var-get total-vendors) u1))
    (ok vendor-id)
  )
)

(define-public (create-payment (vendor principal) (amount uint) (description (string-ascii 100)) (qr-data (string-ascii 150)))
  (let (
    (payment-id (+ (var-get total-payments) u1))
    (fee (/ (* amount PLATFORM_FEE) u10000))
    (net-amount (- amount fee))
    (current-block stacks-block-height)
    (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status vendor-info) "active") ERR_VENDOR_SUSPENDED)
    (asserts! (>= amount MIN_PAYMENT) ERR_INVALID_PAYMENT)
    (asserts! (<= amount MAX_PAYMENT) ERR_INVALID_PAYMENT)
    (asserts! (> (len description) u0) ERR_INVALID_PAYMENT)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set payments
      { payment-id: payment-id }
      {
        vendor: vendor,
        customer: tx-sender,
        amount: amount,
        fee: fee,
        description: description,
        qr-data: qr-data,
        status: "pending",
        timestamp: current-block,
        settlement-block: none
      }
    )
    
    (map-set customer-payments
      { customer: tx-sender, payment-id: payment-id }
      { exists: true }
    )
    
    (let (
      (current-balance (default-to { available: u0, pending: u0 } (map-get? vendor-balances { vendor: vendor })))
    )
      (map-set vendor-balances
        { vendor: vendor }
        { 
          available: (get available current-balance),
          pending: (+ (get pending current-balance) net-amount)
        }
      )
    )
    
    (var-set total-payments payment-id)
    (var-set total-volume (+ (var-get total-volume) amount))
    (var-set platform-treasury (+ (var-get platform-treasury) fee))
    
    (ok payment-id)
  )
)

(define-public (settle-payment (payment-id uint))
  (let (
    (payment-info (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND))
    (vendor (get vendor payment-info))
    (net-amount (- (get amount payment-info) (get fee payment-info)))
    (current-block stacks-block-height)
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment-info) "pending") ERR_PAYMENT_ALREADY_SETTLED)
    (asserts! (is-eq tx-sender vendor) ERR_UNAUTHORIZED)
    
    (let (
      (current-balance (unwrap! (map-get? vendor-balances { vendor: vendor }) ERR_VENDOR_NOT_FOUND))
      (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
    )
      (map-set vendor-balances
        { vendor: vendor }
        {
          available: (+ (get available current-balance) net-amount),
          pending: (- (get pending current-balance) net-amount)
        }
      )
      
      (map-set vendors
        { vendor-id: vendor }
        (merge vendor-info {
          total-sales: (+ (get total-sales vendor-info) (get amount payment-info)),
          payment-count: (+ (get payment-count vendor-info) u1)
        })
      )
    )
    
    (map-set payments
      { payment-id: payment-id }
      (merge payment-info {
        status: "settled",
        settlement-block: (some current-block)
      })
    )
    
    (ok true)
  )
)

(define-public (withdraw-funds (amount uint))
  (let (
    (vendor tx-sender)
    (balance-info (unwrap! (map-get? vendor-balances { vendor: vendor }) ERR_VENDOR_NOT_FOUND))
    (available-balance (get available balance-info))
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (<= amount available-balance) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> amount u0) ERR_INVALID_PAYMENT)
    
    (try! (as-contract (stx-transfer? amount tx-sender vendor)))
    
    (map-set vendor-balances
      { vendor: vendor }
      {
        available: (- available-balance amount),
        pending: (get pending balance-info)
      }
    )
    
    (ok amount)
  )
)

(define-public (refund-payment (payment-id uint))
  (let (
    (payment-info (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND))
    (vendor (get vendor payment-info))
    (customer (get customer payment-info))
    (amount (get amount payment-info))
    (fee (get fee payment-info))
    (net-amount (- amount fee))
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (or (is-eq tx-sender vendor) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment-info) "pending") ERR_INVALID_REFUND)
    
    (try! (as-contract (stx-transfer? amount tx-sender customer)))
    
    (let (
      (current-balance (unwrap! (map-get? vendor-balances { vendor: vendor }) ERR_VENDOR_NOT_FOUND))
    )
      (map-set vendor-balances
        { vendor: vendor }
        {
          available: (get available current-balance),
          pending: (- (get pending current-balance) net-amount)
        }
      )
    )
    
    (map-set payments
      { payment-id: payment-id }
      (merge payment-info { status: "refunded" })
    )
    
    (var-set platform-treasury (- (var-get platform-treasury) fee))
    
    (ok true)
  )
)

(define-public (dispute-payment (payment-id uint) (reason (string-ascii 200)))
  (let (
    (payment-info (unwrap! (map-get? payments { payment-id: payment-id }) ERR_PAYMENT_NOT_FOUND))
    (customer (get customer payment-info))
  )
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    (asserts! (is-eq tx-sender customer) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status payment-info) "pending") ERR_INVALID_PAYMENT)
    (asserts! (> (len reason) u0) ERR_INVALID_PAYMENT)
    
    (map-set payment-disputes
      { payment-id: payment-id }
      {
        disputed-by: customer,
        reason: reason,
        status: "open",
        created-at: stacks-block-height
      }
    )
    
    (ok true)
  )
)

(define-public (update-vendor-status (vendor principal) (new-status (string-ascii 20)))
  (let (
    (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    
    (map-set vendors
      { vendor-id: vendor }
      (merge vendor-info { status: new-status })
    )
    
    (ok true)
  )
)

(define-public (verify-vendor (vendor principal))
  (let (
    (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
  )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    ;; (asserts! (get contract-enabled (var-get contract-enabled)) ERR_UNAUTHORIZED)
    
    (map-set vendors
      { vendor-id: vendor }
      (merge vendor-info { is-verified: true })
    )
    
    (ok true)
  )
)

(define-public (toggle-contract (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (var-set contract-enabled enabled)
    (ok enabled)
  )
)

(define-read-only (get-vendor (vendor-id principal))
  (map-get? vendors { vendor-id: vendor-id })
)

(define-read-only (get-payment (payment-id uint))
  (map-get? payments { payment-id: payment-id })
)

(define-read-only (get-vendor-balance (vendor principal))
  (map-get? vendor-balances { vendor: vendor })
)

(define-read-only (get-payment-dispute (payment-id uint))
  (map-get? payment-disputes { payment-id: payment-id })
)

(define-read-only (is-customer-payment (customer principal) (payment-id uint))
  (is-some (map-get? customer-payments { customer: customer, payment-id: payment-id }))
)

(define-read-only (get-contract-stats)
  {
    total-vendors: (var-get total-vendors),
    total-payments: (var-get total-payments),
    total-volume: (var-get total-volume),
    platform-treasury: (var-get platform-treasury),
    contract-enabled: (var-get contract-enabled)
  }
)

(define-read-only (get-vendor-qr (vendor-id principal))
  (match (map-get? vendors { vendor-id: vendor-id })
    vendor-data (some (get qr-code vendor-data))
    none
  )
)

(define-read-only (calculate-payment-fee (amount uint))
  (/ (* amount PLATFORM_FEE) u10000)
)

(define-read-only (get-net-payment-amount (amount uint))
  (- amount (calculate-payment-fee amount))
)