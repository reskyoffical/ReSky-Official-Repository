import XCTest
@testable import ReSky

final class ReSkyTests: XCTestCase {
    func testUsernameFormat() {
        XCTAssertNil(UsernameRules.formatProblem("cloud.walker"))
        XCTAssertNotNil(UsernameRules.formatProblem("ab"))
        XCTAssertNotNil(UsernameRules.formatProblem("_bad"))
        XCTAssertNotNil(UsernameRules.formatProblem("bad..name"))
        XCTAssertNotNil(UsernameRules.formatProblem("emoji😀"))
    }

    func testNormalisationDefeatsSubstitutions() {
        XCTAssertEqual(UsernameRules.normalize("AdM1N"), "admin")
        XCTAssertEqual(UsernameRules.normalize("a_d_m_i_n"), "admin")
        XCTAssertEqual(UsernameRules.normalize("ADMIIIN"), "admin")
        XCTAssertEqual(UsernameRules.normalize("Ŝüppört"), "suport")
    }

    func testPasswordRules() {
        XCTAssertFalse(UsernameRules.passwordProblems("short").isEmpty)
        XCTAssertTrue(UsernameRules.passwordProblems("CloudyDay42").isEmpty)
    }

    func testPostgresDates() {
        let d = DateParser.parse("2026-11-12T20:07:00.123456+00:00")
        XCTAssertEqual(d.timeIntervalSince1970, 1_794_514_020.123456, accuracy: 0.001)
        XCTAssertEqual(DateParser.parse("2026-11-12T20:07:00Z").timeIntervalSince1970, 1_794_514_020, accuracy: 0.001)
        XCTAssertEqual(DateParser.parse("2026-11-12 20:07:00+00").timeIntervalSince1970, 1_794_514_020, accuracy: 0.001)
        XCTAssertEqual(DateParser.parse("2026-11-12T21:07:00+01:00").timeIntervalSince1970, 1_794_514_020, accuracy: 0.001)
    }
}
