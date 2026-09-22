public enum QueryPhase<Value> {
    case idle
    case loading
    case success(Value)
    case failure(Error)
}

extension QueryPhase {
    /// The value, if this phase is ``success(_:)``.
    public var value: Value? {
        if case .success(let value) = self {
            return value
        }

        return nil
    }

    /// `true` if this phase is ``loading``.
    ///
    /// This is only the case while there is no value to show. To reflect a
    /// refetch of data that is already loaded, use ``QueryObserver/isFetching``.
    public var isLoading: Bool {
        if case .loading = self { return true }

        return false
    }

    /// The error, if this phase is ``failure(_:)``.
    ///
    /// This is only populated when a fetch fails with no value to fall back on.
    /// For an error from a failed revalidation, use ``QueryObserver/error``.
    public var error: Error? {
        if case .failure(let error) = self {
            return error
        }

        return nil
    }
}
