/// The pages loaded so far by an ``InfiniteQueryObserver``, with the parameter each one was fetched with.
public struct InfiniteData<Page: Sendable, PageParam: Sendable>: Sendable {
    public var pages: [Page]
    public var pageParams: [PageParam]

    public init(pages: [Page], pageParams: [PageParam]) {
        self.pages = pages
        self.pageParams = pageParams
    }
}

extension InfiniteData: Equatable where Page: Equatable, PageParam: Equatable {}
