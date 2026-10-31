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
}
