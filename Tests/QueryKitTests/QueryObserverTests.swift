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
}
