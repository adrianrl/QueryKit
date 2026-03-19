import Foundation

@MainActor
@Observable
public final class QueryObserver<Value: Sendable> {
    public var phase: QueryPhase<Value> = .idle

    private var client: QueryClient?
    private var key: (any QueryKey)?
    private var staleTime: TimeInterval?
    private var loader: (@Sendable () async throws -> Value)?

    private var isConfigured = false

    public init() {}

    init(
        client: QueryClient,
        key: any QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        self.client = client
        self.key = key
        self.staleTime = staleTime
        self.loader = loader
        self.isConfigured = true
    }

    func configureIfNeeded(
        client: QueryClient,
        key: any QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        guard !isConfigured else { return }

        self.client = client
        self.key = key
        self.staleTime = staleTime
        self.loader = loader
        self.isConfigured = true
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

    public func refresh() async {
        guard let client, let key else { return }

        await client.invalidate(key)
        await fetch()
    }
}
