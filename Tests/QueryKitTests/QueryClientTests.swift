import Testing

@testable import QueryKit

enum TestKey: QueryKey { case users, posts }

@Suite("QueryClient tests")
struct QueryClientTests {
    @Test("Fetch returns cached data within stale time")
    @MainActor
    func testCachedData() async throws {
        let client = QueryClient()
        var callCount = 0

        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["A", "B"]
        }

        let first = try await client.fetch(key: TestKey.users, staleTime: 120, loader: loader)
        let second = try await client.fetch(key: TestKey.users, staleTime: 120, loader: loader)

        #expect(first == ["A", "B"])
        #expect(second == ["A", "B"])
        #expect(callCount == 1)
    }

    @Test("Invalidating causes refresh")
    @MainActor
    func testInvalidationRefresh() async throws {
        let client = QueryClient()
        var callCount = 0

        let loader: @Sendable () async throws -> Int = { @MainActor in
            callCount += 1
            return callCount
        }

        _ = try await client.fetch(key: TestKey.users, loader: loader)
        await client.invalidate(TestKey.users)
        let value = try await client.fetch(key: TestKey.users, loader: loader)

        #expect(value == 2)
    }

    @Test("setQueryData is served from cache and pushed to observers")
    @MainActor
    func testSetQueryData() async throws {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 60)
        await Task.yield() // let configure's subscribe Task run

        await client.setQueryData(TestKey.users, value: ["seeded"])

        #expect(observer.phase.value == ["seeded"])

        let cached = try await client.fetch(key: TestKey.users, staleTime: 60) { ["loaded"] }
        #expect(cached == ["seeded"])
    }
}
