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
}
