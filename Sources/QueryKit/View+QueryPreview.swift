import SwiftUI

extension View {
    /// Injects a ``MockQueryClient`` configured with the given phase for a single key,
    /// for use in SwiftUI previews.
    ///
    /// ```swift
    /// #Preview("Loading") {
    ///     PostsView()
    ///         .queryPreview(AppQueryKey.posts, phase: QueryPhase<[Post]>.loading)
    /// }
    ///
    /// #Preview("Error") {
    ///     PostsView()
    ///         .queryPreview(AppQueryKey.posts, phase: .failure(APIError.notFound))
    /// }
    ///
    /// #Preview("Success") {
    ///     PostsView()
    ///         .queryPreview(AppQueryKey.posts, phase: .success([.mock]))
    /// }
    /// ```
    public func queryPreview<K: QueryKey, V: Sendable>(_ key: K, phase: QueryPhase<V>) -> some View {
        let mock = MockQueryClient().stub(key, phase: phase)
        return environment(\.queryClient, mock)
    }

    /// Injects a ``MockQueryClient`` configured with a `.loading` phase for a single key,
    /// for use in SwiftUI previews.
    ///
    /// Use this overload instead of `.queryPreview(_:phase:)` with `.loading` to avoid
    /// having to specify the generic type explicitly.
    ///
    /// ```swift
    /// #Preview("Loading") {
    ///     PostsView()
    ///         .queryPreview(AppQueryKey.posts, loading: [Post].self)
    /// }
    /// ```
    public func queryPreview<K: QueryKey, V: Sendable>(_ key: K, loading type: V.Type) -> some View {
        let mock = MockQueryClient().stub(key, phase: QueryPhase<V>.loading)
        return environment(\.queryClient, mock)
    }

    /// Injects a ``MockQueryClient`` configured with an `.idle` phase for a single key,
    /// for use in SwiftUI previews.
    ///
    /// Use this overload instead of `.queryPreview(_:phase:)` with `.idle` to avoid
    /// having to specify the generic type explicitly.
    ///
    /// ```swift
    /// #Preview("Idle") {
    ///     PostsView()
    ///         .queryPreview(AppQueryKey.posts, idle: [Post].self)
    /// }
    /// ```
    public func queryPreview<K: QueryKey, V: Sendable>(_ key: K, idle type: V.Type) -> some View {
        let mock = MockQueryClient().stub(key, phase: QueryPhase<V>.idle)
        return environment(\.queryClient, mock)
    }

    /// Injects a ``MockQueryClient`` configured with phases for multiple keys,
    /// for use in SwiftUI previews.
    ///
    /// ```swift
    /// #Preview {
    ///     PostDetailView()
    ///         .queryPreview { mock in
    ///             mock
    ///                 .stub(AppQueryKey.posts, phase: .success([.mock]))
    ///                 .stub(AppQueryKey.currentUser, phase: .failure(APIError.unauthorized))
    ///         }
    /// }
    /// ```
    public func queryPreview(_ configure: (MockQueryClient) -> MockQueryClient) -> some View {
        let mock = configure(MockQueryClient())
        return environment(\.queryClient, mock)
    }
}
