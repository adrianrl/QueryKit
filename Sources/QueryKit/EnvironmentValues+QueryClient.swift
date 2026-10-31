import SwiftUI

extension EnvironmentValues {
    // `@Entry` re-evaluates its default on every read that finds no injected value, so it must
    // return the same instance: a fresh client per read would share no cache between views.
    @Entry public var queryClient: any QueryClientProtocol = QueryClient.shared
}
