import Foundation

public actor QueryClient {
    private struct AnyCacheEntry {
        let value: any Sendable
        let timestamp: Date
    }

    private var observers: [AnyHashable: [WeakBox]] = [:]

    struct WeakBox {
        weak var observer: AnyQueryObserver?
    }

    private var cache: [AnyHashable: AnyCacheEntry] = [:]
    private var runningTasks: [AnyHashable: Task<any Sendable, Error>] = [:]
    private let overrideStaleTime: TimeInterval?

    public static let shared = QueryClient()

    /// Creates a new ``QueryClient`` instance.
    ///
    /// - Parameter overrideStaleTime: An optional time interval that, if provided,
    ///   will override the stale time for all entries in this client. This is
    ///   useful for testing scenarios where you want to control cache expiration.
    ///   If `nil`, the stale time specified in each query will be used.
    public init(overrideStaleTime: TimeInterval? = nil) {
        self.overrideStaleTime = overrideStaleTime
    }

    /// Creates a ``QueryClient`` with pre-populated cache entries.
    ///
    /// Use this initializer to seed the cache with known values, which is useful
    /// for testing or pre-warming the cache with server-provided data.
    ///
    /// - Parameter seed: A dictionary mapping ``QueryKey`` values to their
    ///   corresponding cached values. Each entry is stored with a timestamp
    ///   of the current date and time.
    /// - Parameter overrideStaleTime: An optional time interval that, if provided,
    ///   will override the stale time for all entries in this client. This is
    ///   useful for testing scenarios where you want to control cache expiration.
    ///   If `nil`, the stale time specified in each query will be used.
    public init<K: QueryKey>(seed: [K: any Sendable], overrideStaleTime: TimeInterval? = nil) {
        for (key, value) in seed {
            cache[AnyHashable(key)] = AnyCacheEntry(value: value, timestamp: Date())
        }

        self.overrideStaleTime = overrideStaleTime
    }

    public func fetch<Value: Sendable>(
        key: some QueryKey,
        staleTime: TimeInterval = 60,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        try await fetch(key: AnyHashable(key), staleTime: staleTime, loader: loader)
    }

    func fetch<Value: Sendable>(
        key: AnyHashable,
        staleTime: TimeInterval = 60,
        loader: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        // Return valid cache
        let effectiveStaleTime = overrideStaleTime ?? staleTime
        if let entry = cache[key],
           let value = entry.value as? Value,
           Date().timeIntervalSince(entry.timestamp) < effectiveStaleTime {
            return value
        }

        // Deduplicate in-flight requests
        if let existingTask = runningTasks[key] {
            return try await existingTask.value as! Value
        }

        // Create new task
        let task = Task<any Sendable, Error> {
            let value = try await loader()
            return value
        }

        runningTasks[key] = task
        
        defer {
            runningTasks[key] = nil
        }

        do {
            let result = try await task.value as! Value
            cache[key] = AnyCacheEntry(value: result, timestamp: Date())
            await notify(key: key, value: result)
            return result
        } catch {
            throw error
        }
    }

    private func notify(key: AnyHashable, value: any Sendable) async {
        observers[key] = observers[key]?.filter { $0.observer != nil }

        for box in observers[key] ?? [] {
            await box.observer?.receive(value: value)
        }
    }
    
    private func notifyInvalidated(key: AnyHashable) {
        observers[key] = observers[key]?.filter { $0.observer != nil }
    
        Task {
            for box in observers[key] ?? [] {
                await box.observer?.didInvalidate()
            }
        }
    }

    public func invalidate(_ key: some QueryKey) {
        cache.removeValue(forKey: AnyHashable(key))
        notifyInvalidated(key: AnyHashable(key))
    }

    public func invalidateAll() {
        cache.removeAll()
    }
}

extension QueryClient {
    func subscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) {
        let hash = AnyHashable(key)
        let box = WeakBox(observer: observer)
        observers[hash, default: []].append(box)
    }

    func unsubscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) {
        let hash = AnyHashable(key)
        observers[hash] = observers[hash]?.filter {
            $0.observer !== observer && $0.observer != nil
        }
    }
}

extension QueryClient {
    @discardableResult
    public func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: (@Sendable (inout QueryValue) -> Void),
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        let hash = AnyHashable(key)
        var previousValue: QueryValue?

        if let entry = cache[hash],
           let value = entry.value as? QueryValue {
            previousValue = value
        }

        if var value = previousValue {
            onMutate(&value)
            await setCacheValue(key, value: value)
        }

        do {
            let result = try await operation()

            if invalidate {
                self.invalidate(key)
            }

            return result
        } catch {
            if let previousValue {
                await setCacheValue(key, value: previousValue)
            }

            throw error
        }
    }

    @discardableResult
    public func mutate<K: QueryKey, QueryValue: Sendable, Result: Sendable>(
        _ key: K,
        invalidate: Bool,
        onMutate: (@Sendable (inout QueryValue) -> Void)? = nil,
        onSuccess: (@Sendable (inout QueryValue, Result) -> Void),
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        let hash = AnyHashable(key)
        var previousValue: QueryValue?
    
        if let entry = cache[hash],
           let value = entry.value as? QueryValue {
            previousValue = value
        }
    
        if var value = previousValue {
            onMutate?(&value)
            await setCacheValue(key, value: value)
        }
    
        do {
            let result = try await operation()

            if invalidate {
                self.invalidate(key)
                return result
            }

            if var value = previousValue {
                onSuccess(&value, result)
                await setCacheValue(key, value: value)
            }

            return result
        } catch {
            if let previousValue {
                await setCacheValue(key, value: previousValue)
            }
    
            throw error
        }
    }

    public func mutate<K: QueryKey, Result: Sendable>(
        _ key: K,
        operation: @Sendable () async throws -> Result
    ) async throws {
        do {
            _ = try await operation()
            invalidate(key)
        } catch {
            throw error
        }
    }
}

extension QueryClient {    
    func setCacheValue<K: QueryKey, Value: Sendable>(_ key: K, value: Value) async {
        let key = AnyHashable(key)
        
        cache[key] = AnyCacheEntry(value: value, timestamp: Date())
        await notify(key: key, value: value)
    }
}
