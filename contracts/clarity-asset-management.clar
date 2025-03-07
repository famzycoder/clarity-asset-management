;; nft-digital-assets.clar
;; ============================================================
;; NFT Digital Asset Management System
;; ============================================================
;; This contract implements a comprehensive system for digital assets as NFTs
;; on the Stacks blockchain. It provides core functionality for digital asset 
;; lifecycle management including creation, ownership transfer, metadata 
;; management, and permanent removal.
;;
;; Core Capabilities:
;; - Single and bulk asset creation with configurable limits
;; - Asset destruction with permanent record keeping
;; - Secure ownership transfer between users
;; - Dynamic metadata management with validation
;; - Comprehensive query system for asset details and status
;;
;; Security Features:
;; - Role-based access controls for sensitive operations
;; - Input validation for all public interfaces
;; - Permanent tracking of destroyed assets
;; - Multiple verification layers for ownership operations
;;
;; Contract Version: 1.1
;; Clarity Version: 6.0
;; ============================================================

;; ============================================================
;; Core Configuration Parameters
;; ============================================================

;; Management configuration
(define-constant contract-owner tx-sender)
(define-constant bulk-creation-limit u50)  ;; Maximum assets per bulk operation

;; System error definitions
(define-constant err-unauthorized (err u200))           ;; Access control violation
(define-constant err-ownership-violation (err u201))    ;; Caller is not the asset owner
(define-constant err-asset-duplicate (err u202))        ;; Asset ID already exists
(define-constant err-asset-missing (err u203))          ;; Asset ID does not exist
(define-constant err-metadata-invalid (err u204))       ;; Metadata format is invalid
(define-constant err-destruction-failed (err u205))     ;; Asset destruction operation failed
(define-constant err-previously-destroyed (err u206))   ;; Asset was already destroyed
(define-constant err-metadata-permission (err u207))    ;; Not permitted to update metadata
(define-constant err-bulk-limit-exceeded (err u208))    ;; Bulk operation size too large
(define-constant err-bulk-creation-error (err u209))    ;; Bulk creation operation failed

;; ============================================================
;; Core Data Structures
;; ============================================================

;; Asset token definition
(define-non-fungible-token digital-asset uint)

;; System counters
(define-data-var asset-counter uint u0)

;; ============================================================
;; Data Storage Maps
;; ============================================================

;; Asset metadata storage
(define-map asset-metadata uint (string-ascii 256))

;; Tracks destruction status
(define-map destroyed-assets uint bool)

;; Bulk operation details
(define-map creation-batch-data uint (string-ascii 256))

;; ============================================================
;; Private Utility Functions
;; ============================================================

;; Validates asset ownership claim
(define-private (confirm-asset-owner (asset-id uint) (claimed-owner principal))
    (is-eq claimed-owner (unwrap! (nft-get-owner? digital-asset asset-id) false)))

;; Validates metadata format requirements
(define-private (validate-metadata (metadata-url (string-ascii 256)))
    (let ((metadata-length (len metadata-url)))
        (and (>= metadata-length u1)
             (<= metadata-length u256))))

;; Checks asset destruction status
(define-private (is-asset-destroyed (asset-id uint))
    (default-to false (map-get? destroyed-assets asset-id)))

;; Internal asset creation implementation
(define-private (create-single-asset (metadata-url (string-ascii 256)))
    (let ((next-id (+ (var-get asset-counter) u1)))
        (asserts! (validate-metadata metadata-url) err-metadata-invalid)
        (try! (nft-mint? digital-asset next-id tx-sender))
        (map-set asset-metadata next-id metadata-url)
        (var-set asset-counter next-id)
        (ok next-id)))

;; ============================================================
;; Asset Creation Operations
;; ============================================================

;; Creates a single digital asset with metadata
(define-public (mint-asset (metadata-url (string-ascii 256)))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (validate-metadata metadata-url) err-metadata-invalid)
        (create-single-asset metadata-url)))

;; Creates multiple assets in a single transaction
(define-public (bulk-mint (metadata-urls (list 50 (string-ascii 256))))
    (let ((item-count (len metadata-urls)))
        (begin
            (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
            (asserts! (<= item-count bulk-creation-limit) err-bulk-limit-exceeded)
            (asserts! (> item-count u0) err-bulk-limit-exceeded)
            (ok (fold process-bulk-creation metadata-urls (list)))
        )))

;; Helper for bulk creation process
(define-private (process-bulk-creation (metadata-url (string-ascii 256)) (created-assets (list 50 uint)))
    (match (create-single-asset metadata-url)
        new-asset-id (unwrap-panic (as-max-len? (append created-assets new-asset-id) u50))
        err created-assets))

;; ============================================================
;; Asset Management Operations
;; ============================================================

;; Permanently destroys an asset
(define-public (destroy-asset (asset-id uint))
    (let ((current-owner (unwrap! (nft-get-owner? digital-asset asset-id) err-asset-missing)))
        (asserts! (is-eq tx-sender current-owner) err-ownership-violation)
        (asserts! (not (is-asset-destroyed asset-id)) err-previously-destroyed)
        (try! (nft-burn? digital-asset asset-id current-owner))
        (map-set destroyed-assets asset-id true)
        (ok true)))

;; Transfers asset ownership between users
(define-public (transfer-asset (asset-id uint) (sender principal) (recipient principal))
    (begin
        (asserts! (is-eq recipient tx-sender) err-ownership-violation)
        (asserts! (not (is-asset-destroyed asset-id)) err-previously-destroyed)
        (let ((current-owner (unwrap! (nft-get-owner? digital-asset asset-id) err-ownership-violation)))
            (asserts! (is-eq current-owner sender) err-ownership-violation)
            (try! (nft-transfer? digital-asset asset-id sender recipient))
            (ok true))))


;; Updates asset metadata
(define-public (update-asset-metadata (asset-id uint) (new-metadata-url (string-ascii 256)))
    (let ((current-owner (unwrap! (nft-get-owner? digital-asset asset-id) err-asset-missing)))
        (asserts! (is-eq current-owner tx-sender) err-metadata-permission)
        (asserts! (validate-metadata new-metadata-url) err-metadata-invalid)
        (map-set asset-metadata asset-id new-metadata-url)
        (ok true)))

;; ============================================================
;; Asset Information Queries
;; ============================================================

;; Retrieves asset metadata
(define-read-only (get-asset-metadata (asset-id uint))
    (ok (map-get? asset-metadata asset-id)))

;; Retrieves asset owner
(define-read-only (get-asset-owner (asset-id uint))
    (ok (nft-get-owner? digital-asset asset-id)))

;; Retrieves current asset counter
(define-read-only (get-asset-count)
    (ok (var-get asset-counter)))

;; Checks if asset has been destroyed
(define-read-only (check-destruction-status (asset-id uint))
    (ok (is-asset-destroyed asset-id)))

;; Returns asset destruction status
(define-read-only (get-asset-status (asset-id uint))
    (ok (is-asset-destroyed asset-id)))

;; Retrieves specific asset metadata
(define-read-only (fetch-asset-metadata (asset-id uint))
    (ok (map-get? asset-metadata asset-id)))

;; Retrieves total asset count
(define-read-only (get-total-assets)
    (ok (var-get asset-counter)))

;; Retrieves asset metadata for multiple assets
(define-read-only (get-asset-batch (start-id uint) (batch-size uint))
    (ok (map asset-details (unwrap-panic (as-max-len? (generate-asset-id-range start-id batch-size) u50)))))

(define-read-only (get-current-owner (asset-id uint))
(ok (unwrap-panic (nft-get-owner? digital-asset asset-id))))

(define-read-only (verify-asset-existence (asset-id uint))
(ok (is-some (map-get? asset-metadata asset-id))))

(define-read-only (is-asset-minted (asset-id uint))
(ok (is-some (map-get? asset-metadata asset-id))))

;; Verifies asset existence
(define-read-only (asset-exists (asset-id uint))
    (ok (is-some (map-get? asset-metadata asset-id))))

;; Validates asset ID
(define-read-only (is-valid-asset-id (asset-id uint))
    (ok (<= asset-id (var-get asset-counter))))

(define-read-only (get-minted-asset-count)
(ok (var-get asset-counter)))

;; Returns bulk operation limit
(define-read-only (get-bulk-limit)
    (ok bulk-creation-limit))

(define-read-only (check-asset-id-validity (asset-id uint))
(ok (<= asset-id (var-get asset-counter))))

(define-read-only (verify-metadata-exists (asset-id uint))
(ok (is-some (map-get? asset-metadata asset-id))))

;; Gets batch operation details
(define-read-only (get-batch-details (asset-id uint))
    (ok (map-get? creation-batch-data asset-id)))

(define-read-only (check-asset-active (asset-id uint))
(ok (not (is-asset-destroyed asset-id))))

;; Gets batch asset details
(define-read-only (get-bulk-assets (start-id uint) (count uint))
    (ok (map asset-details (unwrap-panic (as-max-len? (generate-asset-id-range start-id count) u50)))))

;; Helper for asset details
(define-private (asset-details (id uint))
    {
        asset-id: id,
        metadata: (unwrap-panic (get-asset-metadata id)),
        owner: (unwrap-panic (get-asset-owner id)),
        destroyed: (unwrap-panic (check-destruction-status id))
    })

(define-read-only (get-all-asset-metadata)
(ok (map-get? asset-metadata (var-get asset-counter))))

;; Checks for available asset IDs
(define-read-only (check-id-availability (asset-id uint))
    (ok (is-none (map-get? asset-metadata asset-id))))

;; Verifies administrative access
(define-read-only (check-admin-status (address principal))
    (ok (is-eq address contract-owner)))

;; Gets next asset ID
(define-read-only (get-next-asset-id)
    (ok (+ (var-get asset-counter) u1)))

;; Ownership transfer history
(define-map transfer-history uint uint)

;; Gets transfer count
(define-read-only (get-ownership-transfer-count (asset-id uint))
    (ok (default-to u0 (map-get? transfer-history asset-id))))

(define-read-only (get-destruction-status (asset-id uint))
(ok (is-asset-destroyed asset-id)))

;; Gets complete asset details
(define-read-only (get-complete-asset-details (asset-id uint))
    (let ((metadata-url (map-get? asset-metadata asset-id))
          (owner (nft-get-owner? digital-asset asset-id))
          (destroyed (is-asset-destroyed asset-id)))
        (ok {asset-id: asset-id, metadata: metadata-url, owner: owner, destroyed: destroyed})))


(define-read-only (retrieve-asset-metadata (asset-id uint))
(ok (map-get? asset-metadata asset-id)))

;; Generates asset ID sequence
(define-private (generate-asset-id-range (start uint) (count uint))
    (map + 
        (list start) 
        (create-numeric-sequence count)))

;; Creates numeric sequence
(define-private (create-numeric-sequence (num uint))
    (map - (list num)))

;; Generates sequence for iteration
(define-private (create-id-sequence (start uint) (end uint))
    (map + (list start) (create-numeric-sequence end)))

;; ============================================================
;; Contract Initialization
;; ============================================================

(begin
    (var-set asset-counter u0))


;; ============================================================
;; Enhanced Asset Management Functions
;; ============================================================

;; Retrieves asset transfer history
(define-public (get-asset-transfer-history (asset-id uint))
    (ok (map-get? transfer-history asset-id)))

;; Validates metadata before asset transfer
(define-public (transfer-with-metadata-validation (asset-id uint) (recipient principal))
    (let ((metadata-url (unwrap! (map-get? asset-metadata asset-id) err-asset-missing)))
        (asserts! (validate-metadata metadata-url) err-metadata-invalid)
        (transfer-asset asset-id (unwrap! (nft-get-owner? digital-asset asset-id) err-asset-missing) recipient)))

;; Logs destruction attempts
(define-private (record-destruction-attempt (asset-id uint) (result bool))
    (if (not result)
        (begin
            (map-set creation-batch-data asset-id "Destruction attempt failed")
            (ok false))
        (ok true)))

;; Combined asset query
(define-read-only (get-asset-combined-status (asset-id uint))
    (ok {metadata: (unwrap-panic (get-asset-metadata asset-id)),
         destroyed: (is-asset-destroyed asset-id)}))

;; Verifies asset existence before transfer
(define-public (verify-before-transfer (asset-id uint))
    (if (is-none (map-get? asset-metadata asset-id))
        (err err-asset-missing)
        (ok true)))

;; ============================================================
;; Security and Optimization Functions
;; ============================================================

;; Validates asset ID before creation
(define-private (validate-asset-creation (asset-id uint))
    (let ((exists (map-get? asset-metadata asset-id)))
        (asserts! (is-none exists) err-asset-duplicate)
        (ok true)))

;; Administrator-only asset destruction
(define-public (admin-destroy-asset (asset-id uint))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-unauthorized)
        (asserts! (not (is-asset-destroyed asset-id)) err-previously-destroyed)
        (try! (nft-burn? digital-asset asset-id tx-sender))
        (map-set destroyed-assets asset-id true)
        (ok true)))

;; Enhanced metadata validation
(define-private (enhanced-metadata-validation (metadata-url (string-ascii 256)))
    (let ((url-length (len metadata-url)))
        (if (or (< url-length u1) (> url-length u256))
            (err err-metadata-invalid)
            (ok true))))

;; Comprehensive asset lookup
(define-public (get-full-asset-info (asset-id uint))
    (ok {metadata: (unwrap-panic (get-asset-metadata asset-id)), 
         owner: (unwrap-panic (get-asset-owner asset-id)),
         destroyed: (unwrap-panic (check-destruction-status asset-id))}))

;; Ownership verification
(define-public (verify-asset-ownership (asset-id uint) (claimed-owner principal))
    (ok (is-eq (unwrap! (nft-get-owner? digital-asset asset-id) err-ownership-violation) claimed-owner)))

;; ============================================================
;; Additional Asset Management Functions
;; ============================================================

;; Gets asset ownership records
(define-read-only (retrieve-ownership-records (asset-id uint))
    (ok (map-get? transfer-history asset-id)))

;; Gets asset metadata with validation
(define-public (get-validated-metadata (asset-id uint))
    (ok (map-get? asset-metadata asset-id)))

;; Validates metadata batch
(define-private (validate-metadata-batch (metadata-urls (list 50 (string-ascii 256))))
    (begin
        (asserts! (<= (len metadata-urls) bulk-creation-limit) err-bulk-limit-exceeded)
        (asserts! (> (len metadata-urls) u0) err-bulk-limit-exceeded)
        (ok (map validate-metadata metadata-urls))))

;; Gets batch creation status
(define-read-only (check-batch-status (batch-id uint))
    (ok (map-get? creation-batch-data batch-id)))

;; Enhanced security verification
(define-private (security-verification (asset-id uint))
    (begin
        (asserts! (not (is-asset-destroyed asset-id)) err-previously-destroyed)
        (asserts! (is-some (map-get? asset-metadata asset-id)) err-asset-missing)
        (ok true)))

;; Secure transfer validation
(define-public (validate-transfer-security (asset-id uint) (sender principal) (recipient principal))
    (begin
        (try! (security-verification asset-id))
        (asserts! (confirm-asset-owner asset-id sender) err-ownership-violation)
        (ok true)))

;; ============================================================
;; Advanced Data Structures for Performance and Security
;; ============================================================

;; Asset transfer locks
(define-map security-locks uint bool)

;; Extended asset details storage
(define-map asset-extended-info uint 
    {
        creation-timestamp: uint,
        last-update: uint,
        properties: (string-ascii 256)
    })

;; Enhanced asset data retrieval
(define-read-only (get-asset-extended-info (asset-id uint))
    (ok (map-get? asset-extended-info asset-id)))

;; System monitoring
(define-map contract-monitoring uint 
    {
        total-assets: uint,
        admin: principal,
        max-batch: uint
    })

;; Gets system limits
(define-read-only (get-system-limits)
    (ok {
        max-bulk-size: bulk-creation-limit,
        metadata-max-length: u256
    }))

;; Operation audit trail
(define-map audit-log uint 
    {
        action: (string-ascii 16),
        block: uint,
        actor: principal
    })

;; Records system operations
(define-private (log-system-action 
    (asset-id uint) 
    (action (string-ascii 16)))
    (map-set audit-log asset-id
        {
            action: action,
            block: block-height,
            actor: tx-sender
        }))

;; Retrieves operation audit
(define-read-only (get-operation-audit (asset-id uint))
    (ok (map-get? audit-log asset-id)))

;; Asset statistics tracking
(define-map asset-metrics uint 
    {
        transfers: uint,
        destruction-attempts: uint,
        last-operation: uint
    })

;; Updates asset tracking
(define-private (update-asset-metrics 
    (asset-id uint) 
    (operation (string-ascii 16)))
    (let ((current-metrics (default-to 
            {transfers: u0, destruction-attempts: u0, last-operation: u0}
            (map-get? asset-metrics asset-id))))
        (map-set asset-metrics asset-id
            (merge current-metrics
                {last-operation: block-height}))))

;; Gets asset metrics
(define-read-only (get-asset-metrics (asset-id uint))
    (ok (map-get? asset-metrics asset-id)))

;; Secure metadata update
(define-public (secure-metadata-update (asset-id uint) (updated-metadata (string-ascii 256)))
    (let ((owner (unwrap! (nft-get-owner? digital-asset asset-id) err-asset-missing)))
        (asserts! (is-eq tx-sender owner) err-metadata-permission)
        (asserts! (validate-metadata updated-metadata) err-metadata-invalid)
        (map-set asset-metadata asset-id updated-metadata)
        (ok true)))

;; Metadata correction utility
(define-private (fix-metadata-issues (asset-id uint) (correct-metadata (string-ascii 256)))
    (begin
        (map-set asset-metadata asset-id correct-metadata)
        (ok "Metadata corrected successfully")
    )
)

;; Enhanced secure transfer
(define-private (multi-verified-transfer (asset-id uint) (sender principal) (recipient principal))
    (let ((verified-owner (unwrap! (nft-get-owner? digital-asset asset-id) err-ownership-violation)))
        (asserts! (is-eq sender verified-owner) err-ownership-violation)
        (asserts! (not (is-asset-destroyed asset-id)) err-previously-destroyed)
        (try! (nft-transfer? digital-asset asset-id sender recipient))
        (ok true)))

;; Metadata format validation
(define-public (validate-and-update-metadata (asset-id uint) (new-metadata (string-ascii 256)))
    (let ((owner (unwrap! (nft-get-owner? digital-asset asset-id) err-asset-missing)))
        (asserts! (is-eq tx-sender owner) err-metadata-permission)
        (asserts! (validate-metadata new-metadata) err-metadata-invalid)
        (map-set asset-metadata asset-id new-metadata)
        (ok true))
)

;; Optimized metadata retrieval
(define-private (optimized-metadata-fetch (asset-id uint))
    (let ((metadata (map-get? asset-metadata asset-id))
          (owner (nft-get-owner? digital-asset asset-id)))
        (ok {asset-id: asset-id, metadata: metadata, owner: owner})
    )
)

;; Asset destruction event logging
(define-private (record-destruction-event (asset-id uint))
    (begin
        (map-set creation-batch-data asset-id "Asset permanently destroyed")
        (ok true)
    )
)

;; Creation limit validation
(define-public (validate-creation-limit (metadata-urls (list 50 (string-ascii 256))))
    (let ((operation-size (len metadata-urls)))
        (asserts! (<= operation-size bulk-creation-limit) err-bulk-limit-exceeded)
        (ok true)
    )
)

;; Enhanced asset metadata structure
(define-map comprehensive-asset-data uint 
    {
        creation-block: uint,
        updated-at: uint,
        version-number: uint,
        classification: (string-ascii 64),
        characteristics: (list 10 (string-ascii 64))
    })

;; Security monitoring
(define-map security-monitoring uint 
    {
        alert-total: uint,
        last-triggered: uint,
        alert-category: (string-ascii 64)
    })

;; Bulk operation tracking
(define-map bulk-operation-status uint 
    {
        requested-count: uint,
        completed-count: uint,
        success-count: uint,
        timestamp: uint
    })

;; Data access optimization
(define-map performance-optimization uint 
    {
        last-accessed: uint,
        access-frequency: uint,
        cached-metadata: (string-ascii 256)
    })

;; Testing framework
(define-map test-results uint 
    {
        test-identifier: (string-ascii 64),
        passed: bool,
        execution-duration: uint,
        error-details: (string-ascii 256)
    })

;; UI configuration storage
(define-map interface-preferences uint 
    {
        view-mode: (string-ascii 32),
        sort-preference: (string-ascii 32),
        filter-settings: (string-ascii 64)
    })

;; Gets enhanced asset data
(define-read-only (get-comprehensive-asset-data (asset-id uint))
    (ok (map-get? comprehensive-asset-data asset-id)))

;; Gets security monitoring data
(define-read-only (get-security-monitoring-data (asset-id uint))
    (ok (map-get? security-monitoring asset-id)))

;; Gets bulk operation tracking
(define-read-only (get-bulk-operation-status (operation-id uint))
    (ok (map-get? bulk-operation-status operation-id)))

;; Gets optimization status
(define-read-only (get-optimization-status (asset-id uint))
    (ok (map-get? performance-optimization asset-id)))

;; Gets test framework results
(define-read-only (get-test-framework-results (test-id uint))
    (ok (map-get? test-results test-id)))

;; Gets UI configuration
(define-read-only (get-interface-configuration (user-id uint))
    (ok (map-get? interface-preferences user-id)))

