import Foundation

@MainActor
@Observable
public final class MutationObserver<Value: Sendable> {
    private(set) public var phase: MutationPhase<Value> = .idle
    private var client: QueryClient?

    public var isLoading: Bool {
        if case .loading = phase { return true }
        return false
    }

    public var error: Error? {
        if case .failure(let error) = phase { return error }
        return nil
    }

    func configure(client: QueryClient) {
        self.client = client
    }

    public func mutate(
        invalidate keys: [any QueryKey] = [],
        operation: @Sendable () async throws -> Value
    ) async {
        phase = .loading

        do {
            let result = try await operation()

            for key in keys {
                await client?.invalidate(key)
            }

            phase = .success(result)
        } catch {
            phase = .failure(error)
        }
    }
}
