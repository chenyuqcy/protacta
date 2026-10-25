import XCTest
import StoreKit
import StoreKitTest
@testable import Protacta

/// StoreKit's local environment is shared: run this class serially. The tests
/// exercise real StoreKit verification/events rather than injecting unlocks.
final class PurchaseStoreTests: XCTestCase {
    @MainActor
    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "ProtactaTesting")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        // Expiry is driven explicitly in these tests, not by a short automatic
        // renewal timer that could race assertions on a busy simulator.
        session.timeRate = .realTime
        return session
    }

    @MainActor
    private func waitUntil(_ description: String, timeout: TimeInterval = 8,
                           condition: @escaping @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(condition(), description)
    }

    @MainActor
    func testVerifiedPurchaseRelaunchRestoreAndRefund() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        XCTAssertFalse(store.isUnlocked, "A clean install must stay locked")
        let product = try XCTUnwrap(store.product)
        XCTAssertEqual(product.id, PurchaseStore.productID)
        XCTAssertEqual(product.type, .nonConsumable)
        XCTAssertFalse(product.displayPrice.isEmpty, "UI must get its localized price from StoreKit")

        await store.purchase()
        try await waitUntil("Verified purchase should grant the full library") { store.isUnlocked }
        XCTAssertFalse(store.isBusy)

        let relaunched = PurchaseStore()
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isUnlocked, "Existing verified purchase should restore on launch")
        await relaunched.restore()
        XCTAssertTrue(relaunched.isUnlocked)
        XCTAssertEqual(relaunched.message, "Your full library has been restored.")

        let purchased = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PurchaseStore.productID })
        try session.refundTransaction(identifier: purchased.identifier)
        try await waitUntil("A live refund must remove access without relaunch") { !store.isUnlocked && !relaunched.isUnlocked }
        await relaunched.refresh()
        XCTAssertFalse(relaunched.isUnlocked, "Refresh must not revive a refunded entitlement")
    }

    @MainActor
    func testPendingPurchaseUnlocksOnlyAfterApproval() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        session.askToBuyEnabled = true
        let store = PurchaseStore()
        await store.refresh()
        await store.purchase()
        XCTAssertFalse(store.isUnlocked, "Pending approval is not a purchase entitlement")
        XCTAssertTrue(store.message?.contains("waiting for approval") == true)
        let pending = try XCTUnwrap(session.allTransactions().first { $0.productIdentifier == PurchaseStore.productID })
        try session.approveAskToBuyTransaction(identifier: pending.identifier)
        try await waitUntil("Approved purchase should arrive through Transaction.updates") { store.isUnlocked }
    }

    @MainActor
    func testCancellationFailureAndUnverifiedTransactionsNeverUnlock() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        try await session.setSimulatedError(.generic(.userCancelled), forAPI: .purchase)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        XCTAssertNil(store.message, "Canceling the Apple sheet is a normal choice")
        XCTAssertFalse(store.isBusy)

        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .purchase)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)
        XCTAssertNotNil(store.message)
        XCTAssertFalse(store.isBusy)

        try await session.setSimulatedError(nil, forAPI: .purchase)
        try await session.setSimulatedError(.verification(.invalidSignature), forAPI: .verification)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked, "Unverified transactions must not unlock content")
        await store.refresh()
        XCTAssertFalse(store.isUnlocked, "Refreshing must not trust an unverified current entitlement")
    }

    @MainActor
    func testMissingProductDoesNotUnlockAndVerifiedOwnershipSurvivesProductFetchFailure() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        let store = PurchaseStore()
        await store.refresh()
        XCTAssertNil(store.product)
        XCTAssertFalse(store.isUnlocked)
        await store.purchase()
        XCTAssertFalse(store.isUnlocked)

        try await session.setSimulatedError(nil, forAPI: .loadProducts)
        await store.refresh()
        await store.purchase()
        try await waitUntil("Verified purchase should unlock") { store.isUnlocked }
        try await session.setSimulatedError(.generic(.networkError(URLError(.notConnectedToInternet))), forAPI: .loadProducts)
        await store.refresh()
        XCTAssertNil(store.product)
        XCTAssertTrue(store.isUnlocked, "Product fetch failure must not erase a valid cached StoreKit entitlement")
    }

    @MainActor
    func testPlanCatalogUsesOneSubscriptionGroupAndTheApprovedBillingPeriods() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()

        XCTAssertEqual(Set(store.availablePlans), Set([.monthly, .annual, .lifetime]))
        let monthly = try XCTUnwrap(store.product(for: .monthly))
        let annual = try XCTUnwrap(store.product(for: .annual))
        let lifetime = try XCTUnwrap(store.product(for: .lifetime))
        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(annual.type, .autoRenewable)
        XCTAssertEqual(lifetime.type, .nonConsumable)
        XCTAssertEqual(monthly.price, Decimal(string: "2.99"))
        XCTAssertEqual(annual.price, Decimal(string: "26.99"))
        XCTAssertEqual(lifetime.price, Decimal(string: "49.90"))
        let monthlyInfo = try XCTUnwrap(monthly.subscription)
        let annualInfo = try XCTUnwrap(annual.subscription)
        XCTAssertEqual(monthlyInfo.subscriptionGroupID, annualInfo.subscriptionGroupID,
                       "Monthly and annual are alternative terms for the same access")
        XCTAssertEqual(monthlyInfo.subscriptionPeriod.unit, .month)
        XCTAssertEqual(monthlyInfo.subscriptionPeriod.value, 1)
        XCTAssertEqual(annualInfo.subscriptionPeriod.unit, .year)
        XCTAssertEqual(annualInfo.subscriptionPeriod.value, 1)
        XCTAssertNil(lifetime.subscription)
        XCTAssertNil(store.activePlan)
        XCTAssertNil(store.expirationDate)
        XCTAssertFalse(store.isLifetimeUnlocked)
    }

    @MainActor
    func testMonthlyPurchaseRestoresAndCancellationKeepsAccessUntilExpiry() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        await store.purchase(.monthly)
        try await waitUntil("A verified monthly subscription should unlock the library") { store.isUnlocked }
        XCTAssertEqual(store.activePlan, .monthly)
        XCTAssertFalse(store.isLifetimeUnlocked)
        XCTAssertGreaterThan(try XCTUnwrap(store.expirationDate), Date())

        let relaunched = PurchaseStore()
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isUnlocked, "An active subscription should restore on launch")
        await relaunched.restore()
        XCTAssertEqual(relaunched.activePlan, .monthly)
        XCTAssertTrue(relaunched.isUnlocked)

        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PurchasePlan.monthly.productID
        })
        try session.disableAutoRenewForTransaction(identifier: transaction.identifier)
        await relaunched.refresh()
        XCTAssertTrue(relaunched.isUnlocked, "Canceling renewal must keep already-paid access until expiry")

        try session.expireSubscription(productIdentifier: PurchasePlan.monthly.productID)
        try await waitUntil("Expiry must remove access from stores already on screen") {
            !store.isUnlocked && !relaunched.isUnlocked
        }
        XCTAssertNil(store.activePlan)
        XCTAssertNil(store.expirationDate)
        await relaunched.restore()
        XCTAssertFalse(relaunched.isUnlocked, "Restore must not resurrect an expired subscription")
    }

    @MainActor
    func testAnnualSubscriptionRefundRemovesAccessWithoutRelaunch() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        await store.purchase(.annual)
        try await waitUntil("A verified annual subscription should unlock the library") { store.isUnlocked }
        XCTAssertEqual(store.activePlan, .annual)
        XCTAssertGreaterThan(try XCTUnwrap(store.expirationDate), Date())

        let transaction = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PurchasePlan.annual.productID
        })
        try session.refundTransaction(identifier: transaction.identifier)
        try await waitUntil("A refunded subscription must remove access while the app is open") { !store.isUnlocked }
        XCTAssertNil(store.activePlan)
        XCTAssertFalse(store.isLifetimeUnlocked)
        await store.refresh()
        XCTAssertFalse(store.isUnlocked, "A refreshed catalog must not restore a refunded subscription")
    }

    @MainActor
    func testLifetimeTakesPrecedenceAndSurvivesSubscriptionExpiryAndRefund() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        await store.purchase(.monthly)
        try await waitUntil("Monthly subscription should become active") { store.activePlan == .monthly }
        // An external purchase also covers an account that already owns both
        // products; the entitlement resolver must preserve lifetime access.
        try await session.buyProduct(identifier: PurchasePlan.lifetime.productID)
        try await waitUntil("Lifetime must take precedence over subscription access") { store.isLifetimeUnlocked }
        XCTAssertEqual(store.activePlan, .lifetime)
        XCTAssertNil(store.expirationDate, "Lifetime access must never inherit a subscription end date")

        try session.expireSubscription(productIdentifier: PurchasePlan.monthly.productID)
        await store.refresh()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(store.activePlan, .lifetime)

        try await session.buyProduct(identifier: PurchasePlan.annual.productID)
        await store.refresh()
        XCTAssertEqual(store.activePlan, .lifetime)
        let annual = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PurchasePlan.annual.productID
        })
        try session.refundTransaction(identifier: annual.identifier)
        await store.refresh()
        XCTAssertTrue(store.isUnlocked, "Refunding a subscription must not revoke a different lifetime purchase")
        XCTAssertTrue(store.isLifetimeUnlocked)
        XCTAssertEqual(store.activePlan, .lifetime)
        XCTAssertNil(store.expirationDate)
    }

    @MainActor
    func testLifetimeRefundFallsBackToAnActivePaidSubscription() async throws {
        let session = try session()
        defer { session.clearTransactions(); session.resetToDefaultState() }
        let store = PurchaseStore()
        await store.refresh()
        await store.purchase(.annual)
        try await waitUntil("Annual access should become active") { store.activePlan == .annual }
        try await session.buyProduct(identifier: PurchasePlan.lifetime.productID)
        try await waitUntil("Lifetime should take precedence") { store.isLifetimeUnlocked }

        let lifetime = try XCTUnwrap(session.allTransactions().first {
            $0.productIdentifier == PurchasePlan.lifetime.productID
        })
        try session.refundTransaction(identifier: lifetime.identifier)
        try await waitUntil("Refunding lifetime must preserve another valid paid entitlement") {
            store.isUnlocked && !store.isLifetimeUnlocked && store.activePlan == .annual
        }
        XCTAssertGreaterThan(try XCTUnwrap(store.expirationDate), Date())
        await store.restore()
        XCTAssertTrue(store.isUnlocked)
        XCTAssertEqual(store.activePlan, .annual)
    }
}
