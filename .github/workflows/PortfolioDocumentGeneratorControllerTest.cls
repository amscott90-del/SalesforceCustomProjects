@IsTest
private class PortfolioDocumentGeneratorControllerTest {
    @IsTest static void statusRequiresId() {
        try {
            PortfolioDocumentGeneratorController.getStatus(null);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
    @IsTest static void startRequiresIds() {
        try {
            PortfolioDocumentGeneratorController.startGeneration(null, null, null);
            System.assert(false, 'Expected exception');
        } catch (AuraHandledException e) {
            System.assert(true);
        }
    }
}
