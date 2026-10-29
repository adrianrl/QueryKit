import Foundation

@MainActor
@Observable
public final class MutationObserver<Value: Sendable> {
    private(set) public var phase: MutationPhase<Value> = .idle
    private var client: (any QueryClientProtocol)?

    public var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    public var error: Error? {
        if case .failure(let error) = phase { return error }
        return nil
    }

    func configure(client: any QueryClientProtocol) {
        self.client = client
    }

    /// Runs `operation`, applying `updates` to the cache around it and invalidating `keys` on success.
    ///
    /// Doesn't throw: a failure is reported through ``phase`` and ``error``, and any
    /// optimistic change from `updates` is rolled back. Returns the operation's result,
    /// or `nil` if it failed.
    @discardableResult
    public func mutate(
        updating updates: CacheUpdate<Value>...,
        invalidate keys: [any QueryKey] = [],
        operation: @Sendable () async throws -> Value
    ) async -> Value? {
        guard let client else { return nil }

        phase = .loading

        do {
            let result = try await client.mutate(updating: updates, invalidate: keys, operation: operation)
            phase = .success(result)
            return result
        } catch {
            phase = .failure(error)
            return nil
        }
    }
}
