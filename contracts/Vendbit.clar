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
(define-constant ERR_SUBSCRIPTION_NOT_FOUND (err u109))
(define-constant ERR_SUBSCRIPTION_ALREADY_EXISTS (err u110))
(define-constant ERR_SUBSCRIPTION_INACTIVE (err u111))
(define-constant ERR_SUBSCRIPTION_EXPIRED (err u112))
(define-constant ERR_INVALID_INTERVAL (err u113))
(define-constant ERR_INVALID_DURATION (err u114))
(define-constant ERR_AUTO_RENEWAL_FAILED (err u115))
(define-constant PLATFORM_FEE u25)
(define-constant MIN_PAYMENT u1000000)
(define-constant MAX_PAYMENT u1000000000000)
(define-constant MIN_SUBSCRIPTION_INTERVAL u144)
(define-constant MAX_SUBSCRIPTION_INTERVAL u52560)
(define-constant SUBSCRIPTION_GRACE_PERIOD u1008)

(define-data-var contract-enabled bool true)
(define-data-var total-vendors uint u0)
(define-data-var total-payments uint u0)
(define-data-var total-volume uint u0)
(define-data-var platform-treasury uint u0)
(define-data-var total-subscriptions uint u0)
(define-data-var total-subscription-revenue uint u0)

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

(define-map subscription-plans
  { vendor: principal, plan-id: uint }
  {
    name: (string-ascii 50),
    description: (string-ascii 200),
    price: uint,
    interval-blocks: uint,
    max-subscribers: uint,
    current-subscribers: uint,
    is-active: bool,
    created-at: uint
  }
)

(define-map user-subscriptions
  { subscriber: principal, vendor: principal, plan-id: uint }
  {
    subscription-id: uint,
    start-block: uint,
    end-block: uint,
    next-payment-block: uint,
    last-payment-block: uint,
    total-payments: uint,
    status: (string-ascii 20),
    auto-renew: bool
  }
)

(define-map subscription-payments
  { subscription-id: uint, payment-number: uint }
  {
    subscriber: principal,
    vendor: principal,
    amount: uint,
    fee: uint,
    payment-block: uint,
    status: (string-ascii 20)
  }
)

(define-map vendor-plan-counters
  { vendor: principal }
  { next-plan-id: uint }
)

(define-map subscription-counters
  { counter-id: uint }
  { next-subscription-id: uint }
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

(define-public (create-subscription-plan (name (string-ascii 50)) (description (string-ascii 200)) (price uint) (interval-blocks uint) (max-subscribers uint))
  (let (
    (vendor tx-sender)
    (current-counter (default-to { next-plan-id: u1 } (map-get? vendor-plan-counters { vendor: vendor })))
    (plan-id (get next-plan-id current-counter))
    (current-block stacks-block-height)
  )
    (asserts! (is-some (map-get? vendors { vendor-id: vendor })) ERR_VENDOR_NOT_FOUND)
    (asserts! (>= interval-blocks MIN_SUBSCRIPTION_INTERVAL) ERR_INVALID_INTERVAL)
    (asserts! (<= interval-blocks MAX_SUBSCRIPTION_INTERVAL) ERR_INVALID_INTERVAL)
    (asserts! (>= price MIN_PAYMENT) ERR_INVALID_PAYMENT)
    (asserts! (<= price MAX_PAYMENT) ERR_INVALID_PAYMENT)
    (asserts! (> max-subscribers u0) ERR_INVALID_PAYMENT)
    (asserts! (> (len name) u0) ERR_INVALID_PAYMENT)
    
    (map-set subscription-plans
      { vendor: vendor, plan-id: plan-id }
      {
        name: name,
        description: description,
        price: price,
        interval-blocks: interval-blocks,
        max-subscribers: max-subscribers,
        current-subscribers: u0,
        is-active: true,
        created-at: current-block
      }
    )
    
    (map-set vendor-plan-counters
      { vendor: vendor }
      { next-plan-id: (+ plan-id u1) }
    )
    
    (ok plan-id)
  )
)

(define-public (subscribe-to-plan (vendor principal) (plan-id uint) (auto-renew bool))
  (let (
    (subscriber tx-sender)
    (plan-info (unwrap! (map-get? subscription-plans { vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
    (current-counter (default-to { next-subscription-id: u1 } (map-get? subscription-counters { counter-id: u0 })))
    (subscription-id (get next-subscription-id current-counter))
    (current-block stacks-block-height)
    (end-block (+ current-block (get interval-blocks plan-info)))
    (next-payment-block (+ current-block (get interval-blocks plan-info)))
    (price (get price plan-info))
    (fee (/ (* price PLATFORM_FEE) u10000))
    (net-amount (- price fee))
    (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
  )
    (asserts! (get is-active plan-info) ERR_SUBSCRIPTION_INACTIVE)
    (asserts! (is-eq (get status vendor-info) "active") ERR_VENDOR_SUSPENDED)
    (asserts! (< (get current-subscribers plan-info) (get max-subscribers plan-info)) ERR_SUBSCRIPTION_ALREADY_EXISTS)
    (asserts! (is-none (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id })) ERR_SUBSCRIPTION_ALREADY_EXISTS)
    
    (try! (stx-transfer? price subscriber (as-contract tx-sender)))
    
    (map-set user-subscriptions
      { subscriber: subscriber, vendor: vendor, plan-id: plan-id }
      {
        subscription-id: subscription-id,
        start-block: current-block,
        end-block: end-block,
        next-payment-block: next-payment-block,
        last-payment-block: current-block,
        total-payments: u1,
        status: "active",
        auto-renew: auto-renew
      }
    )
    
    (map-set subscription-payments
      { subscription-id: subscription-id, payment-number: u1 }
      {
        subscriber: subscriber,
        vendor: vendor,
        amount: price,
        fee: fee,
        payment-block: current-block,
        status: "completed"
      }
    )
    
    (map-set subscription-plans
      { vendor: vendor, plan-id: plan-id }
      (merge plan-info { current-subscribers: (+ (get current-subscribers plan-info) u1) })
    )
    
    (map-set subscription-counters
      { counter-id: u0 }
      { next-subscription-id: (+ subscription-id u1) }
    )
    
    (let (
      (current-balance (default-to { available: u0, pending: u0 } (map-get? vendor-balances { vendor: vendor })))
    )
      (map-set vendor-balances
        { vendor: vendor }
        { 
          available: (+ (get available current-balance) net-amount),
          pending: (get pending current-balance)
        }
      )
    )
    
    (var-set total-subscriptions (+ (var-get total-subscriptions) u1))
    (var-set total-subscription-revenue (+ (var-get total-subscription-revenue) price))
    (var-set platform-treasury (+ (var-get platform-treasury) fee))
    
    (ok subscription-id)
  )
)

(define-public (renew-subscription (subscriber principal) (vendor principal) (plan-id uint))
  (let (
    (subscription-info (unwrap! (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
    (plan-info (unwrap! (map-get? subscription-plans { vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
    (current-block stacks-block-height)
    (subscription-id (get subscription-id subscription-info))
    (price (get price plan-info))
    (fee (/ (* price PLATFORM_FEE) u10000))
    (net-amount (- price fee))
    (new-payment-number (+ (get total-payments subscription-info) u1))
    (vendor-info (unwrap! (map-get? vendors { vendor-id: vendor }) ERR_VENDOR_NOT_FOUND))
  )
    (asserts! (is-eq (get status subscription-info) "active") ERR_SUBSCRIPTION_INACTIVE)
    (asserts! (get is-active plan-info) ERR_SUBSCRIPTION_INACTIVE)
    (asserts! (is-eq (get status vendor-info) "active") ERR_VENDOR_SUSPENDED)
    (asserts! (<= (get next-payment-block subscription-info) (+ current-block SUBSCRIPTION_GRACE_PERIOD)) ERR_SUBSCRIPTION_EXPIRED)
    
    (try! (stx-transfer? price subscriber (as-contract tx-sender)))
    
    (map-set user-subscriptions
      { subscriber: subscriber, vendor: vendor, plan-id: plan-id }
      (merge subscription-info {
        end-block: (+ current-block (get interval-blocks plan-info)),
        next-payment-block: (+ current-block (get interval-blocks plan-info)),
        last-payment-block: current-block,
        total-payments: new-payment-number
      })
    )
    
    (map-set subscription-payments
      { subscription-id: subscription-id, payment-number: new-payment-number }
      {
        subscriber: subscriber,
        vendor: vendor,
        amount: price,
        fee: fee,
        payment-block: current-block,
        status: "completed"
      }
    )
    
    (let (
      (current-balance (default-to { available: u0, pending: u0 } (map-get? vendor-balances { vendor: vendor })))
    )
      (map-set vendor-balances
        { vendor: vendor }
        { 
          available: (+ (get available current-balance) net-amount),
          pending: (get pending current-balance)
        }
      )
    )
    
    (var-set total-subscription-revenue (+ (var-get total-subscription-revenue) price))
    (var-set platform-treasury (+ (var-get platform-treasury) fee))
    
    (ok true)
  )
)

(define-public (cancel-subscription (subscriber principal) (vendor principal) (plan-id uint))
  (let (
    (subscription-info (unwrap! (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
    (plan-info (unwrap! (map-get? subscription-plans { vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
  )
    (asserts! (or (is-eq tx-sender subscriber) (is-eq tx-sender vendor) (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status subscription-info) "active") ERR_SUBSCRIPTION_INACTIVE)
    
    (map-set user-subscriptions
      { subscriber: subscriber, vendor: vendor, plan-id: plan-id }
      (merge subscription-info { status: "cancelled", auto-renew: false })
    )
    
    (map-set subscription-plans
      { vendor: vendor, plan-id: plan-id }
      (merge plan-info { current-subscribers: (- (get current-subscribers plan-info) u1) })
    )
    
    (ok true)
  )
)

(define-public (update-plan-status (plan-id uint) (is-active bool))
  (let (
    (vendor tx-sender)
    (plan-info (unwrap! (map-get? subscription-plans { vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
  )
    (map-set subscription-plans
      { vendor: vendor, plan-id: plan-id }
      (merge plan-info { is-active: is-active })
    )
    
    (ok true)
  )
)

(define-public (process-auto-renewal (subscriber principal) (vendor principal) (plan-id uint))
  (let (
    (subscription-info (unwrap! (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id }) ERR_SUBSCRIPTION_NOT_FOUND))
    (current-block stacks-block-height)
  )
    (asserts! (get auto-renew subscription-info) ERR_AUTO_RENEWAL_FAILED)
    (asserts! (is-eq (get status subscription-info) "active") ERR_SUBSCRIPTION_INACTIVE)
    (asserts! (>= current-block (get next-payment-block subscription-info)) ERR_AUTO_RENEWAL_FAILED)
    
    (match (renew-subscription subscriber vendor plan-id)
      success (ok true)
      error (begin
        (map-set user-subscriptions
          { subscriber: subscriber, vendor: vendor, plan-id: plan-id }
          (merge subscription-info { status: "expired" })
        )
        ERR_AUTO_RENEWAL_FAILED
      )
    )
  )
)

(define-read-only (get-subscription-plan (vendor principal) (plan-id uint))
  (map-get? subscription-plans { vendor: vendor, plan-id: plan-id })
)

(define-read-only (get-user-subscription (subscriber principal) (vendor principal) (plan-id uint))
  (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id })
)

(define-read-only (get-subscription-payment (subscription-id uint) (payment-number uint))
  (map-get? subscription-payments { subscription-id: subscription-id, payment-number: payment-number })
)

(define-read-only (is-subscription-due (subscriber principal) (vendor principal) (plan-id uint))
  (match (map-get? user-subscriptions { subscriber: subscriber, vendor: vendor, plan-id: plan-id })
    subscription-info 
      (and 
        (is-eq (get status subscription-info) "active")
        (>= stacks-block-height (get next-payment-block subscription-info))
      )
    false
  )
)

(define-read-only (get-vendor-plans (vendor principal))
  (let (
    (counter-info (default-to { next-plan-id: u1 } (map-get? vendor-plan-counters { vendor: vendor })))
  )
    (get next-plan-id counter-info)
  )
)

(define-read-only (get-subscription-stats)
  {
    total-subscriptions: (var-get total-subscriptions),
    total-subscription-revenue: (var-get total-subscription-revenue)
  }
)