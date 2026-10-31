// Compile-only check that the README's Mutations and Optimistic updates examples build.
import SwiftUI
import QueryKit

private enum PostsKey: QueryKey { case list, detail(Int) }
private struct Post: Sendable, Equatable { var id: Int }
private struct API: Sendable {
    func deletePost(id: Int) async throws {}
    func createPost(_ post: Post) async throws -> Post { post }
}
private extension EnvironmentValues { @Entry var api = API() }

private struct PostDetailView: View {
    @Environment(\.api) private var api
    @Mutation private var deletePost
    @Mutation<Post> private var createPost
    @State private var path: [Int] = []

    let post: Post
    let draft: Post

    var body: some View {
        Button("Delete") {
            Task {
                // refetches the list once the delete succeeds
                await deletePost.mutate(invalidate: [PostsKey.list]) {
                    try await api.deletePost(id: post.id)
                }
            }
        }
        .disabled(deletePost.isLoading)
        .alert("Couldn't delete the post", isPresented: .constant(deletePost.error != nil)) {
            Button("OK") { deletePost.reset() }
        }
    }

    func examples() async {
        let saved = await createPost.mutate { try await api.createPost(draft) }
        if let saved {
            path.append(saved.id)
        }

        await deletePost.mutate(
            updating: .init(PostsKey.list) { (posts: inout [Post]) in
                posts.removeAll { $0.id == post.id }
            }
        ) {
            try await api.deletePost(id: post.id)
        }

        await createPost.mutate(
            updating: .init(PostsKey.list,
                            optimistic: { (posts: inout [Post]) in posts.append(draft) },
                            onSuccess: { posts, saved in posts[posts.count - 1] = saved }),
                      .init(PostsKey.detail(draft.id)) { (post: inout Post) in post = draft }
        ) {
            try await api.createPost(draft)
        }
    }
}
