// Compile-only check of what views can do through `@Environment(\.queryClient)`.
import SwiftUI
import QueryKit

private struct SignOutButton: View {
    @Environment(\.queryClient) private var client

    var body: some View {
        Button("Sign out") {
            Task { await client.invalidateAll() }
        }
    }
}

private enum PostsKey: QueryKey { case list }

private struct CacheLifetimeExamples: View {
    let queryClient = QueryClient(defaultStaleTime: 30, defaultGCTime: 600)
    let testClient = QueryClient(seed: [PostsKey.list: [1, 2]], overrideStaleTime: .infinity)

    @RemoteQuery(PostsKey.list, staleTime: 120, gcTime: 1800, loader: { [1, 2] })
    private var posts

    @RemoteInfiniteQuery(
        PostsKey.list,
        gcTime: .infinity,
        initialPageParam: 1,
        getNextPageParam: { _, _, _ in nil },
        loader: { page in [page] }
    ) private var feed

    var body: some View { Text("\(posts?.count ?? 0)") }
}
