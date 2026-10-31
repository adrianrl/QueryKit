import Foundation

public actor QueryClient: QueryClientProtocol {
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

    private let defaultGCTime: TimeInterval
    /// The longest `gcTime` any observer of each key asked for since the key was last evicted.
    private var gcTimes: [AnyHashable: TimeInterval] = [:]
    private var gcTasks: [AnyHashable: Task<Void, Never>] = [:]

    public static let shared = QueryClient()

    /// Creates a new ``QueryClient`` instance.
    ///
    /// - Parameter defaultGCTime: How long, in seconds, a cached value is kept once no
    ///   query observes its key. A query can ask for longer with its own `gcTime`.
    ///   Pass `.infinity` to never evict.
    /// - Parameter overrideStaleTime: An optional time interval that, if provided,
    ///   will override the stale time for all entries in this client. This is
    ///   useful for testing scenarios where you want to control cache expiration.
    ///   If `nil`, the stale time specified in each query will be used.
    public init(defaultGCTime: TimeInterval = 300, overrideStaleTime: TimeInterval? = nil) {
        self.defaultGCTime = defaultGCTime
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
    /// - Parameter defaultGCTime: How long, in seconds, a cached value is kept once no
    ///   query observes its key. Seeded values count from creation.
    public init<K: QueryKey>(
        seed: [K: any Sendable],
        defaultGCTime: TimeInterval = 300,
        overrideStaleTime: TimeInterval? = nil
    ) {
        for (key, value) in seed {
            cache[AnyHashable(key)] = AnyCacheEntry(value: value, timestamp: Date())
        }

        self.defaultGCTime = defaultGCTime
        self.overrideStaleTime = overrideStaleTime

        let keys = Array(seed.keys)
        Task { await self.scheduleGC(for: keys) }
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
            await write(result, for: key)
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

    public func invalidate(_ key: some QueryKey) async {
        cache.removeValue(forKey: AnyHashable(key))
        notifyInvalidated(key: AnyHashable(key))
    }

    /// Empties the cache and refetches every query that has an observer, as ``invalidate(_:)`` does for one key.
    public func invalidateAll() async {
        cache.removeAll()

        for key in observers.keys {
            notifyInvalidated(key: key)
        }
    }
}

extension QueryClient {
    func subscribe<Value: Sendable>(
        key: some QueryKey,
        observer: QueryObserver<Value>,
        gcTime: TimeInterval?
    ) async {
        let hash = AnyHashable(key)
        let box = WeakBox(observer: observer)
        observers[hash, default: []].append(box)

        if let gcTime {
            gcTimes[hash] = max(gcTimes[hash] ?? 0, gcTime)
        }

        gcTasks.removeValue(forKey: hash)?.cancel()
    }

    func unsubscribe<Value: Sendable>(key: some QueryKey, observer: QueryObserver<Value>) async {
        let hash = AnyHashable(key)
        observers[hash] = observers[hash]?.filter {
            $0.observer !== observer && $0.observer != nil
        }

        scheduleGC(for: [hash])
    }

    /// The cached value for `key`, however old, so an observer can show it while it reloads.
    func cachedValue(for key: any QueryKey) -> (any Sendable)? {
        cache[AnyHashable(key)]?.value
    }

    /// Called from an observer's `deinit`, when its weak box has already been zeroed.
    func observerDidLeave(key: any QueryKey) {
        scheduleGC(for: [AnyHashable(key)])
    }
}

extension QueryClient {
    private func scheduleGC(for keys: [some QueryKey]) {
        scheduleGC(for: keys.map(AnyHashable.init))
    }

    /// Starts the eviction timer for each key that is cached and has no live observer.
    private func scheduleGC(for keys: [AnyHashable]) {
        for key in keys {
            observers[key] = observers[key]?.filter { $0.observer != nil }

            guard cache[key] != nil,
                  observers[key]?.isEmpty ?? true else { continue }

            let gcTime = gcTimes[key] ?? defaultGCTime
            guard gcTime.isFinite else { continue }

            gcTasks[key]?.cancel()
            gcTasks[key] = Task {
                try? await Task.sleep(for: .seconds(gcTime))
                guard !Task.isCancelled else { return }
                self.evict(key)
            }
        }
    }

    private func evict(_ key: AnyHashable) {
        gcTasks[key] = nil
        observers[key] = observers[key]?.filter { $0.observer != nil }

        // An observer may have arrived after the timer fired but before this ran.
        guard observers[key]?.isEmpty ?? true else { return }

        cache.removeValue(forKey: key)
        gcTimes.removeValue(forKey: key)
        observers.removeValue(forKey: key)
    }
}

extension QueryClient {
    /// Runs `operation`, applying `updates` to the cache around it and invalidating `keys` on success.
    ///
    /// Each update's optimistic change is written before `operation` runs. If `operation`
    /// throws, every changed key is restored to its previous value and the error is rethrown.
    /// If it succeeds, each update's `onSuccess` runs on the current cached value, then
    /// `keys` are invalidated.
    @discardableResult
    public func mutate<Result: Sendable>(
        updating updates: [CacheUpdate<Result>] = [],
        invalidate keys: [any QueryKey] = [],
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        var previousValues: [(key: AnyHashable, value: any Sendable)] = []

        for update in updates {
            let key = AnyHashable(update.key)
            guard let previous = cache[key]?.value,
                  let value = update.optimistic(previous) else { continue }

            previousValues.append((key, previous))
            await write(value, for: key)
        }

        let result: Result
        do {
            result = try await operation()
        } catch {
            // Reversed, so two updates on the same key end on the value from before the first.
            for (key, previous) in previousValues.reversed() {
                await write(previous, for: key)
            }
            throw error
        }

        for update in updates {
            let key = AnyHashable(update.key)
            guard let onSuccess = update.onSuccess,
                  let current = cache[key]?.value,
                  let value = onSuccess(current, result) else { continue }

            await write(value, for: key)
        }

        for key in keys {
            await invalidate(key)
        }

        return result
    }

    private func write(_ value: any Sendable, for key: AnyHashable) async {
        cache[key] = AnyCacheEntry(value: value, timestamp: Date())
        await notify(key: key, value: value)
        scheduleGC(for: [key])
    }
}

extension QueryClient {
    /// Writes `value` to the cache for `key` and notifies its observers, without running a loader.
    public func setQueryData<K: QueryKey, Value: Sendable>(_ key: K, value: Value) async {
        await write(value, for: AnyHashable(key))
    }
}
