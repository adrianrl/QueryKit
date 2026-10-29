/// A change to the cached value of one key, applied as part of a mutation.
///
/// `optimistic` runs before the operation, so observers of `key` see the change
/// immediately. If the operation throws, the previous value is restored. If it
/// succeeds, `onSuccess` runs on the current cached value with the operation's
/// result — for example, to replace a placeholder with the saved item.
///
/// Nothing is applied when `key` has no cached value. A cached value of a type
/// other than `QueryValue` is a programming error: it traps in debug builds and
/// is skipped in release. For an ``InfiniteQuery`` key, `QueryValue` is
/// `InfiniteData<Page, PageParam>`, not the page type.
///
/// ```swift
/// await deletePost.mutate(
///     updating: .init(PostsKey.list) { (posts: inout [Post]) in
///         posts.removeAll { $0.id == post.id }
///     }
/// ) {
///     try await api.deletePost(id: post.id)
/// }
/// ```
public struct CacheUpdate<Result: Sendable>: Sendable {
    let key: any QueryKey
    let optimistic: @Sendable (any Sendable) -> (any Sendable)?
    let onSuccess: (@Sendable (any Sendable, Result) -> (any Sendable)?)?

    public init<QueryValue: Sendable>(
        _ key: some QueryKey,
        optimistic: @escaping @Sendable (inout QueryValue) -> Void,
        onSuccess: (@Sendable (inout QueryValue, Result) -> Void)? = nil
    ) {
        self.key = key
        self.optimistic = { cached in
            guard var value = cached as? QueryValue else {
                assertTypeMismatch(key, expected: QueryValue.self, cached: cached)
                return nil
            }
            optimistic(&value)
            return value
        }

        if let onSuccess {
            self.onSuccess = { cached, result in
                guard var value = cached as? QueryValue else {
                    assertTypeMismatch(key, expected: QueryValue.self, cached: cached)
                    return nil
                }
                onSuccess(&value, result)
                return value
            }
        } else {
            self.onSuccess = nil
        }
    }
}

private func assertTypeMismatch(_ key: any QueryKey, expected: Any.Type, cached: any Sendable) {
    assertionFailure("CacheUpdate for \(key) expects \(expected), but the cache holds \(type(of: cached))")
}
