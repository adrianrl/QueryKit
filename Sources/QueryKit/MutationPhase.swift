public enum MutationPhase<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

extension MutationPhase {
    /// The result of the operation, if this phase is ``success(_:)``.
    public var value: Value? {
        if case .success(let value) = self {
            return value
        }

        return nil
    }
}
