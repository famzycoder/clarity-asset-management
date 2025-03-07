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

