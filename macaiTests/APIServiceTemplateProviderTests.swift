import XCTest
@testable import macai

final class APIServiceTemplateProviderTests: XCTestCase {
    func testLoadCatalogReturnsTemplates() {
        let catalog = APIServiceTemplateProvider.loadCatalog()
        XCTAssertGreaterThan(catalog.providers.count, 0, "Expected to load bundled API service templates")
        XCTAssertNotNil(catalog.providers.first?.models.first?.settings, "Templates should opt in to default settings")
    }
}
