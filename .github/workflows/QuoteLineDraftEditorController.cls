public with sharing class QuoteLineDraftEditorController {
    public class QuoteLineDraftEditorException extends Exception {}

    public class ProductOption {
        @AuraEnabled public Id productId;
        @AuraEnabled public Id pricebookEntryId;
        @AuraEnabled public String productName;
        @AuraEnabled public String productCode;
        @AuraEnabled public Decimal listPrice;
        @AuraEnabled public String currencyIsoCode;
    }

    public class ProductSearchResponse {
        @AuraEnabled public List<ProductOption> products;
        @AuraEnabled public Id quoteId;
        @AuraEnabled public Id pricebook2Id;
        @AuraEnabled public String currencyIsoCode;
        @AuraEnabled public Integer matchingEntryCount;
        @AuraEnabled public String message;
    }

    public class SaveRow {
        public Id id { get; set; }
        public Id pricebookEntryId { get; set; }
        public Id productId { get; set; }
        public String productCode { get; set; }
        public Decimal quantity { get; set; }
        public Decimal unitPrice { get; set; }
        public Decimal overridePrice { get; set; }
        public Decimal totalOverride { get; set; }
        public Date startDate { get; set; }
        public Date endDate { get; set; }
        public Boolean deleteRow { get; set; }
    }

    public class EditorConfig {
        @AuraEnabled public String overrideFieldApiName;
        @AuraEnabled public String startDateFieldApiName;
        @AuraEnabled public String endDateFieldApiName;
    }


    public class GroupOption {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Date startDate;
        @AuraEnabled public Date endDate;
        @AuraEnabled public String description;
    }

    private static String resolveGroupObjectApiName() {
        Map<String, Schema.SObjectType> gd = Schema.getGlobalDescribe();
        for (String c : new List<String>{'QuoteLineGroup','QuoteLineGroup__c'}) if (gd.containsKey(c)) return c;
        return null;
    }
    private static String resolveGroupQuoteLookup(Map<String,Schema.SObjectField> f) {
        for (String c : new List<String>{'QuoteId','Quote__c'}) if (f.containsKey(c)) return c;
        return null;
    }
    private static String resolveQliGroupLookup() {
        Map<String,Schema.SObjectField> f=Schema.SObjectType.QuoteLineItem.fields.getMap();
        for(String c:new List<String>{'QuoteLineGroupId','GroupId','QuoteLineGroup__c'}) if(f.containsKey(c)) return c;
        for(String n:f.keySet()){
            Schema.DescribeFieldResult d=f.get(n).getDescribe();
            if(d.getType()!=Schema.DisplayType.Reference) continue;
            for(Schema.SObjectType t:d.getReferenceTo()){
                String rn=t.getDescribe().getName();
                if(rn=='QuoteLineGroup'||rn=='QuoteLineGroup__c') return n;
            }
        }
        return null;
    }

    @AuraEnabled(cacheable=true)
    public static List<GroupOption> getGroups(Id quoteId) {
        List<GroupOption> out=new List<GroupOption>();
        String o=resolveGroupObjectApiName(); if(quoteId==null||String.isBlank(o)) return out;
        Map<String,Schema.SObjectField> f=Schema.getGlobalDescribe().get(o).getDescribe().fields.getMap();
        String q=resolveGroupQuoteLookup(f); if(String.isBlank(q)||!f.containsKey('Name')) return out;
        List<String> groupSelect=new List<String>{'Id','Name'};
        if(f.containsKey('StartDate')) groupSelect.add('StartDate');
        if(f.containsKey('EndDate')) groupSelect.add('EndDate');
        if(f.containsKey('Description')) groupSelect.add('Description');
        String groupOrder=f.containsKey('SortOrder')?'SortOrder ASC NULLS LAST, Name ASC':'Name ASC';
        for(SObject s:Database.query('SELECT '+String.join(groupSelect,',')+' FROM '+o+' WHERE '+q+' = :quoteId ORDER BY '+groupOrder)){
            GroupOption g=new GroupOption();
            g.id=(Id)s.get('Id'); g.name=(String)s.get('Name');
            g.startDate=f.containsKey('StartDate')?(Date)s.get('StartDate'):null;
            g.endDate=f.containsKey('EndDate')?(Date)s.get('EndDate'):null;
            g.description=f.containsKey('Description')?(String)s.get('Description'):null;
            out.add(g);
        }
        return out;
    }

    @AuraEnabled
    public static String saveGroup(Id quoteId, Id groupId, String groupName, Date startDate, Date endDate, String description) {
        Map<String,Object> r=new Map<String,Object>{'success'=>false,'message'=>null};
        try{
            if(quoteId==null||String.isBlank(groupName)) throw new QuoteLineDraftEditorException('Quote Id and Group Name are required.');
            String o=resolveGroupObjectApiName(); if(String.isBlank(o)) throw new QuoteLineDraftEditorException('Quote Line Group object was not found.');
            Schema.SObjectType typ=Schema.getGlobalDescribe().get(o);
            Map<String,Schema.SObjectField> f=typ.getDescribe().fields.getMap();
            String q=resolveGroupQuoteLookup(f); if(String.isBlank(q)) throw new QuoteLineDraftEditorException('Quote lookup on Quote Line Group was not found.');
            SObject s=groupId==null?typ.newSObject():typ.newSObject(groupId);
            if(groupId==null)s.put(q,quoteId);
            s.put('Name',groupName.trim());
            if(f.containsKey('StartDate')) s.put('StartDate',startDate);
            if(f.containsKey('EndDate')) s.put('EndDate',endDate);
            if(f.containsKey('Description')) s.put('Description',description);
            upsert s;
            r.put('success',true); r.put('groupId',s.get('Id')); r.put('message',groupId==null?'Group created.':'Group details saved.');
        }catch(Exception e){r.put('message',e.getTypeName()+': '+e.getMessage()+' (line '+e.getLineNumber()+')');}
        return JSON.serialize(r);
    }

    @AuraEnabled
    public static String assignLineToGroup(Id quoteLineId, Id groupId) {
        Map<String,Object> r=new Map<String,Object>{'success'=>false,'message'=>null};
        try{
            String f=resolveQliGroupLookup(); if(String.isBlank(f)) throw new QuoteLineDraftEditorException('QuoteLineItem group lookup was not found.');
            QuoteLineItem q=new QuoteLineItem(Id=quoteLineId); q.put(f,groupId); update q;
            r.put('success',true); r.put('message','Line group updated.');
        }catch(Exception e){r.put('message',e.getTypeName()+': '+e.getMessage()+' (line '+e.getLineNumber()+')');}
        return JSON.serialize(r);
    }



    private static String resolveLineSortField() {
        Map<String, Schema.SObjectField> f = Schema.SObjectType.QuoteLineItem.fields.getMap();
        // SortOrder is the standard field used by Salesforce's Quote Line Item sorting UI.
        // Keep this dynamic so the package remains deployable across Revenue Cloud org variants.
        for (String candidate : new List<String>{'SortOrder'}) {
            if (f.containsKey(candidate)) {
                Schema.DescribeFieldResult d = f.get(candidate).getDescribe();
                if (d.isUpdateable()) return candidate;
            }
        }
        return null;
    }

    @AuraEnabled
    public static String saveLineOrder(Id quoteId, List<Id> orderedLineIds) {
        Map<String,Object> r = new Map<String,Object>{'success'=>false,'message'=>null};
        try {
            if (quoteId == null) throw new QuoteLineDraftEditorException('Quote Id is required.');
            if (orderedLineIds == null || orderedLineIds.isEmpty()) throw new QuoteLineDraftEditorException('No quote lines were supplied.');
            String sortField = resolveLineSortField();
            if (String.isBlank(sortField)) throw new QuoteLineDraftEditorException('The standard QuoteLineItem SortOrder field is not available or updateable in this org.');

            Set<Id> requested = new Set<Id>(orderedLineIds);
            Map<Id, QuoteLineItem> actual = new Map<Id, QuoteLineItem>([
                SELECT Id FROM QuoteLineItem WHERE QuoteId = :quoteId AND Id IN :requested
            ]);
            if (actual.size() != requested.size()) throw new QuoteLineDraftEditorException('One or more lines do not belong to this Quote or are not accessible.');

            List<QuoteLineItem> updates = new List<QuoteLineItem>();
            Integer position = 1;
            for (Id lineId : orderedLineIds) {
                QuoteLineItem qli = new QuoteLineItem(Id=lineId);
                qli.put(sortField, position);
                updates.add(qli);
                position++;
            }
            update updates;
            r.put('success', true);
            r.put('message', 'Quote line order saved.');
            r.put('sortField', sortField);
        } catch(Exception e) {
            r.put('message', e.getTypeName()+': '+e.getMessage()+' (line '+e.getLineNumber()+')');
        }
        return JSON.serialize(r);
    }

    @AuraEnabled(cacheable=true)
    public static List<QuoteLineItem> getLines(
        Id quoteId,
        String overrideFieldApiName,
        String startDateFieldApiName,
        String endDateFieldApiName
    ) {
        if (quoteId == null) {
            return new List<QuoteLineItem>();
        }

        if (String.isBlank(startDateFieldApiName)) {
            startDateFieldApiName = 'StartDate';
        }
        if (String.isBlank(endDateFieldApiName)) {
            endDateFieldApiName = 'EndDate';
        }

        Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.QuoteLineItem.fields.getMap();

        List<String> fields = new List<String>{
            'Id',
            'QuoteId',
            'PricebookEntryId',
            'PricebookEntry.Product2Id',
            'PricebookEntry.Product2.Name',
            'PricebookEntry.Product2.ProductCode',
            'PricebookEntry.UnitPrice',
            'Quantity',
            'UnitPrice',
            'TotalPrice'
        };

        for (String candidate : new List<String>{
            overrideFieldApiName,
            startDateFieldApiName,
            endDateFieldApiName,
            'Subscription_Term_in_Months__c',
            'Term_Unit_Price__c',
            'CurrencyIsoCode',
            resolveQliGroupLookup(),
            resolveLineSortField()
        }) {
            if (String.isNotBlank(candidate) && fieldMap.containsKey(candidate) && !fields.contains(candidate)) {
                fields.add(candidate);
            }
        }

        String soql =
            'SELECT ' + String.join(fields, ',') +
            ' FROM QuoteLineItem' +
            ' WHERE QuoteId = :quoteId' +
            (String.isNotBlank(resolveLineSortField()) ? ' ORDER BY ' + resolveLineSortField() + ' NULLS LAST, CreatedDate, Id' : ' ORDER BY CreatedDate, Id');

        return Database.query(soql);
    }

    @AuraEnabled(cacheable=true)
    public static ProductSearchResponse searchProducts(Id quoteId, String searchTerm, Integer maxResults) {
        ProductSearchResponse response = new ProductSearchResponse();
        response.products = new List<ProductOption>();
        response.quoteId = quoteId;

        if (quoteId == null) {
            response.message = 'No Quote Id was passed to the component.';
            return response;
        }

        List<Quote> quotes = [
            SELECT Id, Pricebook2Id, CurrencyIsoCode, OpportunityId, Opportunity.Pricebook2Id
            FROM Quote
            WHERE Id = :quoteId
            LIMIT 1
        ];

        if (quotes.isEmpty()) {
            response.message = 'The supplied record Id is not a Quote or the running user cannot access it.';
            return response;
        }

        Quote q = quotes[0];
        Id effectivePricebookId = q.Pricebook2Id != null ? q.Pricebook2Id : q.Opportunity?.Pricebook2Id;

        response.pricebook2Id = effectivePricebookId;
        response.currencyIsoCode = q.CurrencyIsoCode;

        if (effectivePricebookId == null) {
            response.message = 'This Quote does not have a Price Book, and no Price Book could be inherited from its Opportunity.';
            return response;
        }

        Integer lim = (maxResults == null || maxResults < 1 || maxResults > 100) ? 25 : maxResults;
        String rawTerm = String.isBlank(searchTerm) ? '' : searchTerm.trim();
        String term = '%' + rawTerm + '%';

        List<PricebookEntry> entries = [
            SELECT Id, UnitPrice, CurrencyIsoCode, Product2Id, Product2.Name, Product2.ProductCode
            FROM PricebookEntry
            WHERE Pricebook2Id = :effectivePricebookId
              AND IsActive = true
              AND Product2.IsActive = true
              AND CurrencyIsoCode = :q.CurrencyIsoCode
              AND (Product2.Name LIKE :term OR Product2.ProductCode LIKE :term)
            ORDER BY Product2.ProductCode, Product2.Name
            LIMIT :lim
        ];

        response.matchingEntryCount = entries.size();

        for (PricebookEntry pbe : entries) {
            ProductOption o = new ProductOption();
            o.productId = pbe.Product2Id;
            o.pricebookEntryId = pbe.Id;
            o.productName = pbe.Product2.Name;
            o.productCode = pbe.Product2.ProductCode;
            o.listPrice = pbe.UnitPrice;
            o.currencyIsoCode = pbe.CurrencyIsoCode;
            response.products.add(o);
        }

        if (entries.isEmpty()) {
            response.message =
                'No active Price Book Entries matched Price Book ' + String.valueOf(effectivePricebookId) +
                ' and currency ' + String.valueOf(q.CurrencyIsoCode) +
                (String.isBlank(rawTerm) ? '.' : ' for search "' + rawTerm + '".');
        } else {
            response.message = null;
        }

        return response;
    }

    @AuraEnabled
    public static String saveLines(
        Id quoteId,
        String rowsJson,
        String overrideFieldApiName,
        String startDateFieldApiName,
        String endDateFieldApiName
    ) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false,
            'saved' => false,
            'repriced' => false,
            'message' => null,
            'ids' => new List<Id>()
        };

        try {
            if (quoteId == null) {
                response.put('message', 'Quote Id is required.');
                return JSON.serialize(response);
            }

            List<SaveRow> rows = String.isBlank(rowsJson)
                ? new List<SaveRow>()
                : (List<SaveRow>) JSON.deserialize(rowsJson, List<SaveRow>.class);

            if (String.isBlank(startDateFieldApiName)) {
                startDateFieldApiName = 'StartDate';
            }
            if (String.isBlank(endDateFieldApiName)) {
                endDateFieldApiName = 'EndDate';
            }

            Quote quoteContext = [
                SELECT Id, Pricebook2Id, CurrencyIsoCode, Opportunity.Pricebook2Id
                FROM Quote
                WHERE Id = :quoteId
                LIMIT 1
            ];

            Id effectivePricebookId = quoteContext.Pricebook2Id != null
                ? quoteContext.Pricebook2Id
                : quoteContext.Opportunity?.Pricebook2Id;

            Map<String, Schema.SObjectField> fieldMap =
                Schema.SObjectType.QuoteLineItem.fields.getMap();

            validateOptionalField(
                fieldMap,
                overrideFieldApiName,
                Schema.DisplayType.Currency,
                Schema.DisplayType.Double
            );
            validateOptionalField(
                fieldMap,
                startDateFieldApiName,
                Schema.DisplayType.Date,
                null
            );
            validateOptionalField(
                fieldMap,
                endDateFieldApiName,
                Schema.DisplayType.Date,
                null
            );

            Set<Id> existingIds = new Set<Id>();
            for (SaveRow r : rows) {
                if (r != null && r.id != null) existingIds.add(r.id);
            }

            Map<Id, QuoteLineItem> existing = new Map<Id, QuoteLineItem>();

            if (!existingIds.isEmpty()) {
                List<String> existingFields = new List<String>{
                    'Id',
                    'QuoteId',
                    'PricebookEntryId',
                    'Quantity',
                    'UnitPrice'
                };

                for (String candidate : new List<String>{
                    'PeriodBoundary',
                    'StartQuantity',
                    'AggregatedQuantity',
                    'RevenueCloudPackagingFlag',
                    'StartProrationPeriod',
                    'AllowPartialProrationPeriods',
                    startDateFieldApiName,
                    endDateFieldApiName,
                    'StartDate',
                    'EndDate',
                    'ServiceDate'
                }) {
                    if (
                        String.isNotBlank(candidate) &&
                        fieldMap.containsKey(candidate) &&
                        !existingFields.contains(candidate)
                    ) {
                        existingFields.add(candidate);
                    }
                }

                String existingSoql =
                    'SELECT ' + String.join(existingFields, ',') +
                    ' FROM QuoteLineItem WHERE Id IN :existingIds';

                existing = new Map<Id, QuoteLineItem>(
                    (List<QuoteLineItem>) Database.query(existingSoql)
                );
            }

            List<QuoteLineItem> toInsert = new List<QuoteLineItem>();
            List<QuoteLineItem> toUpdate = new List<QuoteLineItem>();
            List<QuoteLineItem> toDelete = new List<QuoteLineItem>();
            // Total Price Override is a transient editor input. Keep the target
            // totals separately so we can calibrate the unit override against
            // Revenue Cloud's *actual* proration result after pricing runs.
            List<Decimal> insertTargetTotals = new List<Decimal>();
            Map<Id, Decimal> targetTotalByLineId = new Map<Id, Decimal>();

            for (SaveRow r : rows) {
                if (r == null) continue;

                if (r.deleteRow == true) {
                    if (r.id != null && existing.containsKey(r.id)) {
                        toDelete.add(existing.get(r.id));
                    }
                    continue;
                }

                QuoteLineItem qli;
                Boolean isNew = (r.id == null);

                if (!isNew) {
                    if (!existing.containsKey(r.id)) {
                        response.put('message', 'Existing quote line was not found: ' + String.valueOf(r.id));
                        return JSON.serialize(response);
                    }
                    qli = existing.get(r.id);

                    if (qli.QuoteId != quoteId) {
                        response.put('message', 'Quote line ' + String.valueOf(r.id) + ' does not belong to this Quote.');
                        return JSON.serialize(response);
                    }
                } else {
                    Id resolvedPbeId = r.pricebookEntryId;

                    if (resolvedPbeId == null && effectivePricebookId != null) {
                        List<PricebookEntry> matches = new List<PricebookEntry>();

                        if (r.productId != null) {
                            matches = [
                                SELECT Id
                                FROM PricebookEntry
                                WHERE Pricebook2Id = :effectivePricebookId
                                  AND Product2Id = :r.productId
                                  AND CurrencyIsoCode = :quoteContext.CurrencyIsoCode
                                  AND IsActive = true
                                LIMIT 1
                            ];
                        }

                        if (matches.isEmpty() && String.isNotBlank(r.productCode)) {
                            matches = [
                                SELECT Id
                                FROM PricebookEntry
                                WHERE Pricebook2Id = :effectivePricebookId
                                  AND Product2.ProductCode = :r.productCode
                                  AND CurrencyIsoCode = :quoteContext.CurrencyIsoCode
                                  AND IsActive = true
                                  AND Product2.IsActive = true
                                LIMIT 1
                            ];
                        }

                        if (!matches.isEmpty()) {
                            resolvedPbeId = matches[0].Id;
                        }
                    }

                    if (resolvedPbeId == null) {
                        response.put(
                            'message',
                            'Could not resolve a Price Book Entry. ' +
                            'Product Code=' + String.valueOf(r.productCode) +
                            ', Product Id=' + String.valueOf(r.productId) +
                            ', PBE Id=' + String.valueOf(r.pricebookEntryId) +
                            ', Price Book=' + String.valueOf(effectivePricebookId) +
                            ', Currency=' + String.valueOf(quoteContext.CurrencyIsoCode)
                        );
                        return JSON.serialize(response);
                    }

                    qli = new QuoteLineItem(
                        QuoteId = quoteId,
                        PricebookEntryId = resolvedPbeId
                    );

                    // Populate Revenue Cloud subscription/selling-model fields from
                    // the selected Price Book Entry's Product Selling Model.
                    applyRevenueCloudDefaults(
                        qli,
                        resolvedPbeId,
                        r.startDate,
                        r.endDate
                    );
                }

                if (r.quantity != null) qli.Quantity = r.quantity;
                if (r.unitPrice != null) qli.UnitPrice = r.unitPrice;

                // Initialize the same pricing-state inputs that the standard CLE
                // populated in the before/after diff from this org.
                applyClePricingInitialization(qli, r.quantity);

                if (
                    String.isNotBlank(overrideFieldApiName) &&
                    fieldMap.containsKey(overrideFieldApiName)
                ) {
                    Decimal valueToSave = r.overridePrice;

                    if (r.totalOverride != null) {
                        valueToSave = calculateUnitOverrideFromTotal(
                            r.totalOverride,
                            r.quantity,
                            r.startDate,
                            r.endDate
                        );
                    }

                    qli.put(overrideFieldApiName, valueToSave);

                    // Keep the effective/net unit price in sync with the manual
                    // override. The standard Revenue Cloud editor reflects the
                    // override into UnitPrice before repricing; doing the same here
                    // prevents the custom editor from persisting a stale UnitPrice.
                    if (valueToSave != null) {
                        qli.UnitPrice = valueToSave;
                    }
                }

                if (
                    String.isNotBlank(startDateFieldApiName) &&
                    fieldMap.containsKey(startDateFieldApiName)
                ) {
                    qli.put(startDateFieldApiName, r.startDate);
                }

                if (
                    String.isNotBlank(endDateFieldApiName) &&
                    fieldMap.containsKey(endDateFieldApiName)
                ) {
                    qli.put(endDateFieldApiName, r.endDate);
                }

                if (isNew) {
                    toInsert.add(qli);
                    insertTargetTotals.add(r.totalOverride);
                } else {
                    toUpdate.add(qli);
                    if (r.totalOverride != null) {
                        targetTotalByLineId.put(qli.Id, r.totalOverride);
                    }
                }
            }

            List<Id> savedIds = new List<Id>();

            if (!toDelete.isEmpty()) {
                Database.DeleteResult[] deleteResults = Database.delete(toDelete, false);
                for (Integer i = 0; i < deleteResults.size(); i++) {
                    if (!deleteResults[i].isSuccess()) {
                        Database.Error err = deleteResults[i].getErrors()[0];
                        response.put(
                            'message',
                            'Delete failed for Quote Line ' + String.valueOf(toDelete[i].Id) +
                            ': ' + err.getStatusCode() + ' - ' + err.getMessage()
                        );
                        return JSON.serialize(response);
                    }
                }
            }

            if (!toInsert.isEmpty()) {
                Database.SaveResult[] insertResults = Database.insert(toInsert, false);
                for (Integer i = 0; i < insertResults.size(); i++) {
                    if (!insertResults[i].isSuccess()) {
                        Database.Error err = insertResults[i].getErrors()[0];
                        response.put(
                            'message',
                            'Insert failed for product ' +
                            String.valueOf(toInsert[i].PricebookEntryId) +
                            ': ' + err.getStatusCode() + ' - ' + err.getMessage()
                        );
                        return JSON.serialize(response);
                    }
                    Id newLineId = insertResults[i].getId();
                    savedIds.add(newLineId);
                    if (i < insertTargetTotals.size() && insertTargetTotals[i] != null) {
                        targetTotalByLineId.put(newLineId, insertTargetTotals[i]);
                    }
                }
            }

            if (!toUpdate.isEmpty()) {
                Database.SaveResult[] updateResults = Database.update(toUpdate, false);
                for (Integer i = 0; i < updateResults.size(); i++) {
                    if (!updateResults[i].isSuccess()) {
                        Database.Error err = updateResults[i].getErrors()[0];
                        response.put(
                            'message',
                            'Update failed for Quote Line ' + String.valueOf(toUpdate[i].Id) +
                            ': ' + err.getStatusCode() + ' - ' + err.getMessage()
                        );
                        return JSON.serialize(response);
                    }
                    savedIds.add(updateResults[i].getId());
                }
            }

            response.put('saved', true);
            response.put('ids', savedIds);

            try {
                String pricingMessage = forceRepriceQuoteWithLines(
                    quoteId,
                    savedIds,
                    overrideFieldApiName,
                    startDateFieldApiName,
                    endDateFieldApiName
                );

                // The editor's first-pass total override estimate uses calendar
                // dates, but Revenue Cloud can use a slightly different internal
                // proration factor. Calibrate against the actual priced TotalPrice
                // so the requested total lands as close as possible to the user's
                // entered amount. This is intentionally done only for rows where
                // Total Price Override was supplied.
                if (
                    !targetTotalByLineId.isEmpty() &&
                    String.isNotBlank(overrideFieldApiName) &&
                    fieldMap.containsKey(overrideFieldApiName)
                ) {
                    Boolean adjusted = calibrateTotalOverrides(
                        targetTotalByLineId,
                        overrideFieldApiName
                    );
                    if (adjusted) {
                        pricingMessage += ' ' + forceRepriceQuoteWithLines(
                            quoteId,
                            new List<Id>(targetTotalByLineId.keySet()),
                            overrideFieldApiName,
                            startDateFieldApiName,
                            endDateFieldApiName
                        );
                    }
                }

                response.put('repriced', true);
                response.put('success', true);
                response.put(
                    'message',
                    'Quote lines saved and sent through Revenue Cloud pricing. ' +
                    pricingMessage
                );
            } catch (Exception pricingException) {
                response.put('repriced', false);
                response.put('success', true);
                response.put(
                    'message',
                    'Quote lines saved, but Revenue Cloud pricing failed: ' +
                    pricingException.getTypeName() + ': ' +
                    pricingException.getMessage()
                );
            }

            return JSON.serialize(response);

        } catch (Exception e) {
            response.put(
                'message',
                e.getTypeName() + ': ' + e.getMessage() +
                ' (line ' + String.valueOf(e.getLineNumber()) + ')'
            );
            return JSON.serialize(response);
        }
    }

    private static void applyClePricingInitialization(
        QuoteLineItem qli,
        Decimal quantity
    ) {
        if (qli == null) return;

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.QuoteLineItem.fields.getMap();

        // These are the fields that changed when the same line was saved in the
        // standard Revenue Cloud CLE in this org. They are pricing inputs/state,
        // not calculated monetary outputs.
        if (fieldMap.containsKey('PeriodBoundary')) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('PeriodBoundary')
                ? populated.get('PeriodBoundary')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'PeriodBoundary',
                    'Anniversary'
                );
            }
        }

        if (fieldMap.containsKey('StartQuantity')) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('StartQuantity')
                ? populated.get('StartQuantity')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'StartQuantity',
                    0
                );
            }
        }

        if (fieldMap.containsKey('AggregatedQuantity') && quantity != null) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('AggregatedQuantity')
                ? populated.get('AggregatedQuantity')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'AggregatedQuantity',
                    quantity
                );
            }
        }

        if (fieldMap.containsKey('RevenueCloudPackagingFlag')) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('RevenueCloudPackagingFlag')
                ? populated.get('RevenueCloudPackagingFlag')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'RevenueCloudPackagingFlag',
                    'CP'
                );
            }
        }

        // Some Revenue Cloud orgs expose the proration input under these names.
        if (fieldMap.containsKey('StartProrationPeriod')) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('StartProrationPeriod')
                ? populated.get('StartProrationPeriod')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'StartProrationPeriod',
                    'Anniversary'
                );
            }
        }

        if (fieldMap.containsKey('AllowPartialProrationPeriods')) {
            Map<String, Object> populated = qli.getPopulatedFieldsAsMap();
            Object currentValue = populated.containsKey('AllowPartialProrationPeriods')
                ? populated.get('AllowPartialProrationPeriods')
                : null;
            if (currentValue == null) {
                putIfWriteable(
                    qli,
                    fieldMap,
                    'AllowPartialProrationPeriods',
                    true
                );
            }
        }
    }


    private static void applyRevenueCloudDefaults(
        QuoteLineItem qli,
        Id pricebookEntryId,
        Date startDate,
        Date endDate
    ) {
        if (qli == null || pricebookEntryId == null) return;

        Map<String, Schema.SObjectField> qliFields =
            Schema.SObjectType.QuoteLineItem.fields.getMap();
        Map<String, Schema.SObjectField> pbeFields =
            Schema.SObjectType.PricebookEntry.fields.getMap();

        // Revenue Cloud adds ProductSellingModel as a lookup on PricebookEntry.
        // Build the query dynamically so the package remains deployable even if
        // an org exposes a slightly different subset of Revenue Cloud fields.
        if (!pbeFields.containsKey('ProductSellingModelId')) {
            return;
        }

        String soql =
            'SELECT Id, ProductSellingModelId, ' +
            'ProductSellingModel.SellingModelType, ' +
            'ProductSellingModel.PricingTerm, ' +
            'ProductSellingModel.PricingTermUnit ' +
            'FROM PricebookEntry WHERE Id = :pricebookEntryId LIMIT 1';

        SObject pbe = Database.query(soql);
        Id productSellingModelId = (Id) pbe.get('ProductSellingModelId');

        if (productSellingModelId == null) {
            return;
        }

        SObject psm = pbe.getSObject('ProductSellingModel');
        String sellingModelType =
            psm == null ? null : (String) psm.get('SellingModelType');
        Decimal pricingTerm =
            psm == null ? null : (Decimal) psm.get('PricingTerm');
        String pricingTermUnit =
            psm == null ? null : (String) psm.get('PricingTermUnit');

        putIfWriteable(qli, qliFields, 'ProductSellingModelId', productSellingModelId);
        putIfWriteable(qli, qliFields, 'SellingModelType', sellingModelType);
        putIfWriteable(qli, qliFields, 'PricingTerm', pricingTerm);
        putIfWriteable(qli, qliFields, 'PricingTermUnit', pricingTermUnit);

        // QuoteLineItem requires BillingFrequency for Evergreen and TermDefined
        // selling models. Derive it from the Product Selling Model rather than
        // hard-coding Annual.
        if (
            sellingModelType == 'Evergreen' ||
            sellingModelType == 'TermDefined'
        ) {
            String billingFrequency =
                deriveBillingFrequency(pricingTerm, pricingTermUnit);

            putIfWriteable(
                qli,
                qliFields,
                'BillingFrequency',
                billingFrequency
            );
        }

        // Populate standard subscription/service date fields when they exist.
        if (startDate != null) {
            putIfWriteable(qli, qliFields, 'StartDate', startDate);
            putIfWriteable(qli, qliFields, 'ServiceDate', startDate);
        }
        if (endDate != null) {
            putIfWriteable(qli, qliFields, 'EndDate', endDate);
        }

    }

    private static String deriveBillingFrequency(
        Decimal pricingTerm,
        String pricingTermUnit
    ) {
        if (String.isBlank(pricingTermUnit)) {
            return 'Annual';
        }

        if (pricingTermUnit == 'Annual') {
            if (pricingTerm == null || pricingTerm == 1) return 'Annual';
            return 'Annual';
        }

        if (pricingTermUnit == 'Months') {
            Decimal term = pricingTerm == null ? 1 : pricingTerm;

            if (term <= 1) return 'Monthly';
            if (term <= 3) return 'Quarterly';
            if (term <= 6) return 'Semi-Annual';
            return 'Annual';
        }

        // Safe fallback for subscription models when a custom/unknown term unit
        // is encountered. This prevents BillingFrequency from being null.
        return 'Annual';
    }

    private static void putIfWriteable(
        SObject target,
        Map<String, Schema.SObjectField> fieldMap,
        String fieldApiName,
        Object value
    ) {
        if (target == null || value == null || !fieldMap.containsKey(fieldApiName)) {
            return;
        }

        Schema.DescribeFieldResult d = fieldMap.get(fieldApiName).getDescribe();

        if (!(d.isCreateable() || d.isUpdateable())) {
            return;
        }

        Object coercedValue = value;
        Schema.DisplayType fieldType = d.getType();

        if (fieldType == Schema.DisplayType.Integer) {
            Decimal numericValue = Decimal.valueOf(String.valueOf(value));
            coercedValue = Integer.valueOf(
                String.valueOf(numericValue.setScale(0, RoundingMode.HALF_UP))
            );
        } else if (
            fieldType == Schema.DisplayType.Double ||
            fieldType == Schema.DisplayType.Currency ||
            fieldType == Schema.DisplayType.Percent
        ) {
            coercedValue = Decimal.valueOf(String.valueOf(value));
        } else if (fieldType == Schema.DisplayType.String ||
                   fieldType == Schema.DisplayType.TextArea ||
                   fieldType == Schema.DisplayType.Picklist ||
                   fieldType == Schema.DisplayType.MultiPicklist) {
            coercedValue = String.valueOf(value);
        } else if (fieldType == Schema.DisplayType.Date && !(value instanceof Date)) {
            coercedValue = Date.valueOf(String.valueOf(value));
        } else if (fieldType == Schema.DisplayType.Boolean && !(value instanceof Boolean)) {
            coercedValue = Boolean.valueOf(String.valueOf(value));
        }

        target.put(fieldApiName, coercedValue);
    }


    @AuraEnabled
    public static String repriceQuote(
        Id quoteId,
        String overrideFieldApiName,
        String startDateFieldApiName,
        String endDateFieldApiName
    ) {
        Map<String, Object> response = new Map<String, Object>{
            'success' => false,
            'message' => null
        };

        try {
            if (quoteId == null) {
                response.put('message', 'Quote Id is required.');
                return JSON.serialize(response);
            }

            if (String.isBlank(startDateFieldApiName)) {
                startDateFieldApiName = 'StartDate';
            }
            if (String.isBlank(endDateFieldApiName)) {
                endDateFieldApiName = 'EndDate';
            }

            List<Id> quoteLineIds = new List<Id>();
            for (QuoteLineItem qli : [
                SELECT Id
                FROM QuoteLineItem
                WHERE QuoteId = :quoteId
            ]) {
                quoteLineIds.add(qli.Id);
            }

            String message = forceRepriceQuoteWithLines(
                quoteId,
                quoteLineIds,
                overrideFieldApiName,
                startDateFieldApiName,
                endDateFieldApiName
            );

            response.put('success', true);
            response.put(
                'message',
                'Revenue Cloud Reprice All completed. ' + message
            );
            return JSON.serialize(response);

        } catch (Exception e) {
            response.put(
                'message',
                e.getTypeName() + ': ' + e.getMessage() +
                ' (line ' + String.valueOf(e.getLineNumber()) + ')'
            );
            return JSON.serialize(response);
        }
    }


    private static String forceRepriceQuoteWithLines(
        Id quoteId,
        List<Id> quoteLineIds,
        String overrideFieldApiName,
        String startDateFieldApiName,
        String endDateFieldApiName
    ) {
        /*
         * Salesforce's documented Revenue Cloud Advanced automation pattern for
         * Reprice All sends a PATCH for the Quote itself and uses FORCE pricing.
         *
         * Do NOT resend every QuoteLineItem in the graph here. The lines have
         * already been committed by saveLines(), and adding line PATCH records
         * changes this from a quote-level forced repricing request into another
         * transaction update. That was the reason our custom Reprice could return
         * successfully while calculated fields such as NetUnitPrice remained stale.
         */
        RevSalesTrxn.PricingPreferenceEnum pricingPreference =
            RevSalesTrxn.PricingPreferenceEnum.FORCE;

        RevSalesTrxn.ConfigurationExecutionEnum configurationExecution =
            RevSalesTrxn.ConfigurationExecutionEnum.SYSTEM;

        RevSalesTrxn.ConfigurationOptionsInput configurationOptions =
            new RevSalesTrxn.ConfigurationOptionsInput();

        configurationOptions.addDefaultConfiguration = true;
        configurationOptions.executeConfigurationRules = true;
        configurationOptions.validateAmendRenewCancel = true;
        configurationOptions.validateProductCatalog = true;

        RevSalesTrxn.RecordResource quoteRecord =
            new RevSalesTrxn.RecordResource(
                Quote.getSObjectType(),
                'PATCH',
                String.valueOf(quoteId)
            );

        RevSalesTrxn.RecordWithReferenceRequest quoteObject =
            new RevSalesTrxn.RecordWithReferenceRequest(
                'refQuote',
                quoteRecord
            );

        List<RevSalesTrxn.RecordWithReferenceRequest> records =
            new List<RevSalesTrxn.RecordWithReferenceRequest>{
                quoteObject
            };

        RevSalesTrxn.GraphRequest graph =
            new RevSalesTrxn.GraphRequest(
                'draftLineEditorRepriceAll',
                records
            );

        RevSalesTrxn.PlaceSalesTransactionResponse pricingResponse =
            RevSalesTrxn.PlaceSalesTransactionExecutor.execute(
                graph,
                pricingPreference,
                configurationExecution,
                configurationOptions,
                null
            );

        return 'Forced quote-level pricing completed for ' +
            String.valueOf(quoteLineIds == null ? 0 : quoteLineIds.size()) +
            ' line item(s).';
    }


    private static Boolean calibrateTotalOverrides(
        Map<Id, Decimal> targetTotalByLineId,
        String overrideFieldApiName
    ) {
        if (targetTotalByLineId == null || targetTotalByLineId.isEmpty()) return false;

        Map<String, Schema.SObjectField> fieldMap =
            Schema.SObjectType.QuoteLineItem.fields.getMap();
        if (String.isBlank(overrideFieldApiName) || !fieldMap.containsKey(overrideFieldApiName)) {
            return false;
        }

        List<String> fields = new List<String>{'Id', 'UnitPrice', 'TotalPrice'};
        if (!fields.contains(overrideFieldApiName)) fields.add(overrideFieldApiName);
        Set<Id> lineIds = targetTotalByLineId.keySet();
        List<QuoteLineItem> pricedLines = (List<QuoteLineItem>) Database.query(
            'SELECT ' + String.join(fields, ',') +
            ' FROM QuoteLineItem WHERE Id IN :lineIds'
        );

        List<QuoteLineItem> corrections = new List<QuoteLineItem>();
        for (QuoteLineItem priced : pricedLines) {
            Decimal target = targetTotalByLineId.get(priced.Id);
            Decimal actual = priced.TotalPrice;
            Object rawOverride = priced.get(overrideFieldApiName);
            Decimal currentOverride = rawOverride == null ? priced.UnitPrice : (Decimal) rawOverride;

            if (
                target == null || actual == null || actual == 0 ||
                currentOverride == null || currentOverride == 0
            ) {
                continue;
            }

            // Ignore penny-level noise. For larger differences, Revenue Cloud's
            // actual total tells us its true effective proration factor. Because
            // line totals are linear with unit price in this use case, scaling the
            // current override by target/actual converges directly on the target.
            if ((target - actual).abs() <= Decimal.valueOf('0.02')) continue;

            Decimal correctedOverride =
                (currentOverride * target / actual).setScale(6, RoundingMode.HALF_UP);

            QuoteLineItem correction = new QuoteLineItem(Id = priced.Id);
            correction.put(overrideFieldApiName, correctedOverride);
            correction.UnitPrice = correctedOverride;
            corrections.add(correction);
        }

        if (!corrections.isEmpty()) {
            update corrections;
            return true;
        }
        return false;
    }

    private static Decimal calculateUnitOverrideFromTotal(
        Decimal totalOverride,
        Decimal quantity,
        Date startDate,
        Date endDate
    ) {
        if (totalOverride == null) return null;
        if (quantity == null || quantity <= 0) {
            throw new QuoteLineDraftEditorException('Quantity must be greater than 0 when Total Price Override is entered.');
        }
        if (startDate == null || endDate == null) {
            throw new QuoteLineDraftEditorException('Start Date and End Date are required when Total Price Override is entered.');
        }
        if (endDate < startDate) {
            throw new QuoteLineDraftEditorException('End Date must be on or after Start Date.');
        }

        // Proration uses actual calendar days across a 365-day year.
        // This is deterministic and avoids month-boundary ambiguity.
        Integer inclusiveDays = startDate.daysBetween(endDate) + 1;
        Decimal prorationFactor = Decimal.valueOf(String.valueOf(inclusiveDays)) / Decimal.valueOf('365');

        if (prorationFactor <= 0) {
            throw new AuraHandledException('Unable to calculate a valid proration factor.');
        }

        Decimal unitOverride = totalOverride / quantity / prorationFactor;
        return unitOverride.setScale(6, RoundingMode.HALF_UP);
    }

    private static void validateOptionalField(
        Map<String, Schema.SObjectField> fieldMap,
        String apiName,
        Schema.DisplayType expected1,
        Schema.DisplayType expected2
    ) {
        if (String.isBlank(apiName)) return;
        if (!fieldMap.containsKey(apiName)) {
            throw new AuraHandledException('QuoteLineItem field not found: ' + apiName);
        }

        Schema.DisplayType actual = fieldMap.get(apiName).getDescribe().getType();
        if (actual != expected1 && (expected2 == null || actual != expected2)) {
            throw new AuraHandledException('Unexpected field type for ' + apiName + ': ' + String.valueOf(actual));
        }
    }
}
