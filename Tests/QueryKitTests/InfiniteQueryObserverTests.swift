import Foundation
import Observation
import Testing

@testable import QueryKit

@Suite("InfiniteQueryObserver tests")
@MainActor
struct InfiniteQueryObserverTests {
    /// Page-number pagination over 3 pages: page N is `["N"]`, page 3 is the last.
    @MainActor
    private final class Pages {
        var loaded: [Int] = []
        var delay: [Int: Duration] = [:]
        var failing: Set<Int> = []

        func makeObserver(
            client: QueryClient,
            initialPageParam: Int = 1,
            staleTime: TimeInterval = 60
        ) -> InfiniteQueryObserver<[String], Int> {
            let observer = InfiniteQueryObserver<[String], Int>()
            observer.configure(
                client: client,
                key: TestKey.posts,
                staleTime: staleTime,
                initialPageParam: initialPageParam,
                getNextPageParam: { _, _, last in last < 3 ? last + 1 : nil },
                pageLoader: { @MainActor page in
                    self.loaded.append(page)
                    if let delay = self.delay[page] { try await Task.sleep(for: delay) }
                    if self.failing.contains(page) { throw TestError.failed }
                    return ["\(page)"]
                }
            )
            return observer
        }
    }

    private enum TestError: Error { case failed }

    @Test("fetch loads the first page from initialPageParam")
    func firstFetch() async {
        let pages = Pages()
        let observer = pages.makeObserver(client: QueryClient())

        await observer.fetch()

        #expect(observer.phase.value == InfiniteData(pages: [["1"]], pageParams: [1]))
        #expect(observer.hasNextPage)
        #expect(!observer.isFetchingNextPage)
    }

    @Test("A new observer of stale pages shows them and reloads every one")
    func stalePagesReloaded() async {
        let client = QueryClient(seed: [
            TestKey.posts: InfiniteData<[String], Int>(pages: [["old1"], ["old2"]], pageParams: [1, 2])
        ])
        let pages = Pages()
        pages.delay[1] = .milliseconds(50)
        let observer = pages.makeObserver(client: client, staleTime: 0)

        let fetch = Task { await observer.fetch() }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(observer.phase.value?.pages == [["old1"], ["old2"]])

        await fetch.value
        #expect(pages.loaded == [1, 2])
        #expect(observer.phase.value == InfiniteData(pages: [["1"], ["2"]], pageParams: [1, 2]))
    }

    @Test("fetchNextPage appends until getNextPageParam returns nil")
    func fetchNextPage() async {
        let pages = Pages()
        let observer = pages.makeObserver(client: QueryClient())

        await observer.fetch()
        await observer.fetchNextPage()
        await observer.fetchNextPage()
        #expect(!observer.hasNextPage)

        await observer.fetchNextPage() // no-op
        #expect(observer.phase.value == InfiniteData(pages: [["1"], ["2"], ["3"]], pageParams: [1, 2, 3]))
        #expect(pages.loaded == [1, 2, 3])
    }

    @Test("concurrent fetchNextPage calls load the page once")
    func concurrentFetchNextPage() async {
        let pages = Pages()
        pages.delay[2] = .milliseconds(20)
        let observer = pages.makeObserver(client: QueryClient())
        await observer.fetch()

        async let first: Void = observer.fetchNextPage()
        async let second: Void = observer.fetchNextPage()
        _ = await (first, second)

        #expect(pages.loaded == [1, 2])
        #expect(observer.phase.value?.pageParams == [1, 2])
    }

    @Test("refresh reloads every page in order, from the first page's param")
    func refreshReloadsAllPages() async {
        let pages = Pages()
        let observer = pages.makeObserver(client: QueryClient(), initialPageParam: 2) // deep-link
        await observer.fetch()
        await observer.fetchNextPage()
        pages.loaded = []

        await observer.refresh()

        #expect(pages.loaded == [2, 3])
        #expect(observer.phase.value?.pageParams == [2, 3])
        #expect(!observer.hasNextPage)
    }

    @Test("a page that arrives after the list was replaced is discarded")
    func stalePageIsDiscarded() async {
        let pages = Pages()
        pages.delay[2] = .milliseconds(20)
        let client = QueryClient()
        let observer = pages.makeObserver(client: client)
        await observer.fetch()

        let next = Task { await observer.fetchNextPage() }
        try? await Task.sleep(for: .milliseconds(5))
        observer.phase = .success(InfiniteData(pages: [["x"]], pageParams: [7]))
        await next.value

        #expect(observer.phase.value == InfiniteData(pages: [["x"]], pageParams: [7]))
    }

    @Test("re-configuring does not invalidate views reading hasNextPage")
    func reconfigureDoesNotInvalidate() async {
        let pages = Pages()
        let client = QueryClient()
        let observer = pages.makeObserver(client: client)
        await observer.fetch()

        // SwiftUI calls configure from update() on every body evaluation.
        nonisolated(unsafe) var invalidated = false
        withObservationTracking {
            _ = observer.hasNextPage
        } onChange: {
            invalidated = true
        }
        observer.configure(
            client: client,
            key: TestKey.posts,
            staleTime: 60,
            initialPageParam: 1,
            getNextPageParam: { _, _, last in last < 3 ? last + 1 : nil },
            pageLoader: { page in ["\(page)"] }
        )

        #expect(!invalidated)
    }

    @Test("a failed fetchNextPage keeps the loaded pages and reports the error")
    func fetchNextPageFailure() async {
        let pages = Pages()
        pages.failing = [2]
        let observer = pages.makeObserver(client: QueryClient())
        await observer.fetch()

        await observer.fetchNextPage()

        #expect(observer.phase.value?.pageParams == [1])
        #expect(observer.error != nil)
        #expect(!observer.isFetchingNextPage)
    }
}
