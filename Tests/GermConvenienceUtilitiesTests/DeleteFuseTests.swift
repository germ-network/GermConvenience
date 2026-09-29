import Foundation
import GermConvenienceUtilities
import Testing

@Suite struct DeleteFuseTests {
	@Test func testPassesBeforeTrip() throws {
		let fuse = DeleteFuse()
		try fuse.test()
	}

	@Test func testThrowsAfterTrip() throws {
		let fuse = DeleteFuse()
		fuse.trip()
		#expect(throws: DeletionError.alreadyDeleting) {
			try fuse.test()
		}
	}
}
