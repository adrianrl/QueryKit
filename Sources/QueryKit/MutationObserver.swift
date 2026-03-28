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
    
    public func mutate(
        invalidate keys: (any QueryKey)...,
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
    
    public func mutate<QueryValue: Sendable>(
        _ key: any QueryKey,
        invalidate: Bool,
        onMutate: (@Sendable (inout QueryValue) -> Void),
        operation: @Sendable () async throws -> Value
    ) async {
        phase = .loading

        do {
            let result = try await client?.mutate(
                key,
                invalidate: invalidate,
                onMutate: onMutate,
                operation: operation
            )

            if let result {
                phase = .success(result)
            }
        } catch {
            phase = .failure(error)
        }
    }

    public func mutate<QueryValue: Sendable>(
        _ key: any QueryKey,
        invalidate keys: [any QueryKey] = [],
        onMutate: (@Sendable (inout QueryValue) -> Void)? = nil,
        onSuccess: (@Sendable (inout QueryValue, Value) -> Void),
        operation: @Sendable () async throws -> Value
    ) async {
        phase = .loading
    
        do {
            let result = try await client?.mutate(
                key,
                invalidate: !keys.isEmpty,
                onMutate: onMutate,
                onSuccess: onSuccess,
                operation: operation
            )
    
            for key in keys {
                await client?.invalidate(key)
            }
    
            if let result {
                phase = .success(result)
            }
        } catch {
            phase = .failure(error)
        }
    }
}
