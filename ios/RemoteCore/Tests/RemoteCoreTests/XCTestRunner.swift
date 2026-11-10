#if canImport(XCTest)
import XCTest
@testable import RemoteCore

/// No Mac, `swift test` corre os mesmos testes que o runner de Linux do CI (CoreTests.all), um por um. O CI de Linux
/// não compila este ficheiro (não liga ao XCTest).
final class RemoteCoreTests: XCTestCase {
    func testCoreTests() {
        for (name, test) in CoreTests.all {
            XCTAssertNoThrow(try test(), name)
        }
    }
}
#endif
