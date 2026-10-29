// Compile-only check: SwiftData's `@Query` and QueryKit's `@RemoteQuery` coexist in one view.
// With QueryKit's wrapper named `Query`, `@Query(key, loader:)` resolved to SwiftData's macro.
import SwiftData
import SwiftUI
import QueryKit

@Model private final class Draft {
    var date = Date()
    init() {}
}

private enum DraftsKey: QueryKey { case remote }

private struct DraftsView: View {
    @Query(sort: \Draft.date) private var drafts: [Draft]
    @RemoteQuery(DraftsKey.remote, loader: { [1, 2] }) private var remote

    var body: some View {
        Text("\(drafts.count) local, \(remote?.count ?? 0) remote")
    }
}
