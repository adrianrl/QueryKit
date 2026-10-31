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

        _ = try await client.fetch(key: TestKey.users, staleTime: 60, loader: loader)
        await client.invalidate(TestKey.users)
        let value = try await client.fetch(key: TestKey.users, staleTime: 60, loader: loader)

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

    @Test("invalidateAll empties the cache and refetches observed queries")
    @MainActor
    func testInvalidateAll() async throws {
        let client = QueryClient()
        let observer = QueryObserver<Int>()
        observer.configure(client: client, key: TestKey.users, staleTime: 60)
        await Task.yield() // let configure's subscribe Task run

        var callCount = 0
        await observer.fetch(loader: { @MainActor in
            callCount += 1
            return callCount
        })
        _ = try await client.fetch(key: TestKey.posts, staleTime: 60) { "cached" }

        await client.invalidateAll()
        // invalidation notifies observers from a Task; give it a turn, then let the refetch finish
        for _ in 0..<5 { await Task.yield() }

        #expect(callCount == 2)
        #expect(observer.phase.value == 2)
        let posts = try await client.fetch(key: TestKey.posts, staleTime: 60) { "reloaded" }
        #expect(posts == "reloaded")
    }

    @Test("A query's staleTime wins over the client's defaultStaleTime")
    @MainActor
    func testStaleTimePrecedence() async throws {
        let client = QueryClient(defaultStaleTime: 0)
        var callCount = 0
        let loader: @Sendable () async throws -> Int = { @MainActor in
            callCount += 1
            return callCount
        }

        // nil falls back to defaultStaleTime (0): every fetch calls the loader
        _ = try await client.fetch(key: TestKey.users, loader: loader)
        _ = try await client.fetch(key: TestKey.users, loader: loader)
        #expect(callCount == 2)

        // an explicit staleTime is honoured even though the default is 0
        _ = try await client.fetch(key: TestKey.users, staleTime: 60, loader: loader)
        #expect(callCount == 2)
    }

    @Test("overrideStaleTime wins over a query's own staleTime")
    @MainActor
    func testOverrideStaleTime() async throws {
        let client = QueryClient(seed: [TestKey.users: ["seeded"]], overrideStaleTime: .infinity)
        var callCount = 0
        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["network"]
        }

        let value = try await client.fetch(key: TestKey.users, staleTime: 0, loader: loader)

        #expect(value == ["seeded"])
        #expect(callCount == 0)
    }
}
