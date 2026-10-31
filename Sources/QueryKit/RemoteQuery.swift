import SwiftUI

@MainActor
@propertyWrapper
public struct RemoteQuery<Value: Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var client
    @State private var observer = QueryObserver<Value>()

    private let key: any QueryKey
    private let staleTime: TimeInterval
    private let gcTime: TimeInterval?
    private let loader: (@Sendable () async throws -> Value)?

    public var wrappedValue: Value? {
        observer.phase.value
    }

    public var projectedValue: QueryObserver<Value> {
        observer
    }

    /// - Parameter gcTime: How long, in seconds, the cached value is kept once no view
    ///   observes `key`. `nil` uses the client's `defaultGCTime`.
    public init(
        _ key: any QueryKey,
        staleTime: TimeInterval = 60,
        gcTime: TimeInterval? = nil,
        loader: @Sendable @escaping () async throws -> Value
    ) {
        self.key = key
        self.staleTime = staleTime
        self.gcTime = gcTime
        self.loader = loader
    }

    public init(
        _ key: any QueryKey,
        staleTime: TimeInterval = 60,
        gcTime: TimeInterval? = nil
    ) {
        self.key = key
        self.staleTime = staleTime
        self.gcTime = gcTime
        self.loader = nil
    }

    public mutating func update() {
        observer.configure(
            client: client,
            key: key,
            staleTime: staleTime,
            gcTime: gcTime,
            loader: loader
        )
    }
}
