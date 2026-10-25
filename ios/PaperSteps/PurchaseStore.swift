import Combine
import Foundation
import StoreKit

enum PurchasePlan: String, CaseIterable, Identifiable {
    case monthly, annual, lifetime

    var id: String { rawValue }
    var productID: String {
        switch self {
        case .monthly: return "org.realitycore.foliafold.monthly"
        case .annual: return "org.realitycore.foliafold.annual"
        case .lifetime: return "org.realitycore.foliafold.complete"
        }
    }
    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .lifetime: return "Lifetime"
        }
    }
    var isSubscription: Bool { self != .lifetime }
    fileprivate var productType: Product.ProductType { isSubscription ? .autoRenewable : .nonConsumable }
    fileprivate init?(productID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }
}

/// Access comes only from verified StoreKit transactions and signed renewal information.
/// Prices and subscription periods come from Apple's products, never a local price table.
@MainActor
final class PurchaseStore: ObservableObject {
    /// Keep the original non-consumable identifier and API for existing owners.
    static let productID = PurchasePlan.lifetime.productID

    @Published private(set) var isUnlocked = false
    @Published private(set) var activePlan: PurchasePlan?
    /// The current access end, including a verified billing grace period; nil for lifetime.
    /// This is not a prediction of the next charge or a promise that renewal is enabled.
    @Published private(set) var expirationDate: Date?
    @Published private(set) var isLifetimeUnlocked = false
    @Published private(set) var isBusy = false
    @Published var message: String?
    @Published private var products: [PurchasePlan: Product] = [:]

    var availablePlans: [PurchasePlan] { PurchasePlan.allCases.filter { products[$0] != nil } }
    var product: Product? { product(for: .lifetime) }
    func product(for plan: PurchasePlan) -> Product? { products[plan] }

    private struct Entitlement {
        let transaction: StoreKit.Transaction
        let plan: PurchasePlan
        let accessEnd: Date?
    }

    private var updatesTask: Task<Void, Never>?
    private var subscriptionUpdatesTask: Task<Void, Never>?
    private var expirationTask: Task<Void, Never>?
    private var entitlementRevision: UInt64 = 0
    private var excludedTransactionIDs = Set<UInt64>()
    private var entitlements: [UInt64: Entitlement] = [:]

    init() {
        updatesTask = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                if Task.isCancelled { break }
                await self?.receive(result)
            }
        }
        // Expiration, billing recovery and renewal preference changes can arrive
        // as subscription status updates without a new purchase in this process.
        subscriptionUpdatesTask = Task { [weak self] in
            for await status in Product.SubscriptionInfo.Status.updates {
                if Task.isCancelled { break }
                guard case .verified(let transaction) = status.transaction,
                      PurchasePlan(productID: transaction.productID)?.isSubscription == true else { continue }
                await self?.refreshEntitlements(observedStatus: status)
            }
        }
    }

    deinit {
        updatesTask?.cancel()
        subscriptionUpdatesTask?.cancel()
        expirationTask?.cancel()
    }

    /// The app calls this on launch and whenever its scene becomes active.
    /// Even during a purchase, recheck entitlement expiry after backgrounding.
    /// Only the explicit Restore action presents AppStore.sync() authentication.
    func refresh() async {
        await refreshEntitlements()
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        await loadProducts()
    }

    func purchase() async { await purchase(.lifetime) }

    func purchase(_ plan: PurchasePlan) async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        await refreshEntitlements()
        // Lifetime already covers every plan. Existing subscribers can select
        // a different duration; Apple handles the group change and its timing.
        guard !isLifetimeUnlocked, activePlan != plan else { return }
        if product(for: plan) == nil { await loadProducts() }
        guard let product = product(for: plan), product.type == plan.productType else {
            message = "This plan is not available to purchase right now. Please try again later."
            return
        }
        do {
            switch try await product.purchase() {
            case .success(let result):
                await receive(result)
            case .pending:
                message = "Your purchase is waiting for approval. Access will update after Apple confirms it."
            case .userCancelled:
                message = nil
            @unknown default:
                message = "Apple has not confirmed this purchase yet. Please try Restore Purchases later."
            }
        } catch StoreKitError.userCancelled {
            message = nil
        } catch is CancellationError {
            message = nil
        } catch {
            message = "The purchase could not be completed. Please check your connection and try again."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            message = isUnlocked ? "Your full library has been restored."
                : "No active subscription or lifetime purchase was found for this Apple Account."
        } catch StoreKitError.userCancelled {
            message = nil
        } catch is CancellationError {
            message = nil
        } catch {
            // A connection failure never creates access or erases an unexpired
            // verified purchase. It must still respect subscription expiration.
            applyEntitlements(entitlements)
            message = "Purchases could not be restored. Please check your connection and try again."
        }
    }

    private func loadProducts() async {
        do {
            let fetched = try await Product.products(for: PurchasePlan.allCases.map(\.productID))
            products = Dictionary(fetched.compactMap { product -> (PurchasePlan, Product)? in
                guard let plan = PurchasePlan(productID: product.id), product.type == plan.productType else { return nil }
                return (plan, product)
            }, uniquingKeysWith: { first, _ in first })
            if products.isEmpty && !isUnlocked {
                message = "The library plans are not available to purchase right now. Please try again later."
            }
        } catch {
            products = [:]
            if !isUnlocked {
                message = "The store is unavailable. Please check your connection and try again."
            }
        }
    }

    private func receive(_ result: VerificationResult<StoreKit.Transaction>) async {
        switch result {
        case .verified(let transaction):
            guard let plan = PurchasePlan(productID: transaction.productID),
                  transaction.productType == plan.productType else { return }
            excludeIfInvalid(transaction)
            await refreshEntitlements(observedTransaction: transaction)
            // Deliver access before acknowledging a verified purchase or renewal.
            await transaction.finish()
            if transaction.revocationDate != nil {
                message = isUnlocked ? "This purchase was refunded or revoked. Your other active access remains available."
                    : "Your purchase was refunded or revoked. The free lessons are still available."
            } else if isUnlocked {
                message = "Your full library is unlocked. Enjoy folding."
            }
        case .unverified(let transaction, _):
            guard PurchasePlan(productID: transaction.productID) != nil else { return }
            // Never finish or grant content for an unverifiable transaction.
            await refreshEntitlements()
            message = "Apple could not verify this purchase. Please try Restore Purchases."
        }
    }

    private func excludeIfInvalid(_ transaction: StoreKit.Transaction) {
        guard transaction.revocationDate != nil || transaction.isUpgraded else { return }
        excludedTransactionIDs.insert(transaction.id)
        entitlementRevision &+= 1
        entitlements.removeValue(forKey: transaction.id)
        // Revoking a subscription must not remove an independent lifetime purchase.
        applyEntitlements(entitlements)
    }

    private func refreshEntitlements(observedTransaction: StoreKit.Transaction? = nil,
                                     observedStatus: Product.SubscriptionInfo.Status? = nil) async {
        if let observedTransaction { excludeIfInvalid(observedTransaction) }
        if let observedStatus, case .verified(let transaction) = observedStatus.transaction { excludeIfInvalid(transaction) }
        entitlementRevision &+= 1
        let revision = entitlementRevision
        let priorEntitlements = entitlements
        applyEntitlements(entitlements)
        var current: [UInt64: StoreKit.Transaction] = [:]
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            current[transaction.id] = transaction
        }
        // A just-confirmed purchase is signed evidence even if the asynchronous
        // current-entitlement sequence has not reflected that update yet.
        if let observedTransaction { current[observedTransaction.id] = observedTransaction }
        if let observedStatus, case .verified(let transaction) = observedStatus.transaction {
            current[transaction.id] = transaction
        }

        var next: [UInt64: Entitlement] = [:]
        var groups = Set<String>()
        for transaction in current.values {
            guard let plan = validPlan(for: transaction) else { continue }
            if let group = transaction.subscriptionGroupID, plan.isSubscription { groups.insert(group) }
            if plan == .lifetime {
                next[transaction.id] = Entitlement(transaction: transaction, plan: plan, accessEnd: nil)
            } else if let end = transaction.expirationDate, end > Date() {
                next[transaction.id] = Entitlement(transaction: transaction, plan: plan, accessEnd: end)
            }
        }
        for product in products.values {
            if let group = product.subscription?.subscriptionGroupID { groups.insert(group) }
        }
        for group in groups {
            do {
                for status in try await Product.SubscriptionInfo.status(for: group) {
                    apply(status: status, to: &next)
                }
            } catch {
                // Retain only an already verified, still-current grace entitlement
                // until its signed end when a status request temporarily fails.
                for (id, prior) in priorEntitlements where current[id] != nil && prior.transaction.subscriptionGroupID == group {
                    if let transaction = current[id], validPlan(for: transaction) != nil,
                       let end = prior.accessEnd, end > Date(), validPlan(for: prior.transaction) != nil {
                        next[id] = prior
                    }
                }
            }
        }
        if let observedStatus { apply(status: observedStatus, to: &next) }
        // A transaction/status update that began later supersedes an older query.
        guard revision == entitlementRevision else { return }
        applyEntitlements(next)
    }

    private func validPlan(for transaction: StoreKit.Transaction) -> PurchasePlan? {
        guard let plan = PurchasePlan(productID: transaction.productID),
              transaction.productType == plan.productType,
              transaction.revocationDate == nil, !transaction.isUpgraded,
              !excludedTransactionIDs.contains(transaction.id) else { return nil }
        return plan
    }

    private func apply(status: Product.SubscriptionInfo.Status, to next: inout [UInt64: Entitlement]) {
        guard case .verified(let transaction) = status.transaction,
              let plan = PurchasePlan(productID: transaction.productID), plan.isSubscription else { return }
        next.removeValue(forKey: transaction.id)
        guard validPlan(for: transaction) != nil else { return }
        let end: Date?
        switch status.state {
        case .subscribed:
            end = transaction.expirationDate
        case .inGracePeriod:
            guard case .verified(let renewal) = status.renewalInfo,
                  renewal.currentProductID == transaction.productID,
                  renewal.originalTransactionID == transaction.originalID else { return }
            end = renewal.gracePeriodExpirationDate
        default:
            // Expired, billing retry without grace and revoked are not access.
            return
        }
        guard let end, end > Date() else { return }
        next[transaction.id] = Entitlement(transaction: transaction, plan: plan, accessEnd: end)
    }

    private func applyEntitlements(_ snapshot: [UInt64: Entitlement]) {
        let now = Date()
        entitlements = snapshot.filter { _, entitlement in
            validPlan(for: entitlement.transaction) != nil && (entitlement.accessEnd.map { $0 > now } ?? (entitlement.plan == .lifetime))
        }
        let lifetime = entitlements.values.first { $0.plan == .lifetime }
        let subscription = entitlements.values.filter { $0.plan.isSubscription }.max {
            if $0.accessEnd == $1.accessEnd { return $0.transaction.purchaseDate < $1.transaction.purchaseDate }
            return ($0.accessEnd ?? .distantPast) < ($1.accessEnd ?? .distantPast)
        }
        let active = lifetime ?? subscription
        activePlan = active?.plan
        expirationDate = active?.accessEnd
        isLifetimeUnlocked = lifetime != nil
        isUnlocked = active != nil
        scheduleExpirationCheck()
    }

    private func scheduleExpirationCheck() {
        expirationTask?.cancel()
        expirationTask = nil
        guard let expirationDate else { return }
        // Recheck at the signed end even if StoreKit sends no transaction event.
        // An hourly bound also responds to wall-clock changes during long sessions.
        let delay = max(0.05, min(expirationDate.timeIntervalSinceNow, 3_600))
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expirationTask = nil
            await self?.refreshEntitlements()
        }
    }
}
