import Foundation

/// Defines the interface for a query client, enabling both production and mock implementations.
///
/// Use ``QueryClient`` in production and ``MockQueryClient`` in SwiftUI previews and tests.
public protocol QueryClientProtocol: AnyObject & Sendable {
    func fetch<Value: Sendable>(
        key: some QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value

    func fetch<Value: Sendable>(
        key: some QueryKey,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value

    func invalidate(_ key: some QueryKey) async

    func subscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) async

    func unsubscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) async

    @discardableResult
    func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: @Sendable (inout QueryValue) -> Void,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result

    @discardableResult
    func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: (@Sendable (inout QueryValue) -> Void)?,
        onSuccess: @Sendable (inout QueryValue, Result) -> Void,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result

    func mutate<K: QueryKey, Result: Sendable>(
        _ key: K,
        operation: @Sendable () async throws -> Result
    ) async throws
}
