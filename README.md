# QueryKit

A lightweight Swift library for data fetching and caching in SwiftUI, inspired by [TanStack Query](https://tanstack.com/query). Provides `@Query` and `@Mutation` property wrappers with built-in caching, deduplication, and optimistic updates.

> **Early development.** The API is subject to change.

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.2+

## Installation

Add QueryKit to your project via Swift Package Manager:

```swift
.package(url: "https://github.com/adrianrl/QueryKit", from: "0.1.0")
```

## Usage

### Setup

Inject a `QueryClient` instance into your SwiftUI environment:

```swift
@main
struct MyApp: App {
    private let queryClient = QueryClient()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.queryClient, queryClient)
        }
    }
}
```

### Fetching data

Define a `QueryKey` to identify your query in the cache:

```swift
enum PostsKey: QueryKey {
    case list
    case detail(Int)
}
```

Use `@Query` in your view to fetch and cache data automatically:

```swift
struct PostsView: View {
    @Query(PostsKey.list, loader: { try await API.shared.fetchPosts() }) private var posts

    var body: some View {
        switch $posts.phase {
        case .loading:
            ProgressView()
        case .success(let posts):
            List(posts) { PostRow($0) }
        case .failure(let error):
            Text(error.localizedDescription)
        case .idle:
            EmptyView()
        }
    }
}
```

### Mutations

Use `@Mutation` to perform write operations:

```swift
struct PostDetailView: View {
    @Mutation private var deletePost

    let post: Post

    var body: some View {
        Button("Delete") {
            Task {
                // applies changes and refetches automatically
                try await deletePost.mutate(invalidate: [PostsKey.list]) {
                    try await api.deletePost(id: post.id)
                }
            }
        }
        .disabled(deletePost.isLoading)
    }
}
```

### Optimistic updates

Apply changes immediately and roll back automatically on failure:

```swift
try await client.mutate(PostsKey.list, operation: {
    try await api.deletePost(id: post.id)
}, update: { (posts: inout [Post], _) in
    posts.removeAll { $0.id == post.id }
})
```

## License

MIT
