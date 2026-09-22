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
