import AppKit
import XCTest
@testable import TrellisFloatingBall

@MainActor
final class PaginationTests: XCTestCase {
    func testPageCountUsesTwoItemsPerPage() {
        let pagination = Pagination(pageSize: 2)

        XCTAssertEqual(pagination.pageCount(for: 0), 1)
        XCTAssertEqual(pagination.pageCount(for: 1), 1)
        XCTAssertEqual(pagination.pageCount(for: 2), 1)
        XCTAssertEqual(pagination.pageCount(for: 3), 2)
        XCTAssertEqual(pagination.pageCount(for: 5), 3)
    }

    func testNavigationExposesExpectedVisibleRanges() {
        var pagination = Pagination(pageSize: 2)

        XCTAssertEqual(pagination.visibleRange(for: 5), 0..<2)
        XCTAssertFalse(pagination.canMovePrevious(itemCount: 5))
        XCTAssertTrue(pagination.moveNext(itemCount: 5))
        XCTAssertEqual(pagination.visibleRange(for: 5), 2..<4)
        XCTAssertTrue(pagination.moveNext(itemCount: 5))
        XCTAssertEqual(pagination.visibleRange(for: 5), 4..<5)
        XCTAssertFalse(pagination.moveNext(itemCount: 5))
        XCTAssertTrue(pagination.movePrevious(itemCount: 5))
        XCTAssertEqual(pagination.visibleRange(for: 5), 2..<4)
    }

    func testClampReturnsToLastValidPageWhenItemsShrink() {
        var pagination = Pagination(pageSize: 2)
        XCTAssertTrue(pagination.moveNext(itemCount: 5))
        XCTAssertTrue(pagination.moveNext(itemCount: 5))
        XCTAssertEqual(pagination.pageIndex, 2)

        XCTAssertTrue(pagination.clamp(itemCount: 3))
        XCTAssertEqual(pagination.pageIndex, 1)
        XCTAssertEqual(pagination.visibleRange(for: 3), 2..<3)

        XCTAssertTrue(pagination.clamp(itemCount: 0))
        XCTAssertEqual(pagination.pageIndex, 0)
        XCTAssertEqual(pagination.visibleRange(for: 0), 0..<0)
    }

    func testModelIQPaginationUsesFourItemsAndCanReset() {
        var pagination = Pagination(pageSize: 4)

        XCTAssertEqual(pagination.pageCount(for: 9), 3)
        XCTAssertEqual(pagination.visibleRange(for: 9), 0..<4)
        XCTAssertTrue(pagination.moveNext(itemCount: 9))
        XCTAssertEqual(pagination.visibleRange(for: 9), 4..<8)
        XCTAssertTrue(pagination.moveNext(itemCount: 9))
        XCTAssertEqual(pagination.visibleRange(for: 9), 8..<9)
        XCTAssertTrue(pagination.reset())
        XCTAssertEqual(pagination.visibleRange(for: 9), 0..<4)
        XCTAssertFalse(pagination.reset())
    }

    func testPanelHeightOnlyIncludesFirstTwoSubscriptions() {
        let view = UsageWidgetView(
            frame: NSRect(x: 0, y: 0, width: 700, height: 900),
            displayMode: .panel
        )
        var snapshot = UsageSnapshot.placeholder
        snapshot.needsToken = false
        snapshot.subscriptions = [makeSubscription(name: "A")]
        view.snapshot = snapshot
        let oneItemHeight = view.preferredPanelSize(maxHeight: 900, maxWidth: 700).height

        snapshot.subscriptions.append(makeSubscription(name: "B"))
        view.snapshot = snapshot
        let twoItemHeight = view.preferredPanelSize(maxHeight: 900, maxWidth: 700).height

        snapshot.subscriptions.append(makeSubscription(name: "C"))
        view.snapshot = snapshot
        let threeItemHeight = view.preferredPanelSize(maxHeight: 900, maxWidth: 700).height

        XCTAssertGreaterThan(twoItemHeight, oneItemHeight)
        XCTAssertEqual(threeItemHeight, twoItemHeight)
    }

    private func makeSubscription(name: String) -> SubscriptionDisplayItem {
        SubscriptionDisplayItem(
            name: name,
            start: nil,
            expiry: nil,
            weeklyRemaining: nil,
            weeklyUsed: nil,
            weeklyTotal: nil,
            weekStart: nil,
            weekEnd: nil,
            monthlyRemaining: 5,
            monthlyTotal: 10
        )
    }
}
