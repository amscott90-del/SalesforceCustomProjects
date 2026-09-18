public without sharing class PortfolioDocumentGeneratorController {
    public class StartResult {
        @AuraEnabled public Id processId;
        @AuraEnabled public String status;
        @AuraEnabled public String message;
    }
    public class StatusResult {
        @AuraEnabled public Id processId;
        @AuraEnabled public String status;
        @AuraEnabled public Boolean done;
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public String technicalDetails;
        @AuraEnabled public Id pdfContentVersionId;
        @AuraEnabled public Id pdfContentDocumentId;
        @AuraEnabled public String fileUrl;
    }

    @AuraEnabled
    public static StartResult startGeneration(Id recordId, Id documentTemplateId, String title) {
        try {
            if (recordId == null) throw new AuraHandledException('A record ID is required.');
            if (documentTemplateId == null) throw new AuraHandledException('A Document Template ID is required.');

            // Guardrail: the controller runs without sharing, but the caller must be able
            // to read the Quote they are asking us to render.
            List<UserRecordAccess> accessRows = [
                SELECT RecordId, HasReadAccess
                FROM UserRecordAccess
                WHERE UserId = :UserInfo.getUserId()
                  AND RecordId = :recordId
                LIMIT 1
            ];
            if (accessRows.isEmpty() || !accessRows[0].HasReadAccess) {
                throw new AuraHandledException('You do not have access to the record used for document generation.');
            }

            List<DocumentTemplateContentDoc> docs = [
                SELECT Id, LatestContentVersionId
                FROM DocumentTemplateContentDoc
                WHERE DocumentTemplateId = :documentTemplateId
                ORDER BY CreatedDate DESC
                LIMIT 1
            ];
            if (docs.isEmpty() || docs[0].LatestContentVersionId == null) {
                throw new AuraHandledException('No template content version was found for this Document Template.');
            }

            // v6 deliberately bypasses Context Service at DGP insert time. We build the
            // token payload ourselves and pass it directly to Salesforce DocGen.
            String tokenJson = buildQuoteTokenData(recordId);
            if (tokenJson.length() > 130000) {
                throw new AuraHandledException('The quote token payload is larger than 130,000 characters. Use TokenDataContentDocumentId for this unusually large quote.');
            }

            String safeTitle = String.isBlank(title) ? 'Quote' : title.trim();
            DocumentGenerationProcess dgp = new DocumentGenerationProcess();
            dgp.Type = 'GenerateAndConvert';
            dgp.ReferenceObject = recordId;
            dgp.TokenData = tokenJson;
            dgp.DocGenApiVersionType = 'Advanced';
            dgp.RequestText = JSON.serialize(new Map<String, Object>{
                'keepIntermediate' => false,
                'title' => safeTitle,
                'templateContentVersionId' => docs[0].LatestContentVersionId
            });

            Database.SaveResult sr = Database.insert(dgp, false);
            if (!sr.isSuccess()) {
                throw new AuraHandledException('DocumentGenerationProcess insert failed: ' + formatDatabaseErrors(sr.getErrors()));
            }

            StartResult out = new StartResult();
            out.processId = sr.getId();
            out.status = 'Started';
            out.message = 'Document generation started with custom token data.';
            return out;
        } catch (AuraHandledException e) {
            throw e;
        } catch (DmlException e) {
            throw new AuraHandledException(formatDmlException('DML error while starting document generation', e));
        } catch (QueryException e) {
            throw new AuraHandledException('Query error while starting document generation: ' + e.getMessage());
        } catch (Exception e) {
            throw new AuraHandledException(formatException('Unexpected error while starting document generation', e));
        }
    }

    private static String buildQuoteTokenData(Id quoteId) {
        Map<String, Schema.SObjectField> qFields = Quote.SObjectType.getDescribe().fields.getMap();
        Set<String> wanted = new Set<String>{
            'Id','Name','CurrencyIsoCode','TotalAmount','GrandTotal','TotalPrice','ExpirationDate','ExpirationDate__c',
            'Address__c','SalesRepName__c','SalesRepEmail__c','CustomerName__c','CustomerAddress__c',
            'PartnerName__c','PartnerAddress__c','PartnerAddressl__c','DistributorName__c','DistributorAddress__c',
            'ShippingMethod','PaymentTerms','StartDate','QuoteEndDate','QuoteNotes','QuoteNotes__c','Notes','Notes__c',
            'RenewalTerms','RenewalTerms__c','Renewal_Terms__c','Renewal_Terms',
            'Include_Signature_Block__c','Show_Signature_Block__c','Signature_Block__c','Signature_Required__c',
            'SIPLang__c','AILang__c','AITopUpLang__c','NewSkuLand__c','SipLang','AILang','AITopUpLang',
            'BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry','CustomerContactName',
            'AccountId','ContactId'
        };
        List<String> selectFields = existingFields(qFields, wanted);
        if (!selectFields.contains('Id')) selectFields.add('Id');
        SObject quoteRow = Database.query('SELECT ' + String.join(selectFields, ',') + ' FROM Quote WHERE Id = :quoteId LIMIT 1');

        Map<String,Object> root = new Map<String,Object>();
        root.put('SalesTransactionName', firstValue(quoteRow, new List<String>{'Name'}));
        copyToken(root, 'ExpirationDate__c', quoteRow, new List<String>{'ExpirationDate__c','ExpirationDate'});
        copyToken(root, 'Address__c', quoteRow, new List<String>{'Address__c'});
        copyToken(root, 'SalesRepName__c', quoteRow, new List<String>{'SalesRepName__c'});
        copyToken(root, 'SalesRepEmail__c', quoteRow, new List<String>{'SalesRepEmail__c'});
        copyToken(root, 'CustomerName__c', quoteRow, new List<String>{'CustomerName__c'});
        copyToken(root, 'CustomerAddress__c', quoteRow, new List<String>{'CustomerAddress__c'});
        copyToken(root, 'PartnerName__c', quoteRow, new List<String>{'PartnerName__c'});
        copyToken(root, 'PartnerAddress__c', quoteRow, new List<String>{'PartnerAddress__c','PartnerAddressl__c'});
        copyToken(root, 'PartnerAddressl__c', quoteRow, new List<String>{'PartnerAddressl__c','PartnerAddress__c'});
        copyToken(root, 'DistributorName__c', quoteRow, new List<String>{'DistributorName__c'});
        copyToken(root, 'DistributorAddress__c', quoteRow, new List<String>{'DistributorAddress__c'});
        copyToken(root, 'ShippingMethod', quoteRow, new List<String>{'ShippingMethod'});
        copyToken(root, 'PaymentTerms', quoteRow, new List<String>{'PaymentTerms'});
        copyToken(root, 'StartDate', quoteRow, new List<String>{'StartDate'});
        copyToken(root, 'QuoteEndDate', quoteRow, new List<String>{'QuoteEndDate'});
        copyToken(root, 'QuoteNotes', quoteRow, new List<String>{'QuoteNotes','QuoteNotes__c','Notes','Notes__c'});
        copyToken(root, 'Notes', quoteRow, new List<String>{'Notes','Notes__c','QuoteNotes','QuoteNotes__c'});
        copyToken(root, 'RenewalTerms', quoteRow, new List<String>{'RenewalTerms','RenewalTerms__c','Renewal_Terms__c','Renewal_Terms'});
        Object signatureFlag = firstValue(quoteRow, new List<String>{'Include_Signature_Block__c','Show_Signature_Block__c','Signature_Block__c','Signature_Required__c'});
        root.put('IF_ShowSignatureBlock', signatureFlag instanceof Boolean ? (Boolean)signatureFlag : false);
        if (isBlankValue(root.get('RenewalTerms'))) {
            root.put('RenewalTerms', 'Renewal terms are subject to the terms of the applicable customer agreement.');
        }
        copyToken(root, 'SIPLang__c', quoteRow, new List<String>{'SIPLang__c','SipLang'});
        copyToken(root, 'AILang__c', quoteRow, new List<String>{'AILang__c','AILang'});
        copyToken(root, 'AITopUpLang__c', quoteRow, new List<String>{'AITopUpLang__c','AITopUpLang'});
        copyToken(root, 'NewSkuLand__c', quoteRow, new List<String>{'NewSkuLand__c'});
        copyToken(root, 'SipLang', quoteRow, new List<String>{'SipLang','SIPLang__c'});
        copyToken(root, 'AILang', quoteRow, new List<String>{'AILang','AILang__c'});
        copyToken(root, 'AITopUpLang', quoteRow, new List<String>{'AITopUpLang','AITopUpLang__c'});
        for (String f : new List<String>{'BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry','CustomerContactName'}) {
            copyToken(root, f, quoteRow, new List<String>{f});
        }

        // Fill customer/billing values from Account when they aren't denormalized on Quote.
        Id accountId = idValue(quoteRow, 'AccountId');
        if (accountId != null) {
            Map<String, Schema.SObjectField> af = Account.SObjectType.getDescribe().fields.getMap();
            List<String> aq = existingFields(af, new Set<String>{'Id','Name','BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry'});
            SObject acct = Database.query('SELECT ' + String.join(aq, ',') + ' FROM Account WHERE Id = :accountId LIMIT 1');
            putIfBlank(root, 'CustomerName__c', safeGet(acct,'Name'));
            for (String f : new List<String>{'BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry'}) putIfBlank(root, f, safeGet(acct,f));
            if (isBlankValue(root.get('CustomerAddress__c'))) {
                List<String> addressParts = new List<String>();
                for (String f : new List<String>{'BillingStreet','BillingCity','BillingState','BillingPostalCode','BillingCountry'}) {
                    Object v = root.get(f); if (!isBlankValue(v)) addressParts.add(String.valueOf(v));
                }
                root.put('CustomerAddress__c', String.join(addressParts, ', '));
            }
        }

        Id contactId = idValue(quoteRow, 'ContactId');
        if (contactId != null && isBlankValue(root.get('CustomerContactName'))) {
            List<Contact> contacts = [SELECT Name FROM Contact WHERE Id = :contactId LIMIT 1];
            if (!contacts.isEmpty()) root.put('CustomerContactName', contacts[0].Name);
        }

        Decimal total = decimalValue(firstValue(quoteRow, new List<String>{'TotalAmount','GrandTotal','TotalPrice'}));
        String currencyCode = stringValue(safeGet(quoteRow,'CurrencyIsoCode'));
        root.put('TotalAmount', total);
        root.put('TotalAmountFormatted', formatMoney(total, currencyCode));

        Map<String, Schema.SObjectField> liFields = QuoteLineItem.SObjectType.getDescribe().fields.getMap();
        Set<String> liWanted = new Set<String>{
            'Id','QuoteId','QuoteLineGroupId','Product2Id','Quantity','ListPrice','UnitPrice','TotalPrice','NetUnitPrice','NetTotalPrice',
            'Subscription_Term_in_Months__c','TermInMonths__c','Term_Unit_Price__c','TermUnitCost__c','CurrencyIsoCode','SortOrder'
        };
        List<String> liSelect = existingFields(liFields, liWanted);
        String lineOrderBy = liFields.containsKey('SortOrder') ? 'SortOrder ASC NULLS LAST, CreatedDate ASC' : 'CreatedDate ASC';
        List<SObject> lines = Database.query('SELECT ' + String.join(liSelect, ',') + ' FROM QuoteLineItem WHERE QuoteId = :quoteId ORDER BY ' + lineOrderBy);

        Set<Id> productIds = new Set<Id>();
        Set<Id> groupIds = new Set<Id>();
        for (SObject line : lines) {
            Id p = idValue(line,'Product2Id'); if (p != null) productIds.add(p);
            Id g = idValue(line,'QuoteLineGroupId'); if (g != null) groupIds.add(g);
        }
        Map<Id,Product2> products = productIds.isEmpty() ? new Map<Id,Product2>() : new Map<Id,Product2>([SELECT Id, Name, ProductCode FROM Product2 WHERE Id IN :productIds]);

        Map<Id,Map<String,Object>> groupDetails = new Map<Id,Map<String,Object>>();
        List<Id> orderedGroupIds = new List<Id>();
        if (!groupIds.isEmpty()) {
            Map<String,Schema.SObjectField> groupFields = QuoteLineGroup.SObjectType.getDescribe().fields.getMap();
            Set<String> groupWanted = new Set<String>{'Id','Name','StartDate','EndDate','Description','SortOrder'};
            List<String> groupSelect = existingFields(groupFields, groupWanted);
            String groupOrderBy = groupFields.containsKey('SortOrder') ? 'SortOrder ASC NULLS LAST, Name ASC' : 'Name ASC';
            List<SObject> groupRows = Database.query('SELECT ' + String.join(groupSelect, ',') + ' FROM QuoteLineGroup WHERE Id IN :groupIds ORDER BY ' + groupOrderBy);
            for (SObject qlg : groupRows) {
                Id gid = (Id)qlg.get('Id');
                orderedGroupIds.add(gid);
                groupDetails.put(gid, new Map<String,Object>{
                    'name' => stringValue(safeGet(qlg,'Name')),
                    'startDate' => safeGet(qlg,'StartDate'),
                    'endDate' => safeGet(qlg,'EndDate'),
                    'description' => stringValue(safeGet(qlg,'Description'))
                });
            }
        }

        Map<Id,List<Map<String,Object>>> childrenByGroup = new Map<Id,List<Map<String,Object>>>();
        List<Map<String,Object>> ungrouped = new List<Map<String,Object>>();
        Integer lineNumber = 1;
        for (SObject line : lines) {
            Map<String,Object> child = new Map<String,Object>();
            child.put('LineNumber', lineNumber);
            lineNumber++;
            Id pid = idValue(line,'Product2Id'); Product2 prod = products.get(pid);
            child.put('ProductCode', prod == null ? null : prod.ProductCode);
            child.put('ProductName', prod == null ? null : prod.Name);
            child.put('Quantity', safeGet(line,'Quantity'));
            Object term = firstValue(line, new List<String>{'Subscription_Term_in_Months__c','TermInMonths__c'});
            child.put('TermInMonths__c', term);
            Decimal listPrice = decimalValue(safeGet(line,'ListPrice'));
            Decimal netUnit = decimalValue(firstValue(line,new List<String>{'NetUnitPrice','UnitPrice'}));
            Decimal termUnit = decimalValue(firstValue(line,new List<String>{'TermUnitCost__c','Term_Unit_Price__c'}));
            Decimal netTotal = decimalValue(firstValue(line,new List<String>{'NetTotalPrice','TotalPrice'}));
            child.put('ListPrice', listPrice); child.put('NetUnitPrice', netUnit); child.put('TermUnitCost__c', termUnit); child.put('NetTotalPrice', netTotal);
            child.put('ListPriceFormatted', formatMoney(listPrice,currencyCode));
            child.put('NetUnitPriceFormatted', formatMoney(netUnit,currencyCode));
            child.put('TermUnitCostFormatted', formatMoney(termUnit,currencyCode));
            child.put('NetTotalPriceFormatted', formatMoney(netTotal,currencyCode));
            Id gid = idValue(line,'QuoteLineGroupId');
            if (gid == null) ungrouped.add(child);
            else {
                if (!childrenByGroup.containsKey(gid)) childrenByGroup.put(gid,new List<Map<String,Object>>());
                childrenByGroup.get(gid).add(child);
            }
        }

        List<Map<String,Object>> related = new List<Map<String,Object>>();
        for (Id gid : orderedGroupIds) {
            if (childrenByGroup.containsKey(gid)) related.add(makePresentationGroup(groupDetails.get(gid), childrenByGroup.get(gid), currencyCode));
        }
        // Safety fallback if a line references a group that was not returned above.
        for (Id gid : childrenByGroup.keySet()) {
            if (!orderedGroupIds.contains(gid)) related.add(makePresentationGroup(groupDetails.get(gid), childrenByGroup.get(gid), currencyCode));
        }
        if (!ungrouped.isEmpty()) related.add(makePresentationGroup(new Map<String,Object>{'name' => (groupIds.isEmpty() ? 'Products' : 'Ungrouped Products')}, ungrouped, currencyCode));
        root.put('relatedRecords', related);
        return JSON.serialize(root);
    }

    private static Map<String,Object> makePresentationGroup(Map<String,Object> details, List<Map<String,Object>> children, String currencyCode) {
        Decimal subtotal = 0;
        for (Map<String,Object> child : children) {
            Decimal d = decimalValue(child.get('NetTotalPrice')); if (d != null) subtotal += d;
        }
        String name = details == null ? null : stringValue(details.get('name'));
        Date startDate = details != null && details.get('startDate') instanceof Date ? (Date)details.get('startDate') : null;
        Date endDate = details != null && details.get('endDate') instanceof Date ? (Date)details.get('endDate') : null;
        String description = details == null ? null : stringValue(details.get('description'));
        String startFormatted = formatDate(startDate);
        String endFormatted = formatDate(endDate);
        String dateRange = '';
        if (!String.isBlank(startFormatted) && !String.isBlank(endFormatted)) dateRange = startFormatted + ' - ' + endFormatted;
        else if (!String.isBlank(startFormatted)) dateRange = startFormatted;
        else if (!String.isBlank(endFormatted)) dateRange = endFormatted;
        return new Map<String,Object>{
            'GroupName' => String.isBlank(name) ? 'Products' : name,
            'GroupStartDate' => startDate,
            'GroupEndDate' => endDate,
            'GroupStartDateFormatted' => startFormatted,
            'GroupEndDateFormatted' => endFormatted,
            'GroupDateRangeFormatted' => dateRange,
            'GroupDescription' => description,
            'children' => children,
            'SummarySubtotal' => subtotal,
            'SummarySubtotalCalculated' => subtotal,
            'SummarySubtotalFormatted' => formatMoney(subtotal,currencyCode)
        };
    }

    private static String formatDate(Date value) {
        if (value == null) return '';
        String mm = value.month() < 10 ? '0' + String.valueOf(value.month()) : String.valueOf(value.month());
        String dd = value.day() < 10 ? '0' + String.valueOf(value.day()) : String.valueOf(value.day());
        return mm + '/' + dd + '/' + String.valueOf(value.year());
    }

    private static List<String> existingFields(Map<String,Schema.SObjectField> fmap, Set<String> requested) {
        List<String> out = new List<String>();
        for (String f : requested) if (fmap.containsKey(f)) out.add(f);
        out.sort(); return out;
    }
    private static Object safeGet(SObject row, String fieldName) {
        if (row == null || String.isBlank(fieldName) || !row.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) return null;
        return row.get(fieldName);
    }
    private static Object firstValue(SObject row, List<String> names) {
        for (String n : names) { Object v = safeGet(row,n); if (v != null) return v; } return null;
    }
    private static void copyToken(Map<String,Object> target, String token, SObject row, List<String> candidates) { target.put(token, firstValue(row,candidates)); }
    private static void putIfBlank(Map<String,Object> target, String token, Object value) { if (isBlankValue(target.get(token)) && value != null) target.put(token,value); }
    private static Boolean isBlankValue(Object v) { return v == null || (v instanceof String && String.isBlank((String)v)); }
    private static Id idValue(SObject row, String fieldName) { Object v=safeGet(row,fieldName); return v==null?null:(Id)String.valueOf(v); }
    private static Decimal decimalValue(Object v) { if (v == null) return null; try { return Decimal.valueOf(String.valueOf(v)); } catch(Exception e) { return null; } }
    private static String stringValue(Object v) { return v == null ? null : String.valueOf(v); }
    private static String formatMoney(Decimal amount, String currencyCode) {
        if (amount == null) return '';
        String symbol = currencyCode == 'EUR' ? '€' : currencyCode == 'GBP' ? '£' : currencyCode == 'USD' || String.isBlank(currencyCode) ? '$' : currencyCode + ' ';
        Decimal rounded = amount.setScale(2);
        String raw = String.valueOf(rounded);
        List<String> parts = raw.split('\\.');
        String whole = parts[0]; Boolean neg = whole.startsWith('-'); if (neg) whole = whole.substring(1);
        String grouped = ''; Integer count = 0;
        for (Integer i = whole.length() - 1; i >= 0; i--) {
            grouped = whole.substring(i, i + 1) + grouped;
            count++;
            if (count == 3 && i > 0) {
                grouped = ',' + grouped;
                count = 0;
            }
        }
        if (neg) grouped = '-' + grouped;
        String cents = parts.size()>1 ? parts[1] : '00'; while(cents.length()<2) cents += '0';
        return symbol + grouped + '.' + cents;
    }

    @AuraEnabled
    public static StatusResult getStatus(Id processId) {
        try {
            if (processId == null) throw new AuraHandledException('A generation process ID is required.');

            Map<String, Schema.SObjectField> fmap = Schema.SObjectType.DocumentGenerationProcess.fields.getMap();
            List<String> fields = new List<String>{'Id'};
            for (String f : new List<String>{'Status','ResponseText','ErrorMessage','RequestText'}) {
                if (fmap.containsKey(f)) fields.add(f);
            }
            // ReferenceObject and CreatedDate let us resolve the attached PDF even if
            // ResponseText hasn't exposed pdfContentVersionId yet.
            if (fmap.containsKey('ReferenceObject')) fields.add('ReferenceObject');
            fields.add('CreatedDate');

            SObject row = Database.query('SELECT ' + String.join(fields, ',') + ' FROM DocumentGenerationProcess WHERE Id = :processId LIMIT 1');

            String status = value(row, 'Status');
            String response = value(row, 'ResponseText');
            String errorMessage = value(row, 'ErrorMessage');
            String requestText = value(row, 'RequestText');
            Id pdfVersionId = extractId(response, 'pdfContentVersionId', '068');
            Id pdfDocumentId;
            if (pdfVersionId != null) {
                List<ContentVersion> versions = [SELECT ContentDocumentId FROM ContentVersion WHERE Id = :pdfVersionId LIMIT 1];
                if (!versions.isEmpty()) pdfDocumentId = versions[0].ContentDocumentId;
            }

            // Some orgs mark the DGP Completed before ResponseText is normalized with
            // pdfContentVersionId. Since DocGen attaches the result to ReferenceObject,
            // fall back to the newest PDF linked to that record and created by this run.
            if (pdfVersionId == null) {
                Id referenceObjectId;
                try {
                    Object referenceValue = fmap.containsKey('ReferenceObject') ? row.get('ReferenceObject') : null;
                    if (referenceValue != null) referenceObjectId = (Id)String.valueOf(referenceValue);
                } catch (Exception ignored) {}

                Datetime processCreated = (Datetime)row.get('CreatedDate');
                if (referenceObjectId != null && processCreated != null) {
                    Set<Id> linkedDocumentIds = new Set<Id>();
                    for (ContentDocumentLink link : [
                        SELECT ContentDocumentId
                        FROM ContentDocumentLink
                        WHERE LinkedEntityId = :referenceObjectId
                    ]) {
                        linkedDocumentIds.add(link.ContentDocumentId);
                    }

                    if (!linkedDocumentIds.isEmpty()) {
                        Datetime earliest = processCreated.addSeconds(-5);
                        List<ContentVersion> generatedPdfs = [
                            SELECT Id, ContentDocumentId, Title, CreatedDate
                            FROM ContentVersion
                            WHERE ContentDocumentId IN :linkedDocumentIds
                              AND FileExtension = 'pdf'
                              AND CreatedDate >= :earliest
                            ORDER BY CreatedDate DESC
                            LIMIT 1
                        ];
                        if (!generatedPdfs.isEmpty()) {
                            pdfVersionId = generatedPdfs[0].Id;
                            pdfDocumentId = generatedPdfs[0].ContentDocumentId;
                        }
                    }
                }
            }

            String normalized = status == null ? '' : status.replace(' ', '').toLowerCase();
            Boolean failed = normalized.contains('fail') || normalized.contains('error') || normalized.contains('cancel');
            // Don't declare success merely because Status says Completed. Wait until
            // we have the generated PDF Id so the View PDF action always has a target.
            Boolean completed = pdfVersionId != null;

            StatusResult out = new StatusResult();
            out.processId = processId;
            out.status = String.isBlank(status) ? 'Processing' : status;
            out.done = failed || completed;
            out.success = completed && !failed;
            out.pdfContentVersionId = pdfVersionId;
            out.pdfContentDocumentId = pdfDocumentId;
            out.fileUrl = pdfDocumentId == null ? null : '/lightning/r/ContentDocument/' + pdfDocumentId + '/view';

            if (failed) {
                List<String> details = new List<String>();
                if (!String.isBlank(errorMessage)) details.add('ErrorMessage: ' + errorMessage);
                if (!String.isBlank(response)) details.add('ResponseText: ' + response);
                if (!String.isBlank(requestText)) details.add('RequestText: ' + requestText);
                out.message = !String.isBlank(errorMessage) ? errorMessage : (!String.isBlank(response) ? response : 'Document generation failed.');
                out.technicalDetails = String.join(details, '\n');
            } else {
                out.message = out.success ? 'PDF generated successfully.' : 'Generating document…';
                out.technicalDetails = null;
            }
            return out;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(formatException('Error while checking document generation status', e));
        }
    }

    private static String formatDatabaseErrors(Database.Error[] errors) {
        List<String> parts = new List<String>();
        for (Database.Error err : errors) {
            String fields = err.getFields() == null || err.getFields().isEmpty()
                ? ''
                : ' | Fields: ' + String.join(err.getFields(), ', ');
            parts.add(String.valueOf(err.getStatusCode()) + ': ' + err.getMessage() + fields);
        }
        return String.join(parts, ' || ');
    }

    private static String formatDmlException(String prefix, DmlException e) {
        List<String> parts = new List<String>();
        for (Integer i = 0; i < e.getNumDml(); i++) {
            String fields = '';
            try {
                List<String> names = e.getDmlFieldNames(i);
                if (names != null && !names.isEmpty()) fields = ' | Fields: ' + String.join(names, ', ');
            } catch (Exception ignored) {}
            parts.add(String.valueOf(e.getDmlStatusCode(i)) + ': ' + e.getDmlMessage(i) + fields);
        }
        if (parts.isEmpty()) parts.add(e.getMessage());
        return prefix + ': ' + String.join(parts, ' || ');
    }

    private static String formatException(String prefix, Exception e) {
        String typeName = e.getTypeName();
        String message = e.getMessage();
        Integer lineNumber = e.getLineNumber();
        return prefix + ': ' + typeName + ': ' + message + (lineNumber == null ? '' : ' | Apex line ' + lineNumber);
    }

    private static String value(SObject row, String fieldName) {
        if (!row.getSObjectType().getDescribe().fields.getMap().containsKey(fieldName)) return null;
        Object v = row.get(fieldName);
        return v == null ? null : String.valueOf(v);
    }

    private static Id extractId(String jsonText, String key, String prefix) {
        if (String.isBlank(jsonText)) return null;
        try {
            Object raw = JSON.deserializeUntyped(jsonText);
            Id found = findId(raw, key, prefix);
            if (found != null) return found;
        } catch (Exception ignored) {}
        Pattern p = Pattern.compile('(?i)' + Pattern.quote(key) + '[^0-9A-Za-z]+(' + prefix + '[0-9A-Za-z]{12,15})');
        Matcher m = p.matcher(jsonText);
        return m.find() ? (Id)m.group(1) : null;
    }

    private static Id findId(Object node, String key, String prefix) {
        if (node instanceof Map<String,Object>) {
            Map<String,Object> m = (Map<String,Object>)node;
            for (String k : m.keySet()) {
                Object v = m.get(k);
                if (k != null && k.equalsIgnoreCase(key) && v != null) {
                    String s = String.valueOf(v);
                    if (s.startsWith(prefix) && (s.length() == 15 || s.length() == 18)) return (Id)s;
                }
                Id nested = findId(v, key, prefix);
                if (nested != null) return nested;
            }
        } else if (node instanceof List<Object>) {
            for (Object v : (List<Object>)node) {
                Id nested = findId(v, key, prefix);
                if (nested != null) return nested;
            }
        }
        return null;
    }
}
