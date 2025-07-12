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
    }
)

(define-data-var last-prescription-id uint u0)

(define-map authorized-doctors
    { doctor: principal }
    bool
)
(define-map authorized-pharmacies
    { pharmacy: principal }
    bool
)

(define-constant err-not-authorized (err u100))
(define-constant err-invalid-prescription (err u101))
(define-constant err-already-filled (err u102))
(define-constant err-expired (err u103))
(define-constant err-invalid-quantity (err u104))
(define-constant err-invalid-validity (err u105))
(define-constant err-insufficient-quantity (err u106))
(define-constant err-no-refills-remaining (err u107))

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
        })
        (var-set last-prescription-id id)
        (ok id)
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
