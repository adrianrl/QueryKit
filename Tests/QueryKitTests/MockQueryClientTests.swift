import Testing

@testable import QueryKit

@Suite("MockQueryClient tests")
struct MockQueryClientTests {
    private enum TestError: Error { case failed }

    @Test("An optimistic update reaches views observing a stubbed key")
    @MainActor
    func testOptimisticUpdateInPreview() async {
        let mock = MockQueryClient().stub(TestKey.users, phase: .success(["a", "b"]))
        let query = QueryObserver<[String]>()
        query.configure(client: mock, key: TestKey.users, staleTime: nil) { ["unused"] }
        for _ in 0..<5 { await Task.yield() } // let configure's subscribe Task run
        await query.fetch()
        #expect(query.phase.value == ["a", "b"])

        let mutation = MutationObserver<Void>()
        mutation.configure(client: mock)
        await mutation.mutate(
            updating: .init(TestKey.users) { (users: inout [String]) in users.removeAll { $0 == "a" } }
        ) { }

        #expect(query.phase.value == ["b"])
    }

    @Test("A failed mutation in a preview rolls back the optimistic change")
    @MainActor
    func testRollbackInPreview() async {
        let mock = MockQueryClient().stub(TestKey.users, phase: .success(["a"]))
        let query = QueryObserver<[String]>()
        query.configure(client: mock, key: TestKey.users, staleTime: nil) { ["unused"] }
        for _ in 0..<5 { await Task.yield() }
        await query.fetch()

        let mutation = MutationObserver<Void>()
        mutation.configure(client: mock)
        await mutation.mutate(
            updating: .init(TestKey.users) { (users: inout [String]) in users.append("b") }
        ) {
            throw TestError.failed
        }

        #expect(mutation.error is TestError)
        #expect(query.phase.value == ["a"])
    }

    @Test("Failure stubs still fail")
    @MainActor
    func testFailureStub() async {
        let mock = MockQueryClient().stub(TestKey.users, phase: QueryPhase<[String]>.failure(TestError.failed))
        let query = QueryObserver<[String]>()
        query.configure(client: mock, key: TestKey.users, staleTime: nil) { ["unused"] }

        await query.fetch()

        #expect(query.error is TestError)
    }

    @Test("fetchNextPage never calls the page loader in a preview")
    @MainActor
    func testFetchNextPageDoesNotLoad() async {
        final class Calls: @unchecked Sendable { var count = 0 }
        let calls = Calls()
        let mock = MockQueryClient().stub(
            TestKey.posts,
            phase: .success(InfiniteData<[String], Int>(pages: [["1"]], pageParams: [1]))
        )
        let list = InfiniteQueryObserver<[String], Int>()
        list.configure(
            client: mock,
            key: TestKey.posts,
            staleTime: nil,
            initialPageParam: 1,
            getNextPageParam: { _, _, last in last + 1 },
            pageLoader: { page in
                calls.count += 1
                return ["\(page)"]
            }
        )
        await list.fetch()
        #expect(list.hasNextPage)

        let next = Task { await list.fetchNextPage() }
        for _ in 0..<10 { await Task.yield() }

        #expect(calls.count == 0)
        #expect(list.phase.value?.pages == [["1"]])
        next.cancel()
    }
}
