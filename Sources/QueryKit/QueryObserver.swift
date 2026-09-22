import Foundation

@MainActor
@Observable
public final class QueryObserver<Value: Sendable> {
    public var phase: QueryPhase<Value> = .idle

    /// `true` while a fetch is in flight, including revalidation of a value that
    /// is already present in ``phase``.
    ///
    /// Use this to drive a secondary indicator — a refresh spinner in the
    /// toolbar, a dimmed list — instead of switching on ``QueryPhase/loading``,
    /// which only occurs when there is no value to show yet.
    public private(set) var isFetching = false

    /// The error from the most recent failed fetch, cleared on the next success.
    ///
    /// A fetch that fails while ``phase`` already holds a value leaves that
    /// value in place and reports the error here, so a failed revalidation
    /// doesn't remove data that is already on screen. When the failure happens
    /// with no value to fall back on, ``phase`` becomes
    /// ``QueryPhase/failure(_:)`` and carries the same error.
    public private(set) var error: Error?

    private var client: (any QueryClientProtocol)?
    private var key: (any QueryKey)?
    private var staleTime: TimeInterval?
    private var loader: (@Sendable () async throws -> Value)?

    /// Number of fetches in flight, so overlapping fetches don't clear
    /// ``isFetching`` while one of them is still running.
    private var inFlightCount = 0

    public init() {}

    init(
        client: any QueryClientProtocol,
        key: any QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        self.client = client
        self.key = key
        self.staleTime = staleTime
        self.loader = loader
    }

    func configure(
        client: any QueryClientProtocol,
        key: any QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        let keyChanged: Bool

        if let currentKey = self.key {
            keyChanged = AnyHashable(currentKey) != AnyHashable(key)
        } else {
            keyChanged = true
        }

        self.client = client
        self.staleTime = staleTime
        self.loader = loader

        if keyChanged {
            // unsubscribe old
            if let oldKey = self.key {
                Task {
                    await client.unsubscribe(key: oldKey, observer: self)
                }
            }

            // subscribe new
            Task {
                await client.subscribe(key: key, observer: self)
            }

            self.key = key

            // reset state
            phase = .idle
            error = nil
        }
    }

    public func fetch() async {
        guard let client, let key, let staleTime, let loader else { return }

        await performFetch {
            try await client.fetch(
                key: key,
                staleTime: staleTime,
                loader: loader
            )
        }
    }

    public func fetch(loader: @Sendable @escaping () async throws -> Value) async {
        guard let client, let key else { return }

        await performFetch {
            try await client.fetch(
                key: key,
                loader: loader
            )
        }
    }

    public func refresh() async {
        guard let client, let key else { return }

        await client.invalidate(key)
        await fetch()
    }

    /// Runs a fetch, keeping any value already in ``phase`` visible for the
    /// duration and on failure.
    ///
    /// ``phase`` only moves to ``QueryPhase/loading`` when there is nothing to
    /// show; once a value exists, an in-flight fetch is reported through
    /// ``isFetching`` and a failure through ``error``.
    private func performFetch(_ operation: () async throws -> Value) async {
        if phase.value == nil {
            phase = .loading
        }

        inFlightCount += 1
        isFetching = true

        defer {
            inFlightCount -= 1
            isFetching = inFlightCount > 0
        }

        do {
            let value = try await operation()
            phase = .success(value)
            error = nil
        } catch {
            self.error = error

            // A concurrent fetch or a cache notification may have delivered a
            // value while this one was in flight — keep whatever is on screen.
            if phase.value == nil {
                phase = .failure(error)
            }
        }
    }
}

@MainActor
protocol AnyQueryObserver: AnyObject & Sendable {
    func receive(value: any Sendable) async
    func didInvalidate() async
}

extension QueryObserver: AnyQueryObserver {
    func receive(value: Sendable) async {
        guard let typed = value as? Value else { return }
        phase = .success(typed)
        error = nil
    }

    func didInvalidate() async {
        await fetch()
    }
}
