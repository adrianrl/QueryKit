# QueryKit

A lightweight Swift library for data fetching and caching in SwiftUI, inspired by [TanStack Query](https://tanstack.com/query). Provides `@RemoteQuery`, `@RemoteInfiniteQuery` and `@Mutation` property wrappers with built-in caching, deduplication, and optimistic updates.

> **Early development.** The API is subject to change.

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.2+

## Installation

Add QueryKit to your project via Swift Package Manager:

```swift
.package(url: "https://github.com/adrianrl/QueryKit", .upToNextMinor(from: "0.2.0"))
```

While QueryKit is below 1.0, breaking changes bump the minor version, so pin it with `.upToNextMinor(from:)`.

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
    case search(String)
}
```

Use `@RemoteQuery` in your view to fetch and cache data automatically:

```swift
struct PostsView: View {
    @RemoteQuery(PostsKey.list, loader: { try await API.shared.fetchPosts() }) private var posts

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

`QueryPhase` also exposes `value`, `isLoading` and `error` if you'd rather read one
of them directly than switch over every case:

```swift
if $posts.phase.isLoading {
    ProgressView()
}
```

When the loader depends on a SwiftUI environment value that is not available in `init`, create the query with only a key. `fetch(loader:)` stores that function and reuses it for `refresh()` and `invalidate`. Like `fetch()`, it honours the query's `staleTime` (a fresh cached value is returned without calling the loader); use `refresh()` to force a new request:

```swift
struct PostDetailView: View {
    let postId: Int
    @Environment(\.api) private var api
    @RemoteQuery(PostsKey.detail(postId)) private var post

    var body: some View {
        content
            .task {
                await $post.fetch {
                    try await api.fetchPost(id: postId)
                }
            }
    }
}
```

Give each distinct request its own key. For search, recreate the query when the term changes instead of reusing the list key:

```swift
struct PostSearchView: View {
    @State private var query = ""

    var body: some View {
        PostSearchResultsView(query: query)
            .id(query)
            .searchable(text: $query)
    }
}

struct PostSearchResultsView: View {
    let query: String
    @RemoteQuery(PostsKey.search(query), loader: {
        try await API.shared.searchPosts(query: query)
    }) private var posts

    var body: some View {
        List { ... }
            .task { await $posts.fetch() }
    }
}
```

### Revalidation

`phase` only reports `.loading` when there is no value to show. Once a query has
succeeded, or a view opens on a stale cached value (see
[Cache lifetime](#cache-lifetime)), a refetch keeps that value in `phase` and reports
itself through `isFetching`, so the list doesn't disappear on every refresh:

```swift
struct PostsView: View {
    @RemoteQuery(PostsKey.list, loader: { try await API.shared.fetchPosts() }) private var posts

    var body: some View {
        List(posts ?? []) { PostRow($0) }
            .overlay(alignment: .top) {
                if $posts.isFetching {
                    ProgressView()
                }
            }
            .refreshable {
                await $posts.refresh()
            }
    }
}
```

The same applies to failures. A refetch that fails leaves the previous value in
`phase` and reports the error through `error`, so you can surface it without
tearing down the list:

```swift
VStack {
    if let error = $posts.error {
        RefreshFailedBanner(error: error)
    }

    List(posts ?? []) { PostRow($0) }
}
```

When the failure happens with no value to fall back on — a failed first load —
`phase` becomes `.failure(error)` and carries the same error. So `switch $posts.phase`
handles the empty states, and `isFetching` / `error` handle everything that happens
on top of already-loaded data.

### Cache lifetime

Two timers decide what happens to a cached value:

- `staleTime` (60 seconds by default) counts from when the value was loaded. While it
  is younger than that, `fetch()` returns it without calling the loader.
- `gcTime` (5 minutes by default) counts from when the last view observing the key
  went away. When it runs out, the value is removed. A view that observes the key again
  before then cancels the removal.

A view that opens on a key whose value is stale but not yet removed shows that value
straight away and reloads it, reporting the reload through `isFetching`, as in
[Revalidation](#revalidation). Once the value is removed, the view starts from
`.loading`.

```swift
// for every query
let queryClient = QueryClient(defaultGCTime: 600)

// for one query: keep the feed for 30 minutes
@RemoteQuery(PostsKey.list, gcTime: 1800, loader: { try await API.shared.fetchPosts() })
private var posts
```

Keep `gcTime` longer than `staleTime`. A shorter `gcTime` removes values that are still
fresh once no view shows them, so returning to the screen reloads data that didn't need
it.

When several views observe a key with different values, the longest `gcTime` wins. Pass
`.infinity` to never remove a value. Values written with `setQueryData` or the `seed:`
initializer count from when they are written, as if no view had observed them.

### Pagination

`@RemoteInfiniteQuery` loads a list page by page. Give it the first page's parameter, a
loader for one page, and a function that derives the next parameter from the last
page (return `nil` when there are no more). The value is an `InfiniteData` with the
`pages` loaded so far and the `pageParams` they were fetched with:

```swift
struct PostsView: View {
    @RemoteInfiniteQuery(
        PostsKey.list,
        initialPageParam: 1,
        getNextPageParam: { lastPage, _, page in lastPage.isEmpty ? nil : page + 1 },
        loader: { page in try await API.shared.fetchPosts(page: page) }
    ) private var posts

    var body: some View {
        List {
            ForEach(posts?.pages.flatMap(\.self) ?? []) { PostRow($0) }

            if $posts.hasNextPage {
                ProgressView()
                    // id: re-run after each page, in case the spinner never left the screen
                    .task(id: posts?.pages.count) { await $posts.fetchNextPage() }
            }
        }
        .task { await $posts.fetch() }
        .refreshable { await $posts.refresh() }
    }
}
```

For cursor-based APIs, read the cursor off the last page:
`getNextPageParam: { lastPage, _, _ in lastPage.nextCursor }`.

The whole list is cached under one key. A refetch — `refresh()`, or an invalidation
from a mutation — reloads every page that is on screen, in order, starting from the
first page's parameter, so the scroll position survives and a list opened at page 5
from a deep link stays at page 5. `fetchNextPage()` ignores calls while a page is
already loading, and reports a failure through `error` without dropping the pages
you have. `isFetchingNextPage` is separate from `isFetching`, so you can show a
footer spinner without the list looking like it is refreshing.

### Mutations

Use `@Mutation` to perform write operations. Its type parameter is the result of the
operation, so a mutation that returns nothing is `@Mutation<Void>`:

```swift
struct PostDetailView: View {
    @Environment(\.api) private var api
    @Mutation<Void> private var deletePost

    let post: Post

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
    }
}
```

`mutate` doesn't throw: a failure is reported through `deletePost.error` and
`deletePost.phase`. It returns the operation's result, or `nil` if it failed:

```swift
let saved = await createPost.mutate { try await api.createPost(draft) }
if let saved {
    path.append(saved.id)
}
```

### Optimistic updates

Pass a `CacheUpdate` to change cached data before the operation runs. Observers of that
key update immediately, and the previous value is restored if the operation fails:

```swift
await deletePost.mutate(
    updating: .init(PostsKey.list) { (posts: inout [Post]) in
        posts.removeAll { $0.id == post.id }
    }
) {
    try await api.deletePost(id: post.id)
}
```

Use `onSuccess` to fold the server's response into the cache, and pass several updates
to change more than one key:

```swift
await createPost.mutate(
    updating: .init(PostsKey.list,
                    optimistic: { (posts: inout [Post]) in posts.append(draft) },
                    onSuccess: { posts, saved in posts[posts.count - 1] = saved }),
              .init(PostsKey.detail(draft.id)) { (post: inout Post) in post = draft }
) {
    try await api.createPost(draft)
}
```

An update is skipped when its key has nothing cached. The closure's type must match
the cached value — a mismatch traps in debug builds. For a `@RemoteInfiniteQuery` key that
type is `InfiniteData<Page, PageParam>`, not the page type. Outside SwiftUI,
`QueryClient.mutate(updating:invalidate:operation:)` does the same and throws on failure.

To write to the cache directly — for example, with data you already have from
another response — use `setQueryData`. Observers of that key update immediately:

```swift
await client.setQueryData(PostsKey.detail(post.id), value: post)
```

`invalidateAll()` empties the cache and refetches every query on screen — for example,
after signing out:

```swift
@Environment(\.queryClient) private var client

Button("Sign out") {
    Task { await client.invalidateAll() }
}
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
