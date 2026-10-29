import Foundation

/// A ``QueryObserver`` whose value is a list of pages that grows with ``fetchNextPage()``.
///
/// The whole ``InfiniteData`` is cached under a single key, so `fetch()`, `refresh()`
/// and invalidation behave as for any other query: a refetch reloads every page
/// already on screen, in order, starting from the first page's parameter.
@MainActor
@Observable
public final class InfiniteQueryObserver<Page: Sendable, PageParam: Sendable & Equatable>: QueryObserver<InfiniteData<Page, PageParam>> {
    public typealias PageLoader = @Sendable (PageParam) async throws -> Page

    /// Returns the parameter for the page after `lastPage`, or `nil` when there are no more pages.
    public typealias NextPageParam = @MainActor (_ lastPage: Page, _ pages: [Page], _ lastPageParam: PageParam) -> PageParam?

    /// `true` while ``fetchNextPage()`` is in flight. ``isFetching`` does not cover it:
    /// loading one more page should not be mistaken for a refetch of the list.
    public private(set) var isFetchingNextPage = false

    // Configuration, rewritten by every SwiftUI update(): observing it would re-render forever.
    @ObservationIgnored private var initialPageParam: PageParam?
    @ObservationIgnored private var getNextPageParam: NextPageParam?
    @ObservationIgnored private var pageLoader: PageLoader?

    public var hasNextPage: Bool {
        nextPageParam != nil
    }

    /// Derived from ``phase`` on every read so it stays in sync when another
    /// observer of the same key appends a page.
    private var nextPageParam: PageParam? {
        guard let data = phase.value,
              let lastPage = data.pages.last,
              let lastParam = data.pageParams.last,
              let getNextPageParam else { return nil }

        return getNextPageParam(lastPage, data.pages, lastParam)
    }

    func configure(
        client: any QueryClientProtocol,
        key: any QueryKey,
        staleTime: TimeInterval,
        initialPageParam: PageParam,
        getNextPageParam: @escaping NextPageParam,
        pageLoader: @escaping PageLoader
    ) {
        self.initialPageParam = initialPageParam
        self.getNextPageParam = getNextPageParam
        self.pageLoader = pageLoader

        super.configure(client: client, key: key, staleTime: staleTime) { @MainActor [weak self] in
            guard let self else { throw CancellationError() }

            return try await loadPages()
        }
    }

    /// Unavailable: a single-value loader would replace the page loader and break pagination.
    /// Reached only through a `QueryObserver` reference, where it falls back to ``fetch()``.
    @available(*, unavailable, message: "Use fetch(); the page loader is set by @RemoteInfiniteQuery")
    override public func fetch(loader: @Sendable @escaping () async throws -> InfiniteData<Page, PageParam>) async {
        await fetch()
    }

    /// Loads the page after the last one and appends it to ``phase``.
    ///
    /// Does nothing when there is no next page or one is already loading. A failure
    /// keeps the loaded pages and is reported through ``error``.
    public func fetchNextPage() async {
        guard !isFetchingNextPage,
              let client, let key, let pageLoader,
              let param = nextPageParam else { return }

        isFetchingNextPage = true
        defer { isFetchingNextPage = false }

        do {
            let page = try await pageLoader(param)

            // Re-read after the await: a refetch may have replaced the list while
            // this page loaded. Only append to a list that still ends where it begins.
            guard var data = phase.value, nextPageParam == param else { return }

            data.pages.append(page)
            data.pageParams.append(param)
            phase = .success(data)
            await client.setQueryData(key, value: data)
        } catch {
            self.error = error
        }
    }

    /// Reloads as many pages as are currently shown (at least one), chaining each
    /// parameter from the previous page. Used as the query loader, so it drives
    /// the first fetch, `refresh()` and invalidation alike.
    private func loadPages() async throws -> InfiniteData<Page, PageParam> {
        guard let pageLoader, let getNextPageParam, let initialPageParam else { throw CancellationError() }

        let count = max(phase.value?.pages.count ?? 0, 1)
        var data = InfiniteData<Page, PageParam>(pages: [], pageParams: [])
        var param: PageParam? = phase.value?.pageParams.first ?? initialPageParam

        while let current = param, data.pages.count < count {
            let page = try await pageLoader(current)
            data.pages.append(page)
            data.pageParams.append(current)
            param = getNextPageParam(page, data.pages, current)
        }

        return data
    }
}
