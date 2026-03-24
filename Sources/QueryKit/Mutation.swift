import SwiftUI

@MainActor
@propertyWrapper
public struct Mutation<Value: Sendable>: @preconcurrency DynamicProperty {
    @Environment(\.queryClient) private var client
    @State private var observer = MutationObserver<Value>()

    public var wrappedValue: MutationObserver<Value> {
        observer
    }

    public init() {}

    public mutating func update() {
        observer.configure(client: client)
    }
}
