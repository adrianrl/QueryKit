import SwiftUI

extension EnvironmentValues {
    @Entry public var queryClient: any QueryClientProtocol = QueryClient()
}
