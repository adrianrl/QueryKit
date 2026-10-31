import SwiftUI
import Testing

@testable import QueryKit

@Suite("Environment tests")
struct EnvironmentTests {
    @Test("Without an injected client, every read returns the same shared client")
    @MainActor
    func testDefaultClientIsStable() {
        let environment = EnvironmentValues()

        #expect(environment.queryClient === environment.queryClient)
        #expect(environment.queryClient === QueryClient.shared)
    }
}
