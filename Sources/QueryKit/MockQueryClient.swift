import Foundation

/// A mock implementation of ``QueryClientProtocol`` for use in SwiftUI previews and tests.
///
/// Configure each key with a ``QueryPhase`` to control what the observer receives:
/// - `.success(value)` — resolves immediately with the given value
/// - `.failure(error)` — throws the given error immediately
/// - `.loading` — never resolves, leaving the observer in the loading state
/// - `.idle` — never resolves, leaving the observer in the idle state
///
/// A mutation's `updating:` changes are applied to `.success` values and shown in every view
/// observing that key, so a preview reflects an optimistic delete or edit. `invalidate:` and
/// ``invalidateAll()`` are ignored: refetching would bring back the stubbed value.
///
/// Use the ``View/queryPreview(_:phase:)`` modifier for a convenient SwiftUI integration.
public final class MockQueryClient: QueryClientProtocol, @unchecked Sendable {
    private enum AnyPhase {
        case loading
        case idle
        case success(any Sendable)
        case failure(Error)
    }

    private var phases: [AnyHashable: AnyPhase] = [:]

    /// Holds `.success` values once read, so mutations can change them and observers see it.
    let cache = QueryClient(defaultGCTime: .infinity)

    public init() {}

    /// Configures the phase to return for a given key.
    ///
    /// - Parameters:
    ///   - key: The ``QueryKey`` to configure.
    ///   - phase: The ``QueryPhase`` the observer will receive when fetching this key.
    /// - Returns: `self`, to allow chaining.
    @discardableResult
    public func stub<K: QueryKey, V: Sendable>(_ key: K, phase: QueryPhase<V>) -> Self {
        switch phase {
        case .idle:
            phases[AnyHashable(key)] = .idle
        case .loading:
            phases[AnyHashable(key)] = .loading
        case .success(let value):
            phases[AnyHashable(key)] = .success(value)
        case .failure(let error):
            phases[AnyHashable(key)] = .failure(error)
        }
        return self
    }

    public func fetch<Value: Sendable>(
        key: some QueryKey,
        staleTime: TimeInterval?,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        let stubbed: Value = try await resolve(key: AnyHashable(key))
        return try await cache.fetch(key: key, staleTime: .infinity) { stubbed }
    }

    public func invalidate(_ key: some QueryKey) async {}

    public func setQueryData<K: QueryKey, Value: Sendable>(_ key: K, value: Value) async {
        await cache.setQueryData(key, value: value)
    }

    public func invalidateAll() async {}

    @discardableResult
    public func mutate<Result: Sendable>(
        updating updates: [CacheUpdate<Result>],
        invalidate keys: [any QueryKey],
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try await cache.mutate(updating: updates, operation: operation)
    }

    // MARK: - Private

    private func resolve<Value: Sendable>(key: AnyHashable) async throws -> Value {
        switch phases[key] {
        case .success(let value):
            guard let typed = value as? Value else {
                throw MockQueryClientError.typeMismatch
            }
            return typed
        case .failure(let error):
            throw error
        case .loading, .idle, .none:
            // Suspend forever; cancelled when the owning Task is cancelled (e.g. view disappears)
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { _ in }
            } onCancel: {}
        }
    }
}

public enum MockQueryClientError: Error {
    case typeMismatch
}
