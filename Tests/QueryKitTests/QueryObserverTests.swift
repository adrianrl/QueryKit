import Testing

@testable import QueryKit

@Suite("QueryObserver tests")
struct QueryObserverTests {
    @Test("Query observer success")
    @MainActor
    func testQueryObserverSuccess() async throws {
        let client = QueryClient()

        let observer = QueryObserver(
            client: client,
            key: TestKey.users,
            staleTime: 60
        ) {
            ["MockUser"]
        }

        await observer.fetch()

        if case .success(let users) = observer.phase {
            #expect(users == ["MockUser"])
        }
    }

    @Test("Query observer fetch with loader")
    @MainActor
    func testQueryObserverFetchWithLoader() async throws {
        let client = QueryClient()

        let observer = QueryObserver(
            client: client,
            key: TestKey.users,
            staleTime: 60
        ) {
            ["MockUser"]
        }

        await observer.fetch(loader: { ["MockUser"] })

        if case .success(let users) = observer.phase {
            #expect(users == ["MockUser"])
        }
    }

    @Test("fetch(loader:) persists for later fetch()")
    @MainActor
    func testFetchLoaderPersists() async {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        var callCount = 0
        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["from-task"]
        }

        await observer.fetch(loader: loader)
        await observer.fetch()

        #expect(callCount == 2)
        if case .success(let users) = observer.phase {
            #expect(users == ["from-task"])
        } else {
            Issue.record("Expected success after persisted fetch")
        }
    }

    @Test("configure with nil loader does not clobber a persisted loader")
    @MainActor
    func testConfigureNilDoesNotClobberPersistedLoader() async {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        var callCount = 0
        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["from-task"]
        }

        await observer.fetch(loader: loader)
        observer.configure(client: client, key: TestKey.users, staleTime: 0)
        await observer.fetch()

        #expect(callCount == 2)
        if case .success(let users) = observer.phase {
            #expect(users == ["from-task"])
        } else {
            Issue.record("Expected success after configure(nil)")
        }
    }

    @Test("changing key resets the persisted loader")
    @MainActor
    func testKeyChangeResetsLoader() async {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        await observer.fetch { ["from-task"] }

        observer.configure(client: client, key: TestKey.posts, staleTime: 0)
        await observer.fetch()

        if case .idle = observer.phase {
            // expected: no loader registered for the new key
        } else {
            Issue.record("Expected idle after key change without a loader")
        }
    }

    @Test("invalidate refetches with the persisted loader")
    @MainActor
    func testInvalidateUsesPersistedLoader() async {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        var callCount = 0
        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["from-task"]
        }

        await observer.fetch(loader: loader)
        await observer.didInvalidate()

        #expect(callCount == 2)
        if case .success(let users) = observer.phase {
            #expect(users == ["from-task"])
        } else {
            Issue.record("Expected success after invalidate refetch")
        }
    }

    @Test("Failed revalidation keeps the previous value and reports the error")
    @MainActor
    func testFailedRevalidationKeepsValue() async throws {
        let observer = makeObserver()

        await observer.fetch(loader: { ["A"] })
        await observer.fetch(loader: { throw TestError.boom })

        #expect(observer.phase.value == ["A"])
        #expect(observer.error is TestError)
        #expect(observer.isFetching == false)
    }

    @Test("Failure with no value to fall back on surfaces in the phase")
    @MainActor
    func testFailureWithoutValue() async throws {
        let observer = makeObserver()

        await observer.fetch(loader: { throw TestError.boom })

        #expect(observer.phase.value == nil)
        #expect(observer.phase.error is TestError)
        #expect(observer.error is TestError)
    }

    @Test("A successful fetch clears a previous error")
    @MainActor
    func testSuccessClearsError() async throws {
        let observer = makeObserver()

        await observer.fetch(loader: { throw TestError.boom })
        await observer.fetch(loader: { ["A"] })

        #expect(observer.phase.value == ["A"])
        #expect(observer.error == nil)
    }

    @Test("Revalidation keeps the value visible while in flight")
    @MainActor
    func testRevalidationKeepsValueWhileInFlight() async throws {
        let observer = makeObserver()

        await observer.fetch(loader: { ["A"] })

        let gate = Gate()
        let task = Task {
            await observer.fetch(loader: {
                await gate.wait()
                return ["B"]
            })
        }

        await gate.waitUntilEntered()

        // The stale value stays on screen instead of flashing back to `.loading`.
        #expect(observer.phase.value == ["A"])
        #expect(observer.isFetching)

        await gate.open()
        await task.value

        #expect(observer.phase.value == ["B"])
        #expect(observer.isFetching == false)
    }

    @Test("The first fetch does report a loading phase")
    @MainActor
    func testFirstFetchReportsLoading() async throws {
        let observer = makeObserver()

        let gate = Gate()
        let task = Task {
            await observer.fetch(loader: {
                await gate.wait()
                return ["A"]
            })
        }

        await gate.waitUntilEntered()

        #expect(observer.phase.isLoading)
        #expect(observer.isFetching)

        await gate.open()
        await task.value
    }

    // MARK: - Helpers

    @MainActor
    private func makeObserver() -> QueryObserver<[String]> {
        QueryObserver(
            client: QueryClient(),
            key: TestKey.users,
            staleTime: 0
        ) {
            []
        }
    }

    @Test("fetch(loader:) serves a fresh cached value without calling the loader")
    @MainActor
    func testFetchLoaderHonoursStaleTime() async {
        let client = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 60)

        var callCount = 0
        let loader: @Sendable () async throws -> [String] = { @MainActor in
            callCount += 1
            return ["from-network"]
        }

        await observer.fetch(loader: loader)
        await observer.fetch(loader: loader)

        #expect(callCount == 1)
        #expect(observer.phase.value == ["from-network"])
    }

    @Test("Changing the client moves the subscription to the new one")
    @MainActor
    func testClientChangeResubscribes() async {
        let first = QueryClient()
        let second = QueryClient()
        let observer = QueryObserver<[String]>()
        observer.configure(client: first, key: TestKey.users, staleTime: 60)
        for _ in 0..<5 { await Task.yield() }

        observer.configure(client: second, key: TestKey.users, staleTime: 60)
        for _ in 0..<5 { await Task.yield() }

        await first.setQueryData(TestKey.users, value: ["from-first"])
        #expect(observer.phase.value == nil)

        await second.setQueryData(TestKey.users, value: ["from-second"])
        #expect(observer.phase.value == ["from-second"])
    }

    @Test("A stale cached value is shown while it reloads")
    @MainActor
    func testStaleValueShownWhileReloading() async {
        let client = QueryClient(seed: [TestKey.users: ["old"]])
        let gate = Gate()
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        let fetch = Task {
            await observer.fetch {
                await gate.wait()
                return ["new"]
            }
        }
        await gate.waitUntilEntered()

        #expect(observer.phase.value == ["old"])
        #expect(observer.isFetching)

        await gate.open()
        await fetch.value

        #expect(observer.phase.value == ["new"])
        #expect(!observer.isFetching)
    }

    @Test("A failed reload of a stale value keeps it and reports the error")
    @MainActor
    func testStaleValueKeptOnFailedReload() async {
        let client = QueryClient(seed: [TestKey.users: ["old"]])
        let observer = QueryObserver<[String]>()
        observer.configure(client: client, key: TestKey.users, staleTime: 0)

        await observer.fetch { throw TestError.boom }

        #expect(observer.phase.value == ["old"])
        #expect(observer.error is TestError)
    }
}

private enum TestError: Error { case boom }

/// Lets a test observe an observer mid-fetch: the loader parks in ``wait()``
/// until the test calls ``open()``.
private actor Gate {
    private var isOpen = false
    private var hasEntered = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called from the loader. Signals that the fetch is in flight, then
    /// suspends until the gate opens.
    func wait() async {
        hasEntered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters = []

        guard !isOpen else { return }

        await withCheckedContinuation { openWaiters.append($0) }
    }

    /// Called from the test. Returns once the loader has reached ``wait()``.
    func waitUntilEntered() async {
        guard !hasEntered else { return }

        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func open() {
        isOpen = true
        openWaiters.forEach { $0.resume() }
        openWaiters = []
    }
}
