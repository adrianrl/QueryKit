import Foundation

/// A mock implementation of ``QueryClientProtocol`` for use in SwiftUI previews and tests.
///
/// Configure each key with a ``QueryPhase`` to control what the observer receives:
/// - `.success(value)` — resolves immediately with the given value
/// - `.failure(error)` — throws the given error immediately
/// - `.loading` — never resolves, leaving the observer in the loading state
/// - `.idle` — never resolves, leaving the observer in the idle state
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
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await resolve(key: AnyHashable(key))
    }

    public func fetch<Value: Sendable>(
        key: some QueryKey,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await resolve(key: AnyHashable(key))
    }

    public func invalidate(_ key: some QueryKey) async {}

    public func subscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) async {}

    public func unsubscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) async {}

    @discardableResult
    public func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: @Sendable (inout QueryValue) -> Void,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try await operation()
    }

    @discardableResult
    public func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: (@Sendable (inout QueryValue) -> Void)?,
        onSuccess: @Sendable (inout QueryValue, Result) -> Void,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try await operation()
    }

    public func mutate<K: QueryKey, Result: Sendable>(
        _ key: K,
        operation: @Sendable () async throws -> Result
    ) async throws {
        _ = try await operation()
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
