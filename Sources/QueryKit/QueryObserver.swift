import Foundation

@MainActor
@Observable
public final class QueryObserver<Value: Sendable> {
    public var phase: QueryPhase<Value> = .idle

    private var client: (any QueryClientProtocol)?
    private var key: (any QueryKey)?
    private var staleTime: TimeInterval?
    private var loader: (@Sendable () async throws -> Value)?

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
            self.loader = loader
            phase = .idle
        } else if let loader {
            self.loader = loader
        }
    }

    public func fetch() async {
        guard let client, let key, let staleTime, let loader else { return }

        phase = .loading

        do {
            let value = try await client.fetch(
                key: key,
                staleTime: staleTime,
                loader: loader
            )
            phase = .success(value)
        } catch {
            phase = .failure(error)
        }
    }

    /// Fetches with `loader` and stores it as the query function for later ``fetch()``, ``refresh()``, and invalidation.
    public func fetch(loader: @Sendable @escaping () async throws -> Value) async {
        guard let client, let key else { return }

        self.loader = loader
        phase = .loading

        do {
            let value = try await client.fetch(
                key: key,
                loader: loader
            )
            phase = .success(value)
        } catch {
            phase = .failure(error)
        }
    }

    public func refresh() async {
        guard let client, let key else { return }

        await client.invalidate(key)
        await fetch()
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
    }

    func didInvalidate() async {
        await fetch()
    }
}
