import Foundation

@MainActor
@Observable
public class QueryObserver<Value: Sendable> {
    public internal(set) var phase: QueryPhase<Value> = .idle

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
    public internal(set) var error: Error?

    var client: (any QueryClientProtocol)?
    var key: (any QueryKey)?
    private var staleTime: TimeInterval?
    private var gcTime: TimeInterval?
    private var loader: (@Sendable () async throws -> Value)?

    /// Number of fetches in flight, so overlapping fetches don't clear
    /// ``isFetching`` while one of them is still running.
    private var inFlightCount = 0

    init() {}

    // Starts the client's eviction timer for this key once no view observes it.
    isolated deinit {
        guard let client = client as? QueryClient, let key else { return }

        Task { [key] in await client.observerDidLeave(key: key) }
    }

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
        gcTime: TimeInterval? = nil,
        loader: (@Sendable () async throws -> Value)? = nil
    ) {
        let keyChanged: Bool

        if let currentKey = self.key {
            keyChanged = AnyHashable(currentKey) != AnyHashable(key)
        } else {
            keyChanged = true
        }

        self.client = client
        self.staleTime = staleTime
        self.gcTime = gcTime

        if keyChanged {
            // Only QueryClient pushes cache updates; a mock has nothing to subscribe to.
            if let client = client as? QueryClient {
                // unsubscribe old
                if let oldKey = self.key {
                    Task {
                        await client.unsubscribe(key: oldKey, observer: self)
                    }
                }

                // subscribe new
                Task {
                    await client.subscribe(key: key, observer: self, gcTime: gcTime)
                }
            }

            self.key = key
            self.loader = loader
            phase = .idle
            error = nil
        } else if let loader {
            self.loader = loader
        }
    }

    /// Loads the query, or returns the cached value while it is younger than `staleTime`.
    ///
    /// When nothing is shown yet and the cache holds an expired value for the key, that
    /// value goes to ``phase`` first and is replaced when the reload finishes, which is
    /// reported through ``isFetching``.
    public func fetch() async {
        guard let client, let key, let staleTime, let loader else { return }

        if phase.value == nil,
           let client = client as? QueryClient,
           let cached = await client.cachedValue(for: key) as? Value {
            phase = .success(cached)
        }

        await performFetch {
            try await client.fetch(
                key: key,
                staleTime: staleTime,
                loader: loader
            )
        }
    }

    /// Fetches with `loader` and stores it as the query function for later ``fetch()``, ``refresh()``, and invalidation.
    ///
    /// Honours the query's `staleTime` like ``fetch()``: a cached value younger than it is
    /// returned without calling `loader`. Use ``refresh()`` to bypass the cache.
    public func fetch(loader: @Sendable @escaping () async throws -> Value) async {
        self.loader = loader
        await fetch()
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
