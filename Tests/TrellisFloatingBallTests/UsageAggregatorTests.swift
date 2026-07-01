import Foundation
import XCTest
@testable import TrellisFloatingBall

@MainActor
final class UsageAggregatorTests: XCTestCase {
    func testMissingCredentialsClearsStaleUsageData() {
        var previous = UsageSnapshot.placeholder
        previous.primaryMode = .quotaPool
        previous.primaryAmount = 10
        previous.primaryTotal = 20
        previous.weeklyRemaining = 10
        previous.weeklyTotal = 20
        previous.monthlyRemaining = 30
        previous.monthlyTotal = 40
        previous.todayCost = 12.3
        previous.walletBalance = 53
        previous.requestCount = 99
        previous.totalTokens = 1_000
        previous.trend = [UsageTrendPoint(cost: 1, requestCount: 2, tokens: 3)]
        previous.cacheRates = [CacheRate(name: "Openai 官渠", percent: 91)]
        previous.subscriptions = [
            SubscriptionDisplayItem(
                name: "轻享月卡",
                start: nil,
                expiry: nil,
                weeklyRemaining: 10,
                weeklyUsed: 10,
                weeklyTotal: 20,
                weekStart: nil,
                weekEnd: nil,
                monthlyRemaining: 30,
                monthlyTotal: 40
            )
        ]
        previous.lastRefresh = Date()
        previous.needsToken = false

        let snapshot = UsageSnapshot.missingCredentials(previous: previous)

        XCTAssertEqual(snapshot.primaryMode, .empty)
        XCTAssertTrue(snapshot.needsToken)
        XCTAssertFalse(snapshot.isLoading)
        XCTAssertNil(snapshot.primaryAmount)
        XCTAssertNil(snapshot.weeklyRemaining)
        XCTAssertNil(snapshot.monthlyRemaining)
        XCTAssertNil(snapshot.todayCost)
        XCTAssertNil(snapshot.walletBalance)
        XCTAssertNil(snapshot.requestCount)
        XCTAssertNil(snapshot.totalTokens)
        XCTAssertTrue(snapshot.trend.isEmpty)
        XCTAssertTrue(snapshot.cacheRates.isEmpty)
        XCTAssertTrue(snapshot.subscriptions.isEmpty)
        XCTAssertNil(snapshot.lastRefresh)
        XCTAssertEqual(snapshot.statsRange, .today)
        XCTAssertEqual(snapshot.availableStatsRanges, [.today, .last7Days, .last30Days])
    }

    func testQuotaPoolSeparatesRecurringWindowAndOneShotTotals() throws {
        let subscription = try decodeSubscription(sampleSubscriptionJSON)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-27T12:00:00Z"))
        let context = try UsageAggregator.statsRangeContext(subscription: subscription, requested: .today, now: now)
        let snapshot = try UsageAggregator.makeSubscriptionSnapshot(
            subscription: subscription,
            statsRangeContext: context,
            previous: .placeholder,
            now: now
        )

        XCTAssertEqual(snapshot.primaryMode, .quotaPool)
        XCTAssertEqual(snapshot.weeklyTotal ?? 0, 713, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.weeklyRemaining ?? 0, 176.130690, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.primaryPercent ?? 0, 24.703, accuracy: 0.001)
        XCTAssertEqual(snapshot.monthlyRemaining ?? 0, 1_376.130690, accuracy: 0.000_001)

        let monthlyCard = try XCTUnwrap(snapshot.subscriptions.first { $0.name == "月卡套餐" })
        XCTAssertEqual(monthlyCard.weeklyTotal ?? 0, 600, accuracy: 0.000_001)
        XCTAssertEqual(monthlyCard.monthlyTotal ?? 0, 2_400, accuracy: 0.000_001)
        XCTAssertEqual(monthlyCard.monthlyRemaining ?? 0, 1_371.871859, accuracy: 0.000_001)

        let rewardCard = try XCTUnwrap(snapshot.subscriptions.first { $0.name == "奖励额度" })
        XCTAssertNil(rewardCard.weeklyTotal)
        XCTAssertEqual(rewardCard.monthlyTotal ?? 0, 108, accuracy: 0.000_001)
        XCTAssertEqual(rewardCard.monthlyRemaining ?? -1, 0, accuracy: 0.000_001)

        let promoCard = try XCTUnwrap(snapshot.subscriptions.first { $0.name == "活动 5U" })
        XCTAssertNil(promoCard.weeklyTotal)
        XCTAssertEqual(promoCard.monthlyTotal ?? 0, 5, accuracy: 0.000_001)
        XCTAssertEqual(promoCard.monthlyRemaining ?? 0, 4.258831, accuracy: 0.000_001)
    }

    func testStatsRangesUseEarliestStartedMonthlyWindowSubscription() throws {
        let subscription = try decodeSubscription(multipleMonthlySubscriptionsJSON)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-23T12:00:00Z"))
        let formatter = ISO8601DateFormatter()

        let windowContext = try UsageAggregator.statsRangeContext(
            subscription: subscription,
            requested: .quotaWeek,
            now: now
        )
        XCTAssertEqual(windowContext.effective, .quotaWeek)
        XCTAssertEqual(windowContext.availableRanges, [.quotaWeek, .subscriptionPeriod, .today, .last7Days, .last30Days])
        XCTAssertEqual(windowContext.start, formatter.date(from: "2026-06-17T00:00:00Z"))
        XCTAssertEqual(windowContext.end, now)

        let monthlyContext = try UsageAggregator.statsRangeContext(
            subscription: subscription,
            requested: .subscriptionPeriod,
            now: now
        )
        XCTAssertEqual(monthlyContext.effective, .subscriptionPeriod)
        XCTAssertEqual(monthlyContext.start, formatter.date(from: "2026-06-10T00:00:00Z"))
        XCTAssertEqual(monthlyContext.end, now)
    }

    func testStatsJSONParserReadsRequiredFieldsFromFile() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("krill-stats-parser-\(UUID().uuidString).json")
        try statsJSON.write(to: fileURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let envelope = try StatsJSONParser.decodeEnvelope(from: fileURL, trendLimit: 2)
        let payload = try XCTUnwrap(envelope.data)

        XCTAssertEqual(envelope.code, 0)
        XCTAssertEqual(envelope.success, true)
        XCTAssertEqual(payload.totalCostUsd, "12.3456")
        XCTAssertEqual(payload.totalRequests, 123)
        XCTAssertEqual(payload.totalTokens, 456_789)
        XCTAssertEqual(payload.trend?.count, 2)
        XCTAssertEqual(payload.trend?.first?.requestCount, 1)
        XCTAssertEqual(payload.trend?.last?.totalTokens, 30)
        XCTAssertEqual(payload.channelCacheRates?.first?.channelName, "OpenAI \"主\" 渠道")
        XCTAssertEqual(payload.channelCacheRates?.first?.cacheRate ?? 0, 0.8123, accuracy: 0.000_001)
    }

    func testBalanceModeTakesOverWhenQuotaPoolIsExhausted() throws {
        let subscription = try decodeSubscription(exhaustedQuotaWithWalletJSON)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-27T12:00:00Z"))
        let context = try UsageAggregator.statsRangeContext(subscription: subscription, requested: .today, now: now)
        let snapshot = try UsageAggregator.makeSubscriptionSnapshot(
            subscription: subscription,
            statsRangeContext: context,
            previous: .placeholder,
            now: now
        )

        XCTAssertEqual(snapshot.primaryMode, .balance)
        XCTAssertEqual(snapshot.primaryAmount ?? 0, 53, accuracy: 0.000_001)
        XCTAssertNil(snapshot.primaryPercent)
        XCTAssertEqual(snapshot.weeklyTotal ?? 0, 10, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.weeklyRemaining ?? -1, 0, accuracy: 0.000_001)
    }

    func testWalletOnlyUsesBalanceMode() throws {
        let subscription = try decodeSubscription(walletOnlyJSON)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-27T12:00:00Z"))
        let context = try UsageAggregator.statsRangeContext(subscription: subscription, requested: .quotaWeek, now: now)
        let snapshot = try UsageAggregator.makeSubscriptionSnapshot(
            subscription: subscription,
            statsRangeContext: context,
            previous: .placeholder,
            now: now
        )

        XCTAssertEqual(context.effective, .today)
        XCTAssertEqual(snapshot.primaryMode, .balance)
        XCTAssertEqual(snapshot.primaryAmount ?? 0, 42.5, accuracy: 0.000_001)
        XCTAssertNil(snapshot.weeklyTotal)
        XCTAssertNil(snapshot.primaryPercent)
    }

    func testExhaustedQuotaWithoutWalletUsesEmptyMode() throws {
        let subscription = try decodeSubscription(exhaustedQuotaNoWalletJSON)
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-06-27T12:00:00Z"))
        let context = try UsageAggregator.statsRangeContext(subscription: subscription, requested: .today, now: now)
        let snapshot = try UsageAggregator.makeSubscriptionSnapshot(
            subscription: subscription,
            statsRangeContext: context,
            previous: .placeholder,
            now: now
        )

        XCTAssertEqual(snapshot.primaryMode, .empty)
        XCTAssertNil(snapshot.primaryAmount)
        XCTAssertNil(snapshot.primaryPercent)
        XCTAssertEqual(snapshot.weeklyTotal ?? 0, 600, accuracy: 0.000_001)
        XCTAssertEqual(snapshot.weeklyRemaining ?? -1, 0, accuracy: 0.000_001)
    }
}

private func decodeSubscription(_ json: String) throws -> SubscriptionEnvelope {
    try JSONDecoder().decode(SubscriptionEnvelope.self, from: Data(json.utf8))
}

private let sampleSubscriptionJSON = """
{
  "code": 0,
  "success": true,
  "data": {
    "credit_balance_usd": "53.011780",
    "welfare_balance_usd": "0",
    "subscriptions": [
      {
        "plan": {
          "active": true,
          "billing_type": "usd_daily",
          "daily_quota_usd": "5.000000",
          "duration_days": 1,
          "name": "活动 5U"
        },
        "quota": {
          "daily_limit_usd": "0.000000",
          "forwarded_limit_usd": "5.000000",
          "forwarded_remaining_usd": "4.258831",
          "forwarded_used_usd": "0.741169",
          "remaining_usd": "0",
          "used_usd": "0.000000"
        },
        "subscription_end_at": "2026-06-27T14:56:21.248230Z",
        "subscription_start_at": "2026-06-26T14:56:21.248230Z",
        "total_used_usd": "0.741169"
      },
      {
        "plan": {
          "active": true,
          "billing_type": "usd_monthly",
          "daily_quota_usd": "0.000000",
          "duration_days": 30,
          "name": "奖励额度"
        },
        "quota": {
          "daily_limit_usd": "108.000000",
          "forwarded_limit_usd": "0.000000",
          "forwarded_remaining_usd": "0",
          "forwarded_used_usd": "0.000000",
          "remaining_usd": "0",
          "used_usd": "108.000000"
        },
        "subscription_end_at": "2026-07-15T07:01:10.923753Z",
        "subscription_start_at": "2026-06-15T07:01:10.923753Z",
        "total_used_usd": "108.000000"
      },
      {
        "plan": {
          "active": true,
          "billing_type": "usd_weekly",
          "daily_quota_usd": "450.000000",
          "duration_days": 30,
          "name": "月卡套餐"
        },
        "quota": {
          "daily_limit_usd": "600.000000",
          "forwarded_limit_usd": "0.000000",
          "forwarded_remaining_usd": "0",
          "forwarded_used_usd": "0.000000",
          "remaining_usd": "171.871859",
          "used_usd": "428.128141",
          "window_reset_at": "2026-06-28T16:00:00Z",
          "window_start_at": "2026-06-21T16:00:00Z"
        },
        "subscription_end_at": "2026-07-16T07:01:10.923753Z",
        "subscription_start_at": "2026-06-15T07:01:10.923753Z",
        "total_used_usd": "552.548677"
      }
    ]
  }
}
"""

private let multipleMonthlySubscriptionsJSON = """
{
  "code": 0,
  "success": true,
  "data": {
    "credit_balance_usd": "0",
    "welfare_balance_usd": "0",
    "subscriptions": [
      {
        "plan": {
          "active": true,
          "billing_type": "usd_monthly",
          "daily_quota_usd": "0.000000",
          "duration_days": 30,
          "name": "世界杯奖励"
        },
        "quota": {
          "daily_limit_usd": "20.000000",
          "remaining_usd": "15.000000",
          "used_usd": "5.000000"
        },
        "subscription_end_at": "2026-07-01T00:00:00Z",
        "subscription_start_at": "2026-06-01T00:00:00Z",
        "total_used_usd": "5.000000"
      },
      {
        "plan": {
          "active": true,
          "billing_type": "usd_weekly",
          "daily_quota_usd": "100.000000",
          "duration_days": 30,
          "name": "后开始月卡"
        },
        "quota": {
          "daily_limit_usd": "100.000000",
          "remaining_usd": "90.000000",
          "used_usd": "10.000000",
          "window_reset_at": "2026-06-29T00:00:00Z",
          "window_start_at": "2026-06-22T00:00:00Z"
        },
        "subscription_end_at": "2026-07-15T00:00:00Z",
        "subscription_start_at": "2026-06-15T00:00:00Z",
        "total_used_usd": "10.000000"
      },
      {
        "plan": {
          "active": true,
          "billing_type": "usd_weekly",
          "daily_quota_usd": "100.000000",
          "duration_days": 30,
          "name": "最早月卡"
        },
        "quota": {
          "daily_limit_usd": "100.000000",
          "remaining_usd": "60.000000",
          "used_usd": "40.000000",
          "window_reset_at": "2026-06-24T00:00:00Z",
          "window_start_at": "2026-06-17T00:00:00Z"
        },
        "subscription_end_at": "2026-07-10T00:00:00Z",
        "subscription_start_at": "2026-06-10T00:00:00Z",
        "total_used_usd": "40.000000"
      }
    ]
  }
}
"""

private let statsJSON = """
{
  "code": 0,
  "success": true,
  "message": null,
  "data": {
    "total_cost_usd": "12.3456",
    "total_requests": 123,
    "total_tokens": 456789,
    "channel_cache_rates": [
      {
        "channel_name": "OpenAI \\"主\\" 渠道",
        "cache_rate": 0.8123
      }
    ],
    "trend": [
      {
        "request_count": 1,
        "total_cost_usd": "0.1",
        "total_tokens": 10
      },
      {
        "request_count": 2,
        "total_cost_usd": "0.2",
        "total_tokens": 20
      },
      {
        "request_count": 3,
        "total_cost_usd": "0.3",
        "total_tokens": 30
      }
    ]
  }
}
"""

private let exhaustedQuotaWithWalletJSON = """
{
  "code": 0,
  "success": true,
  "data": {
    "credit_balance_usd": "53.000000",
    "welfare_balance_usd": "0",
    "subscriptions": [
      {
        "plan": {
          "active": true,
          "billing_type": "usd_daily",
          "daily_quota_usd": "10.000000",
          "duration_days": 1,
          "name": "日卡"
        },
        "quota": {
          "daily_limit_usd": "10.000000",
          "remaining_usd": "0",
          "used_usd": "10.000000"
        },
        "subscription_end_at": "2026-06-27T18:00:00Z",
        "subscription_start_at": "2026-06-26T18:00:00Z",
        "total_used_usd": "10.000000"
      }
    ]
  }
}
"""

private let walletOnlyJSON = """
{
  "code": 0,
  "success": true,
  "data": {
    "credit_balance_usd": "42.500000",
    "welfare_balance_usd": "0",
    "subscriptions": []
  }
}
"""

private let exhaustedQuotaNoWalletJSON = """
{
  "code": 0,
  "success": true,
  "data": {
    "credit_balance_usd": "0",
    "welfare_balance_usd": "0",
    "subscriptions": [
      {
        "plan": {
          "active": true,
          "billing_type": "usd_weekly",
          "daily_quota_usd": "450.000000",
          "duration_days": 30,
          "name": "月卡套餐"
        },
        "quota": {
          "daily_limit_usd": "600.000000",
          "remaining_usd": "0",
          "used_usd": "600.000000",
          "window_reset_at": "2026-06-28T16:00:00Z",
          "window_start_at": "2026-06-21T16:00:00Z"
        },
        "subscription_end_at": "2026-07-16T07:01:10.923753Z",
        "subscription_start_at": "2026-06-15T07:01:10.923753Z",
        "total_used_usd": "2400.000000"
      }
    ]
  }
}
"""
