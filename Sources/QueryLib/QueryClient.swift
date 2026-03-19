import Foundation

public actor QueryClient {
    private struct AnyCacheEntry {
        let value: any Sendable
        let timestamp: Date
    }

    private var cache: [AnyHashable: AnyCacheEntry] = [:]
    private var runningTasks: [AnyHashable: Task<any Sendable, Error>] = [:]

    public static let shared = QueryClient()

    public init() {}

    /// Creates a ``QueryClient`` with pre-populated cache entries.
    ///
    /// Use this initializer to seed the cache with known values, which is useful
    /// for testing or pre-warming the cache with server-provided data.
    ///
    /// - Parameter seed: A dictionary mapping ``QueryKey`` values to their
    ///   corresponding cached values. Each entry is stored with a timestamp
    ///   of the current date and time.
    public init<K: QueryKey>(seed: [K: any Sendable]) {
        for (key, value) in seed {
            cache[AnyHashable(key)] = AnyCacheEntry(value: value, timestamp: Date())
        }
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
        if let entry = cache[key],
           let value = entry.value as? Value,
           Date().timeIntervalSince(entry.timestamp) < staleTime {
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

        do {
            let result = try await task.value as! Value
            cache[key] = AnyCacheEntry(value: result, timestamp: Date())
            runningTasks[key] = nil
            return result
        } catch {
            runningTasks[key] = nil
            throw error
        }
    }

    public func invalidate(_ key: some QueryKey) {
        cache.removeValue(forKey: AnyHashable(key))
    }

    func invalidate(_ key: AnyHashable) {
        cache.removeValue(forKey: key)
    }

    public func invalidateAll() {
        cache.removeAll()
    }
}

extension QueryClient {
    public func mutate<Value, K: QueryKey>(
        invalidate keys: [K],
        operation: @Sendable () async throws -> Value
    ) async throws -> Value {
        let result = try await operation()

        for key in keys {
            invalidate(AnyHashable(key))
        }

        return result
    }
}
