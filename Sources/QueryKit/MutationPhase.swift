public enum MutationPhase<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

extension MutationPhase {
    var value: Value? {
        if case .success(let value) = self {
            return value
        }

        return nil
    }
}
