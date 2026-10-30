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
