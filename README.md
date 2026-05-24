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
        VStack {
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
        .task {
            await $posts.fetch()
        }
    }
}
```

Use `fetch(loader:)` to trigger a fetch with a custom loader — useful when the loader depends on local state like a search query:

```swift
struct PostSearchView: View {
    @Query(PostsKey.list, loader: { try await API.shared.fetchPosts() }) private var posts
    @State private var query = ""

    var body: some View {
        List { ... }
            .searchable(text: $query)
            .task(id: query) {
                await $posts.fetch {
                    try await API.shared.searchPosts(query: query)
                }
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

### SwiftUI Previews

Use the `.queryPreview` modifier to inject a `MockQueryClient` with pre-configured phases for each key, without modifying your views:

```swift
#Preview("Success") {
    PostsView()
        .queryPreview(PostsKey.list, phase: .success([
            Post(id: 1, title: "First Post", content: "This is the first post."),
            Post(id: 2, title: "Second Post", content: "This is the second post.")
        ]))
}

#Preview("Failure") {
    PostsView()
        .queryPreview(PostsKey.list, phase: .failure(APIError.notFound))
}
```

For `.loading` and `.idle`, use the dedicated overloads to avoid specifying the generic type explicitly:

```swift
#Preview("Loading") {
    PostsView()
        .queryPreview(PostsKey.list, loading: [Post].self)
}

#Preview("Idle") {
    PostsView()
        .queryPreview(PostsKey.list, idle: [Post].self)
}
```

To configure multiple keys at once, use the closure-based overload:

```swift
#Preview {
    PostDetailView()
        .queryPreview { mock in
            mock
                .stub(PostsKey.list, phase: .success([.mock]))
                .stub(PostsKey.detail(1), phase: .failure(APIError.notFound))
        }
}
```

## License

MIT
