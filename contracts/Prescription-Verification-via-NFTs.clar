(define-trait nft-trait (
    (transfer
        (uint principal principal)
        (response bool uint)
    )
    (get-owner
        (uint)
        (response principal uint)
    )
    (get-last-token-id
        ()
        (response uint uint)
    )
    (get-token-uri
        (uint)
        (response (optional (string-ascii 256)) uint)
    )
))

(define-non-fungible-token prescription-nft uint)

(define-map prescriptions
    { id: uint }
    {
        doctor: principal,
        patient: principal,
        drug-name: (string-ascii 64),
        dosage: (string-ascii 32),
        quantity: uint,
        issue-date: uint,
        expiry-date: uint,
        filled: bool,
        pharmacy: (optional principal),
        max-refills: uint,
        remaining-quantity: uint,
        revoked: bool,
        revocation-reason: (optional (string-ascii 100)),
    }
)

(define-data-var last-prescription-id uint u0)
(define-data-var audit-entry-id uint u0)

(define-map authorized-doctors
    { doctor: principal }
    bool
)
(define-map authorized-pharmacies
    { pharmacy: principal }
    bool
)

(define-map audit-trail
    { entry-id: uint }
    {
        prescription-id: uint,
        action: (string-ascii 20),
        actor: principal,
        timestamp: uint,
        details: (string-ascii 100),
    }
)

(define-map prescription-delegates
    {
        prescription-id: uint,
        delegate: principal,
    }
    {
        delegator: principal,
        granted-at: uint,
        active: bool,
    }
)

(define-constant err-not-authorized (err u100))
(define-constant err-invalid-prescription (err u101))
(define-constant err-already-filled (err u102))
(define-constant err-expired (err u103))
(define-constant err-invalid-quantity (err u104))
(define-constant err-invalid-validity (err u105))
(define-constant err-insufficient-quantity (err u106))
(define-constant err-no-refills-remaining (err u107))
(define-constant err-not-owner (err u108))
(define-constant err-transfer-to-self (err u109))
(define-constant err-already-revoked (err u110))
(define-constant err-cannot-revoke-filled (err u111))
(define-constant err-already-delegated (err u112))
(define-constant err-not-delegated (err u113))
(define-constant err-delegation-to-self (err u114))

(define-public (authorize-doctor (doctor principal))
    (begin
        (map-set authorized-doctors { doctor: doctor } true)
        (ok true)
    )
)

(define-public (authorize-pharmacy (pharmacy principal))
    (begin
        (map-set authorized-pharmacies { pharmacy: pharmacy } true)
        (ok true)
    )
)

(define-read-only (is-doctor (sender principal))
    (default-to false (map-get? authorized-doctors { doctor: sender }))
)

(define-read-only (is-pharmacy (sender principal))
    (default-to false (map-get? authorized-pharmacies { pharmacy: sender }))
)

(define-private (log-audit-entry
        (prescription-id uint)
        (action (string-ascii 20))
        (details (string-ascii 100))
    )
    (let ((entry-id (+ (var-get audit-entry-id) u1)))
        (map-set audit-trail { entry-id: entry-id } {
            prescription-id: prescription-id,
            action: action,
            actor: tx-sender,
            timestamp: stacks-block-height,
            details: details,
        })
        (var-set audit-entry-id entry-id)
        entry-id
    )
)

(define-public (issue-prescription
        (patient principal)
        (drug-name (string-ascii 64))
        (dosage (string-ascii 32))
        (quantity uint)
        (validity-days uint)
        (max-refills uint)
    )
    (let (
            (is-doc (is-doctor tx-sender))
            (id (+ (var-get last-prescription-id) u1))
            (current-height stacks-block-height)
            (expiry (+ current-height validity-days))
        )
        (asserts! is-doc err-not-authorized)
        (asserts! (> quantity u0) err-invalid-quantity)
        (asserts! (> validity-days u0) err-invalid-validity)
        (try! (nft-mint? prescription-nft id patient))
        (map-set prescriptions { id: id } {
            doctor: tx-sender,
            patient: patient,
            drug-name: drug-name,
            dosage: dosage,
            quantity: quantity,
            issue-date: current-height,
            expiry-date: expiry,
            filled: false,
            pharmacy: none,
            max-refills: max-refills,
            remaining-quantity: quantity,
            revoked: false,
            revocation-reason: none,
        })
        (var-set last-prescription-id id)
        (log-audit-entry id "issued" "prescription created")
        (ok id)
    )
)

(define-private (is-authorized-for-prescription
        (id uint)
        (actor principal)
    )
    (let ((presc (unwrap! (map-get? prescriptions { id: id }) false)))
        (or
            (is-eq actor (get patient presc))
            (match (map-get? prescription-delegates {
                prescription-id: id,
                delegate: actor,
            })
                delegation (get active delegation)
                false
            )
        )
    )
)

(define-public (fill-prescription
        (id uint)
        (requested-quantity uint)
    )
    (let (
            (presc (unwrap! (map-get? prescriptions { id: id }) err-invalid-prescription))
            (is-pharm (is-pharmacy tx-sender))
            (now stacks-block-height)
            (current-remaining (get remaining-quantity presc))
            (max-refills (get max-refills presc))
            (new-remaining (- current-remaining requested-quantity))
        )
        (asserts! is-pharm err-not-authorized)
        (asserts! (not (get revoked presc)) err-already-revoked)
        (asserts! (< now (get expiry-date presc)) err-expired)
        (asserts! (> requested-quantity u0) err-invalid-quantity)
        (asserts! (<= requested-quantity current-remaining)
            err-insufficient-quantity
        )
        (asserts! (> max-refills u0) err-no-refills-remaining)
        (if (and (is-eq new-remaining u0) (not (get filled presc)))
            (try! (nft-transfer? prescription-nft id (get patient presc) tx-sender))
            true
        )
        (map-set prescriptions { id: id }
            (merge presc {
                filled: (is-eq new-remaining u0),
                pharmacy: (some tx-sender),
                max-refills: (- max-refills u1),
                remaining-quantity: new-remaining,
            })
        )
        (log-audit-entry id "filled"
            (concat "dispensed:" (int-to-ascii requested-quantity))
        )
        (ok {
            dispensed-quantity: requested-quantity,
            remaining-quantity: new-remaining,
            refills-left: (- max-refills u1),
        })
    )
)

(define-read-only (verify-prescription (id uint))
    (match (map-get? prescriptions { id: id })
        presc (ok {
            is-valid: (and
                (> (get remaining-quantity presc) u0)
                (> (get max-refills presc) u0)
                (< stacks-block-height (get expiry-date presc))
                (not (get revoked presc))
            ),
            details: presc,
        })
        err-invalid-prescription
    )
)

(define-read-only (get-refill-history (id uint))
    (match (map-get? prescriptions { id: id })
        presc (ok {
            total-quantity: (get quantity presc),
            remaining-quantity: (get remaining-quantity presc),
            dispensed-quantity: (- (get quantity presc) (get remaining-quantity presc)),
            refills-used: (- (get quantity presc) (get max-refills presc)),
            refills-remaining: (get max-refills presc),
            last-pharmacy: (get pharmacy presc),
        })
        err-invalid-prescription
    )
)

(define-public (transfer-prescription
        (id uint)
        (new-patient principal)
    )
    (let (
            (presc (unwrap! (map-get? prescriptions { id: id }) err-invalid-prescription))
            (current-owner (unwrap! (nft-get-owner? prescription-nft id)
                err-invalid-prescription
            ))
        )
        (asserts! (is-eq tx-sender current-owner) err-not-owner)
        (asserts! (not (is-eq tx-sender new-patient)) err-transfer-to-self)
        (asserts! (not (get filled presc)) err-already-filled)
        (asserts! (< stacks-block-height (get expiry-date presc)) err-expired)
        (try! (nft-transfer? prescription-nft id tx-sender new-patient))
        (map-set prescriptions { id: id } (merge presc { patient: new-patient }))
        (log-audit-entry id "transferred" "patient changed")
        (ok true)
    )
)

(define-read-only (get-prescription-audit-count (prescription-id uint))
    (let ((current-audit-id (var-get audit-entry-id)))
        (ok (fold count-prescription-entries
            (list
                u1                 u2                 u3                 u4
                u5                 u6                 u7                 u8
                u9                 u10                 u11                 u12
                u13                 u14                 u15                 u16
                u17                 u18
                u19                 u20
            ) {
            target-id: prescription-id,
            count: u0,
        }))
    )
)

(define-private (count-prescription-entries
        (entry-id uint)
        (acc {
            target-id: uint,
            count: uint,
        })
    )
    (match (map-get? audit-trail { entry-id: entry-id })
        entry (if (is-eq (get prescription-id entry) (get target-id acc))
            {
                target-id: (get target-id acc),
                count: (+ (get count acc) u1),
            }
            acc
        )
        acc
    )
)

(define-read-only (get-audit-entry (entry-id uint))
    (match (map-get? audit-trail { entry-id: entry-id })
        entry (ok entry)
        err-invalid-prescription
    )
)

(define-public (revoke-prescription
        (id uint)
        (reason (string-ascii 100))
    )
    (let ((presc (unwrap! (map-get? prescriptions { id: id }) err-invalid-prescription)))
        (asserts! (is-eq tx-sender (get doctor presc)) err-not-authorized)
        (asserts! (not (get revoked presc)) err-already-revoked)
        (asserts! (not (get filled presc)) err-cannot-revoke-filled)
        (map-set prescriptions { id: id }
            (merge presc {
                revoked: true,
                revocation-reason: (some reason),
            })
        )
        (log-audit-entry id "revoked" reason)
        (ok true)
    )
)

(define-read-only (is-prescription-revoked (id uint))
    (match (map-get? prescriptions { id: id })
        presc (ok (get revoked presc))
        err-invalid-prescription
    )
)

(define-public (delegate-prescription-pickup
        (prescription-id uint)
        (delegate principal)
    )
    (let (
            (presc (unwrap! (map-get? prescriptions { id: prescription-id })
                err-invalid-prescription
            ))
            (current-owner (unwrap! (nft-get-owner? prescription-nft prescription-id)
                err-invalid-prescription
            ))
            (existing-delegation (map-get? prescription-delegates {
                prescription-id: prescription-id,
                delegate: delegate,
            }))
        )
        (asserts! (is-eq tx-sender current-owner) err-not-owner)
        (asserts! (not (is-eq tx-sender delegate)) err-delegation-to-self)
        (asserts! (not (get filled presc)) err-already-filled)
        (asserts! (is-none existing-delegation) err-already-delegated)
        (map-set prescription-delegates {
            prescription-id: prescription-id,
            delegate: delegate,
        } {
            delegator: tx-sender,
            granted-at: stacks-block-height,
            active: true,
        })
        (log-audit-entry prescription-id "delegated" "pickup rights granted")
        (ok true)
    )
)

(define-public (revoke-delegation
        (prescription-id uint)
        (delegate principal)
    )
    (let (
            (presc (unwrap! (map-get? prescriptions { id: prescription-id })
                err-invalid-prescription
            ))
            (current-owner (unwrap! (nft-get-owner? prescription-nft prescription-id)
                err-invalid-prescription
            ))
            (delegation (unwrap!
                (map-get? prescription-delegates {
                    prescription-id: prescription-id,
                    delegate: delegate,
                })
                err-not-delegated
            ))
        )
        (asserts! (is-eq tx-sender current-owner) err-not-owner)
        (asserts! (get active delegation) err-not-delegated)
        (map-set prescription-delegates {
            prescription-id: prescription-id,
            delegate: delegate,
        }
            (merge delegation { active: false })
        )
        (log-audit-entry prescription-id "revoked-delegation"
            "pickup rights revoked"
        )
        (ok true)
    )
)

(define-read-only (is-delegated-for-prescription
        (prescription-id uint)
        (delegate principal)
    )
    (match (map-get? prescription-delegates {
        prescription-id: prescription-id,
        delegate: delegate,
    })
        delegation (ok (get active delegation))
        (ok false)
    )
)

(define-read-only (get-delegation-info
        (prescription-id uint)
        (delegate principal)
    )
    (match (map-get? prescription-delegates {
        prescription-id: prescription-id,
        delegate: delegate,
    })
        delegation (ok delegation)
        err-not-delegated
    )
)
