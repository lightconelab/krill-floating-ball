import Foundation

struct SubscriptionPagination: Equatable {
    static let pageSize = 2

    private(set) var pageIndex = 0

    func pageCount(for itemCount: Int) -> Int {
        max(1, (max(0, itemCount) + Self.pageSize - 1) / Self.pageSize)
    }

    func visibleRange(for itemCount: Int) -> Range<Int> {
        let safeItemCount = max(0, itemCount)
        let start = min(pageIndex * Self.pageSize, safeItemCount)
        let end = min(start + Self.pageSize, safeItemCount)
        return start..<end
    }

    func canMovePrevious(itemCount: Int) -> Bool {
        itemCount > 0 && pageIndex > 0
    }

    func canMoveNext(itemCount: Int) -> Bool {
        pageIndex + 1 < pageCount(for: itemCount)
    }

    @discardableResult
    mutating func movePrevious(itemCount: Int) -> Bool {
        guard canMovePrevious(itemCount: itemCount) else {
            return false
        }
        pageIndex -= 1
        return true
    }

    @discardableResult
    mutating func moveNext(itemCount: Int) -> Bool {
        guard canMoveNext(itemCount: itemCount) else {
            return false
        }
        pageIndex += 1
        return true
    }

    @discardableResult
    mutating func clamp(itemCount: Int) -> Bool {
        let validPageIndex = min(pageIndex, pageCount(for: itemCount) - 1)
        guard pageIndex != validPageIndex else {
            return false
        }
        pageIndex = validPageIndex
        return true
    }
}
