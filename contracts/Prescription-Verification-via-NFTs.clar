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
        })
        (var-set last-prescription-id id)
        (ok id)
    )
)

(define-public (fill-prescription (id uint))
    (let (
            (presc (unwrap! (map-get? prescriptions { id: id }) err-invalid-prescription))
            (is-pharm (is-pharmacy tx-sender))
            (now stacks-block-height)
        )
        (asserts! is-pharm err-not-authorized)
        (asserts! (not (get filled presc)) err-already-filled)
        (asserts! (< now (get expiry-date presc)) err-expired)
        (try! (nft-transfer? prescription-nft id (get patient presc) tx-sender))
        (map-set prescriptions { id: id }
            (merge presc {
                filled: true,
                pharmacy: (some tx-sender),
            })
        )
        (ok true)
    )
)

(define-read-only (verify-prescription (id uint))
    (match (map-get? prescriptions { id: id })
        presc (ok {
            is-valid: (and
                (not (get filled presc))
                (< stacks-block-height (get expiry-date presc))
            ),
            details: presc,
        })
        err-invalid-prescription
    )
)
