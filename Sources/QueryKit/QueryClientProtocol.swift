import Foundation

/// The interface ``RemoteQuery``, ``RemoteInfiniteQuery`` and ``Mutation`` use to reach the cache.
///
/// Use ``QueryClient`` in production and ``MockQueryClient`` in SwiftUI previews and tests.
///
/// Only ``QueryClient`` and ``MockQueryClient`` conform to this protocol. Don't conform
/// your own types: requirements may be added in minor releases.
public protocol QueryClientProtocol: AnyObject & Sendable {
    func fetch<Value: Sendable>(
        key: some QueryKey,
        staleTime: TimeInterval,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value

    func invalidate(_ key: some QueryKey) async

    func invalidateAll() async

    func setQueryData<K: QueryKey, Value: Sendable>(_ key: K, value: Value) async

    @discardableResult
    func mutate<Result: Sendable>(
        updating updates: [CacheUpdate<Result>],
        invalidate keys: [any QueryKey],
        operation: @Sendable () async throws -> Result
    ) async throws -> Result
}
