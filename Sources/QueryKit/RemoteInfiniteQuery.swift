import SwiftUI

@MainActor
@propertyWrapper
public struct RemoteInfiniteQuery<Page: Sendable, PageParam: Sendable & Equatable>: @preconcurrency DynamicProperty {
    public typealias Observer = InfiniteQueryObserver<Page, PageParam>

    @Environment(\.queryClient) private var client
    @State private var observer = Observer()

    private let key: any QueryKey
    private let staleTime: TimeInterval
    private let gcTime: TimeInterval?
    private let initialPageParam: PageParam
    private let getNextPageParam: Observer.NextPageParam
    private let loader: Observer.PageLoader

    public var wrappedValue: InfiniteData<Page, PageParam>? {
        observer.phase.value
    }

    public var projectedValue: Observer {
        observer
    }

    public init(
        _ key: any QueryKey,
        staleTime: TimeInterval = 60,
        gcTime: TimeInterval? = nil,
        initialPageParam: PageParam,
        getNextPageParam: @escaping Observer.NextPageParam,
        loader: @escaping Observer.PageLoader
    ) {
        self.key = key
        self.staleTime = staleTime
        self.gcTime = gcTime
        self.initialPageParam = initialPageParam
        self.getNextPageParam = getNextPageParam
        self.loader = loader
    }

    public mutating func update() {
        observer.configure(
            client: client,
            key: key,
            staleTime: staleTime,
            gcTime: gcTime,
            initialPageParam: initialPageParam,
            getNextPageParam: getNextPageParam,
            pageLoader: loader
        )
    }
}
