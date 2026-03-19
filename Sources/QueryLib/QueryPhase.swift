public enum QueryPhase<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

extension QueryPhase {
    var value: Value? {
        if case .success(let value) = self {
            return value
        }

        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }

        return false
    }

    var error: Error? {
        if case .failure(let error) = self {
            return error
        }

        return nil
    }
}
