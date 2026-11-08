import XCTest
@testable import sansan

#if os(iOS)
final class FlythroughEndpointLabelTests: XCTestCase {
    func testWritesEndpointLabelPreviewImages() throws {
        // 모듈이 비활성이어도 드로잉 API는 유지 — 라벨 회귀용 스틸만 생성합니다.
        let directory = URL(fileURLWithPath: "/Users/jeongwook/Documents/sansan/.cursor/assets", isDirectory: true)
        let urls = FlythroughEndpointLabelPreview.writePreviewImages(to: directory)

        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.start.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls.end.path))

        let startLabel = RouteEndpointLabelDrawing.previewImage(kind: .start)
        let endLabel = RouteEndpointLabelDrawing.previewImage(kind: .end, placesLabelOnLeadingSide: true)
        try startLabel.pngData()?.write(to: directory.appendingPathComponent("flythrough-start-label-only.png"))
        try endLabel.pngData()?.write(to: directory.appendingPathComponent("flythrough-end-label-only.png"))
    }
}
#endif
