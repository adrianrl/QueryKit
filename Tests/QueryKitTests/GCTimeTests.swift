import Foundation
import Testing

@testable import QueryKit

@Suite("gcTime tests")
struct GCTimeTests {
    private enum TestError: Error { case notCached }

    /// Reads the cached value for `key` without loading, or `nil` if it was evicted.
    private func cached<V: Sendable>(_ client: QueryClient, _ key: TestKey, as: V.Type) async -> V? {
        try? await client.fetch(key: key, staleTime: .infinity) { () -> V in throw TestError.notCached }
    }

    /// Lets the subscribe/unsubscribe Tasks started by `configure` and `deinit` run.
    private func settle() async {
        for _ in 0..<5 { await Task.yield() }
    }

    @Test("An entry with no observers is evicted after the default gcTime")
    @MainActor
    func testUnobservedEntryEvicted() async throws {
        let client = QueryClient(defaultGCTime: 0.05)

        await client.setQueryData(TestKey.users, value: ["a"])
        #expect(await cached(client, .users, as: [String].self) == ["a"])

        try await Task.sleep(for: .milliseconds(150))
        #expect(await cached(client, .users, as: [String].self) == nil)
    }

    @Test("An entry with an observer is not evicted")
    @MainActor
    func testObservedEntryKept() async throws {
        let client = QueryClient(defaultGCTime: 0.05)
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 60)
        await settle()

        await observer.fetch { ["a"] }
        try await Task.sleep(for: .milliseconds(150))

        #expect(await cached(client, .users, as: [String].self) == ["a"])
        withExtendedLifetime(observer) {}
    }

    @Test("The timer starts when the last observer goes away")
    @MainActor
    func testEvictedAfterObserverDeinit() async throws {
        let client = QueryClient(defaultGCTime: 0.05)
        var observer: QueryObserver<[String]>? = QueryObserver()
        observer?.configure(client: client, key: TestKey.users, staleTime: 60)
        await settle()
        await observer?.fetch { ["a"] }

        observer = nil
        await settle()

        #expect(await cached(client, .users, as: [String].self) == ["a"])
        try await Task.sleep(for: .milliseconds(150))
        #expect(await cached(client, .users, as: [String].self) == nil)
    }

    @Test("An observer that arrives before the timer fires cancels the eviction")
    @MainActor
    func testResubscribeCancelsEviction() async throws {
        let client = QueryClient(defaultGCTime: 0.1)
        await client.setQueryData(TestKey.users, value: ["a"])

        try await Task.sleep(for: .milliseconds(30))
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 60)
        await settle()

        try await Task.sleep(for: .milliseconds(200))
        #expect(await cached(client, .users, as: [String].self) == ["a"])
        withExtendedLifetime(observer) {}
    }

    @Test("A query's gcTime overrides the client default, and the longest one wins")
    @MainActor
    func testPerQueryGCTime() async throws {
        let client = QueryClient(defaultGCTime: 0.05)
        var short: QueryObserver<[String]>? = QueryObserver()
        var long: QueryObserver<[String]>? = QueryObserver()
        short?.configure(client: client, key: TestKey.users, staleTime: 60, gcTime: 0.05)
        long?.configure(client: client, key: TestKey.users, staleTime: 60, gcTime: 0.4)
        await settle()
        await long?.fetch { ["a"] }

        short = nil
        long = nil
        await settle()

        try await Task.sleep(for: .milliseconds(150))
        #expect(await cached(client, .users, as: [String].self) == ["a"])
        try await Task.sleep(for: .milliseconds(450))
        #expect(await cached(client, .users, as: [String].self) == nil)
    }

    @Test("gcTime of infinity never evicts")
    @MainActor
    func testInfiniteGCTime() async throws {
        let client = QueryClient(seed: [TestKey.users: ["a"]], defaultGCTime: .infinity)

        try await Task.sleep(for: .milliseconds(100))
        #expect(await cached(client, .users, as: [String].self) == ["a"])
    }

    @Test("Seeded entries count from creation")
    @MainActor
    func testSeedEvicted() async throws {
        let client = QueryClient(seed: [TestKey.users: ["a"]], defaultGCTime: 0.05)

        try await Task.sleep(for: .milliseconds(150))
        #expect(await cached(client, .users, as: [String].self) == nil)
    }
}
