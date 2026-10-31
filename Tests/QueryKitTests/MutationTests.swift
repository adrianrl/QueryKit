import Testing

@testable import QueryKit

@Suite("Mutation tests")
struct MutationTests {
    private enum TestError: Error { case failed }

    /// Reads the cached value for `key`, or `nil` if there is none.
    private func cached<V: Sendable>(_ client: QueryClient, _ key: TestKey, as: V.Type) async -> V? {
        try? await client.fetch(key: key, staleTime: 60) { () -> V in throw TestError.failed }
    }

    @Test("mutate returns the result and moves phase to success")
    @MainActor
    func testSuccess() async {
        let observer = MutationObserver<Int>()
        observer.configure(client: QueryClient())

        let result = await observer.mutate { 42 }

        #expect(result == 42)
        #expect(observer.phase.value == 42)
        #expect(observer.error == nil)
    }

    @Test("A failed operation moves phase to failure and returns nil")
    @MainActor
    func testFailure() async {
        let observer = MutationObserver<Int>()
        observer.configure(client: QueryClient())

        let result = await observer.mutate { throw TestError.failed }

        #expect(result == nil)
        #expect(observer.error is TestError)
    }

    @Test("reset returns to idle and clears the error")
    @MainActor
    func testReset() async {
        let observer = MutationObserver<Int>()
        observer.configure(client: QueryClient())

        await observer.mutate { throw TestError.failed }
        #expect(observer.error is TestError)

        observer.reset()

        #expect(observer.error == nil)
        #expect(observer.phase.value == nil)
        if case .idle = observer.phase {} else { Issue.record("Expected idle after reset") }
    }

    @Test("Without a client, mutate doesn't run and phase stays idle")
    @MainActor
    func testNoClient() async {
        let observer = MutationObserver<Int>()
        var ran = false

        let result = await observer.mutate { @MainActor in
            ran = true
            return 1
        }

        #expect(result == nil)
        #expect(!ran)
        #expect(!observer.isLoading)
    }

    @Test("invalidate: removes each key from the cache on success")
    @MainActor
    func testInvalidate() async {
        let client = QueryClient(seed: [TestKey.users: ["a"], TestKey.posts: ["p"]])

        try? await client.mutate(invalidate: [TestKey.users]) { }

        #expect(await cached(client, .users, as: [String].self) == nil)
        #expect(await cached(client, .posts, as: [String].self) == ["p"])
    }

    @Test("Optimistic change is visible while the operation runs")
    @MainActor
    func testOptimisticVisibleDuringOperation() async throws {
        let client = QueryClient(seed: [TestKey.users: ["a", "b"]])
        var seenDuringOperation: [String]?

        try await client.mutate(updating: [
            .init(TestKey.users) { (users: inout [String]) in users.removeAll { $0 == "a" } }
        ]) { @MainActor in
            seenDuringOperation = await self.cached(client, .users, as: [String].self)
        }

        #expect(seenDuringOperation == ["b"])
        #expect(await cached(client, .users, as: [String].self) == ["b"])
    }

    @Test("A failed operation rolls back every optimistic change")
    @MainActor
    func testRollback() async {
        let client = QueryClient(seed: [TestKey.users: ["a"], TestKey.posts: [1]])
        let observer = MutationObserver<Void>()
        observer.configure(client: client)

        await observer.mutate(
            updating: .init(TestKey.users) { (users: inout [String]) in users.append("b") },
                      .init(TestKey.posts) { (posts: inout [Int]) in posts.append(2) }
        ) {
            throw TestError.failed
        }

        #expect(observer.error is TestError)
        #expect(await cached(client, .users, as: [String].self) == ["a"])
        #expect(await cached(client, .posts, as: [Int].self) == [1])
    }

    @Test("Rollback restores the original value when two updates touch the same key")
    @MainActor
    func testRollbackSameKey() async {
        let client = QueryClient(seed: [TestKey.users: ["a"]])

        try? await client.mutate(updating: [
            .init(TestKey.users) { (users: inout [String]) in users.append("b") },
            .init(TestKey.users) { (users: inout [String]) in users.append("c") }
        ]) {
            throw TestError.failed
        }

        #expect(await cached(client, .users, as: [String].self) == ["a"])
    }

    @Test("onSuccess runs with the result even when other keys are invalidated")
    @MainActor
    func testOnSuccessWithInvalidate() async throws {
        let client = QueryClient(seed: [TestKey.users: ["a"], TestKey.posts: ["p"]])

        let saved = try await client.mutate(
            updating: [.init(TestKey.users,
                             optimistic: { (users: inout [String]) in users.append("draft") },
                             onSuccess: { users, saved in users[users.count - 1] = saved })],
            invalidate: [TestKey.posts]
        ) {
            "saved"
        }

        #expect(saved == "saved")
        #expect(await cached(client, .users, as: [String].self) == ["a", "saved"])
        #expect(await cached(client, .posts, as: [String].self) == nil)
    }

    @Test("An update whose type doesn't match the cached value traps in debug builds")
    func testTypeMismatchTraps() async {
        await #expect(processExitsWith: .failure) {
            let client = QueryClient(seed: [TestKey.users: ["a"]])

            try? await client.mutate(updating: [
                .init(TestKey.users) { (users: inout [Int]) in users.append(1) }
            ]) { }
        }
    }
}
