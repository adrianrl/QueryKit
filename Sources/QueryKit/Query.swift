import SwiftUI

@MainActor
@propertyWrapper
public struct Query<Value: Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var client
    @State private var observer = QueryObserver<Value>()

    private let key: any QueryKey
    private let staleTime: TimeInterval
    private let loader: @Sendable () async throws -> Value

    public var wrappedValue: Value? {
        observer.phase.value
    }

    public var projectedValue: QueryObserver<Value> {
        observer
    }

    public init(
        _ key: any QueryKey,
        staleTime: TimeInterval = 60,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        self.key = key
        self.staleTime = staleTime
        self.loader = loader
    }

    public mutating func update() {
        observer.configure(
            client: client,
            key: key,
            staleTime: staleTime,
            loader: loader
        )
    }
}
