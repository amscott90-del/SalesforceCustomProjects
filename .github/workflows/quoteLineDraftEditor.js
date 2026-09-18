import { LightningElement, api, track } from 'lwc';
import getLines from '@salesforce/apex/QuoteLineDraftEditorController.getLines';
import searchProducts from '@salesforce/apex/QuoteLineDraftEditorController.searchProducts';
import saveLines from '@salesforce/apex/QuoteLineDraftEditorController.saveLines';
import repriceQuote from '@salesforce/apex/QuoteLineDraftEditorController.repriceQuote';
import getGroups from '@salesforce/apex/QuoteLineDraftEditorController.getGroups';
import saveGroup from '@salesforce/apex/QuoteLineDraftEditorController.saveGroup';
import assignLineToGroup from '@salesforce/apex/QuoteLineDraftEditorController.assignLineToGroup';
import saveLineOrder from '@salesforce/apex/QuoteLineDraftEditorController.saveLineOrder';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

export default class QuoteLineDraftEditor extends LightningElement {
    @api recordId;
    @api quoteId;
    @api overrideFieldApiName = 'Unit_Price__c';
    @api startDateFieldApiName = 'StartDate';
    @api endDateFieldApiName = 'EndDate';
    @api title = 'Quote Lines';
    @api showUnitPrice;
    @api maxProductResults = 25;

    @api saved = false;

    @track rows = [];
    @track productResults = [];
    @track productSearchMessage = '';
    @track productSearchContext = '';
    @track showProductPicker = false;
    @track searchTerm = '';
    @track isBusy = false;
    @track groups = [];
    @track newGroupName = '';
    @track selectedGroupId = '';
    @track renameGroupName = '';
    @track groupStartDate = '';
    @track groupEndDate = '';
    @track groupDescription = '';
    @track showSortModal = false;
    @track sortRows = [];
    @track currencyIsoCode = 'USD';
    draggedSortIndex = null;

    connectedCallback() {
        this.loadEditorData();
    }

    async loadEditorData() {
        if (!this.effectiveQuoteId) return;
        await Promise.all([
            this.loadLines(),
            this.loadGroups()
        ]);
    }

    handleReload() {
        // Full Lightning page refresh. This intentionally exits/restarts the
        // current Flow screen and reloads the Quote record page and all components.
        window.location.reload();
    }

    get effectiveQuoteId() {
        return this.quoteId || this.recordId;
    }

    get hasRows() {
        return this.rows.length > 0;
    }

    get groupOptions() {
        return [{label:'-- No Group --',value:''}, ...this.groups.map(g=>({label:g.name,value:g.id}))];
    }

    get hasGroups() {
        return this.groups.length > 0;
    }

    get groupTotals() {
        const activeRows = this.rows.filter((r) => !r.deleteRow);
        const totals = this.groups.map((g) => {
            const total = activeRows
                .filter((r) => r.groupId === g.id)
                .reduce((sum, r) => sum + (Number(r.totalPrice) || 0), 0);
            return { key: g.id, name: g.name, total };
        });

        const ungroupedTotal = activeRows
            .filter((r) => !r.groupId)
            .reduce((sum, r) => sum + (Number(r.totalPrice) || 0), 0);
        if (ungroupedTotal !== 0) {
            totals.push({ key: 'ungrouped', name: 'Ungrouped Products', total: ungroupedTotal });
        }
        return totals;
    }

    get grandTotal() {
        return this.rows
            .filter((r) => !r.deleteRow)
            .reduce((sum, r) => sum + (Number(r.totalPrice) || 0), 0);
    }

    decorateLineNumbers(rows) {
        return (rows || []).map((row, index) => ({ ...row, lineNumber: index + 1 }));
    }
    async loadGroups() {
        if(!this.effectiveQuoteId)return;
        try{this.groups=await getGroups({quoteId:this.effectiveQuoteId});}
        catch(e){this.toast('Group load failed',this.message(e),'error');}
    }
    handleNewGroupName(e){this.newGroupName=e.target.value;}
    handleSelectedGroup(e){this.selectedGroupId=e.detail.value; const g=this.groups.find(x=>x.id===this.selectedGroupId); this.renameGroupName=g?g.name:''; this.groupStartDate=g?.startDate||''; this.groupEndDate=g?.endDate||''; this.groupDescription=g?.description||'';}
    handleRenameGroupName(e){this.renameGroupName=e.target.value;}
    handleGroupStartDate(e){this.groupStartDate=e.target.value;}
    handleGroupEndDate(e){this.groupEndDate=e.target.value;}
    handleGroupDescription(e){this.groupDescription=e.target.value;}
    async handleCreateGroup(){
        if(!this.newGroupName?.trim()){this.toast('Group Name required','Enter a group name.','warning');return;}
        this.isBusy=true;
        try{const r=JSON.parse(await saveGroup({quoteId:this.effectiveQuoteId,groupId:null,groupName:this.newGroupName,startDate:null,endDate:null,description:null}));if(!r.success)throw new Error(r.message);this.newGroupName='';await this.loadGroups();this.toast('Group created',r.message,'success');}
        catch(e){this.toast('Create group failed',this.message(e),'error');}finally{this.isBusy=false;}
    }
    async handleRenameGroup(){
        if(!this.selectedGroupId||!this.renameGroupName?.trim()){this.toast('Select a group','Choose a group and enter its new name.','warning');return;}
        this.isBusy=true;
        try{const r=JSON.parse(await saveGroup({quoteId:this.effectiveQuoteId,groupId:this.selectedGroupId,groupName:this.renameGroupName,startDate:this.groupStartDate||null,endDate:this.groupEndDate||null,description:this.groupDescription||null}));if(!r.success)throw new Error(r.message);await this.loadGroups();this.toast('Group saved',r.message,'success');}
        catch(e){this.toast('Group save failed',this.message(e),'error');}finally{this.isBusy=false;}
    }
    async handleLineGroupChange(e){
        const row=this.rows.find(r=>r.key===e.target.dataset.key); if(!row)return;
        if(row.isNew||!row.id){this.toast('Save the line first','Save Lines before assigning a new line to a group.','info');return;}
        this.isBusy=true;
        try{const gid=((e.detail && e.detail.value) || e.target.value || null);const r=JSON.parse(await assignLineToGroup({quoteLineId:row.id,groupId:gid}));if(!r.success)throw new Error(r.message);row.groupId=gid||'';this.rows=[...this.rows];this.toast('Group updated','Line moved to the selected group.','success');}
        catch(e2){this.toast('Group update failed',this.message(e2),'error');}finally{this.isBusy=false;}
    }

    get productColumns() {
        return [
            { label: 'Code', fieldName: 'productCode' },
            { label: 'Product', fieldName: 'productName' },
            { label: 'List Price', fieldName: 'listPrice', type: 'currency' }
        ];
    }

    async loadLines() {
        if (!this.effectiveQuoteId) {
            return;
        }
        this.isBusy = true;
        try {
            const data = await getLines({
                quoteId: this.effectiveQuoteId,
                overrideFieldApiName: this.overrideFieldApiName || null,
                startDateFieldApiName: this.startDateFieldApiName || null,
                endDateFieldApiName: this.endDateFieldApiName || null
            });

            const loadedRows = (data || []).map((r) => ({
                key: r.Id,
                id: r.Id,
                pricebookEntryId: r.PricebookEntryId,
                productId: r.PricebookEntry?.Product2Id,
                productName: r.PricebookEntry?.Product2?.Name || '',
                productCode: r.PricebookEntry?.Product2?.ProductCode || '',
                listPrice: r.PricebookEntry?.UnitPrice,
                quantity: r.Quantity,
                unitPrice: r.UnitPrice,
                termInMonths: r.Subscription_Term_in_Months__c,
                termUnitPrice: r.Term_Unit_Price__c,
                totalPrice: r.TotalPrice,
                groupId: r.QuoteLineGroupId || r.GroupId || r.QuoteLineGroup__c || '',
                overridePrice: this.overrideFieldApiName ? r[this.overrideFieldApiName] : null,
                totalOverride: null,
                startDate: this.startDateFieldApiName ? r[this.startDateFieldApiName] : null,
                endDate: this.endDateFieldApiName ? r[this.endDateFieldApiName] : null,
                deleteRow: false,
                deleteRowClass: '',
                isNew: false
            }));
            this.rows = this.decorateLineNumbers(loadedRows);
            const firstCurrency = (data || []).find((r) => r.CurrencyIsoCode)?.CurrencyIsoCode;
            if (firstCurrency) this.currencyIsoCode = firstCurrency;
        } catch (e) {
            this.toast('Error loading quote lines', this.message(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    openProductPicker() {
        this.showProductPicker = true;
        this.searchTerm = '';
        this.productResults = [];
        this.runProductSearch();
    }

    closeProductPicker() {
        this.showProductPicker = false;
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    async runProductSearch() {
        this.isBusy = true;
        try {
            const response = await searchProducts({
                quoteId: this.effectiveQuoteId,
                searchTerm: this.searchTerm,
                maxResults: Number(this.maxProductResults) || 25
            });
            this.productResults = response?.products || [];
            this.productSearchMessage = response?.message || '';
            const pb = response?.pricebook2Id || 'None';
            const cur = response?.currencyIsoCode || 'None';
            this.productSearchContext = `Quote: ${this.effectiveQuoteId} | Price Book: ${pb} | Currency: ${cur}`;
        } catch (e) {
            this.toast('Product search failed', this.message(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleAddProductRow(event) {
        const pbeId = event.currentTarget.dataset.pbe;
        const productId = event.currentTarget.dataset.product;

        const p = this.productResults.find(
            (candidate) =>
                candidate.pricebookEntryId === pbeId &&
                candidate.productId === productId
        );

        if (!p) {
            this.toast(
                'Product selection failed',
                'The selected product could not be resolved from the search results.',
                'error'
            );
            return;
        }

        const addition = {
            key: `new-${Date.now()}-${p.pricebookEntryId}`,
            id: null,
            pricebookEntryId: p.pricebookEntryId,
            productId: p.productId,
            productName: p.productName,
            productCode: p.productCode,
            listPrice: p.listPrice,
            quantity: 1,
            unitPrice: p.listPrice,
            overridePrice: null,
            totalOverride: null,
            startDate: null,
            endDate: null,
            deleteRow: false,
            deleteRowClass: '',
            isNew: true
        };

        this.rows = this.decorateLineNumbers([...this.rows, addition]);
        this.saved = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('saved', false));
        this.toast('Product added', `${p.productName} added as a draft line.`, 'success');
    }

    openSortModal() {
        const persisted = this.rows.filter((r) => !r.isNew && !r.deleteRow && r.id);
        if (persisted.length < 2) {
            this.toast('Nothing to sort', 'Save at least two quote lines before sorting.', 'info');
            return;
        }
        const groupNames = new Map(this.groups.map((g) => [g.id, g.name]));
        this.sortRows = persisted.map((r, index) => ({
            ...r,
            sortIndex: index,
            lineNumber: index + 1,
            groupName: r.groupId ? (groupNames.get(r.groupId) || '') : 'No Group'
        }));
        this.showSortModal = true;
    }

    closeSortModal() {
        this.showSortModal = false;
        this.sortRows = [];
        this.draggedSortIndex = null;
    }

    handleSortDragStart(event) {
        this.draggedSortIndex = Number(event.currentTarget.dataset.index);
        if (event.dataTransfer) {
            event.dataTransfer.effectAllowed = 'move';
            event.dataTransfer.setData('text/plain', String(this.draggedSortIndex));
        }
    }

    handleSortDragOver(event) {
        event.preventDefault();
        if (event.dataTransfer) event.dataTransfer.dropEffect = 'move';
    }

    handleSortDrop(event) {
        event.preventDefault();
        const toIndex = Number(event.currentTarget.dataset.index);
        const fromIndex = this.draggedSortIndex;
        if (!Number.isInteger(fromIndex) || !Number.isInteger(toIndex) || fromIndex === toIndex) return;
        const next = [...this.sortRows];
        const [moved] = next.splice(fromIndex, 1);
        next.splice(toIndex, 0, moved);
        this.sortRows = next.map((r, index) => ({ ...r, sortIndex: index, lineNumber: index + 1 }));
        this.draggedSortIndex = null;
    }

    moveSortRow(event) {
        const index = Number(event.currentTarget.dataset.index);
        const direction = event.currentTarget.dataset.direction;
        const target = direction === 'up' ? index - 1 : index + 1;
        if (target < 0 || target >= this.sortRows.length) return;
        const next = [...this.sortRows];
        [next[index], next[target]] = [next[target], next[index]];
        this.sortRows = next.map((r, i) => ({ ...r, sortIndex: i, lineNumber: i + 1 }));
    }

    async handleSaveSortOrder() {
        this.isBusy = true;
        try {
            const raw = await saveLineOrder({
                quoteId: this.effectiveQuoteId,
                orderedLineIds: this.sortRows.map((r) => r.id)
            });
            const response = JSON.parse(raw);
            if (!response.success) throw new Error(response.message || 'Unable to save line order.');
            this.closeSortModal();
            await this.loadLines();
            this.toast('Order saved', 'Quote lines reordered successfully.', 'success');
        } catch (e) {
            this.toast('Sort failed', this.message(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    handleInput(event) {
        const key = event.target.dataset.key;
        const field = event.target.dataset.field;
        let value = event.target.value;

        if (['quantity', 'unitPrice', 'overridePrice', 'totalOverride'].includes(field)) {
            value = value === '' ? null : Number(value);
        }

        this.rows = this.rows.map((row) => {
            if (row.key !== key) {
                return row;
            }

            const updated = { ...row, [field]: value };

            // Unit Price Override is the effective price input. Reflect it
            // immediately in the Net Unit Price column so the custom editor
            // matches the value that will be persisted/repriced.
            if (field === 'overridePrice' && value !== null) {
                updated.unitPrice = value;
            }

            return updated;
        });

        this.saved = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('saved', false));
    }

    handleDelete(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.decorateLineNumbers(
            this.rows
                .map((row) => row.key === key ? { ...row, deleteRow: true, deleteRowClass: 'deleted-row' } : row)
                .filter((row) => !(row.isNew && row.deleteRow))
        );

        this.saved = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('saved', false));
    }

    handleUndoDelete(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.rows.map((row) =>
            row.key === key ? { ...row, deleteRow: false, deleteRowClass: '' } : row
        );
    }

    handleDuplicate(event) {
        const key = event.currentTarget.dataset.key;
        const source = this.rows.find((r) => r.key === key);
        if (!source) return;

        const clone = {
            ...source,
            key: `new-${Date.now()}-${Math.random()}`,
            id: null,
            deleteRow: false,
            deleteRowClass: '',
            isNew: true
        };
        this.rows = this.decorateLineNumbers([...this.rows, clone]);
        this.saved = false;
        this.dispatchEvent(new FlowAttributeChangeEvent('saved', false));
    }

    async handleSave() {
        if (!this.effectiveQuoteId) {
            this.toast('Missing Quote Id', 'Pass the Quote Id into the component.', 'error');
            return;
        }

        const invalid = this.rows.find((r) =>
            !r.deleteRow &&
            ((!r.pricebookEntryId && !r.productId && !r.productCode) || r.quantity == null || r.quantity <= 0)
        );
        if (invalid) {
            this.toast(
                'Check quote lines',
                'A draft row is missing its Product/Price Book Entry or has an invalid quantity. Remove that row and add the product again.',
                'error'
            );
            return;
        }

        this.isBusy = true;
        try {
            const payload = this.rows.map((r) => ({
                id: r.id || null,
                pricebookEntryId: r.pricebookEntryId || null,
                productId: r.productId || null,
                productCode: r.productCode || null,
                quantity: r.quantity,
                unitPrice: r.unitPrice,
                overridePrice: r.overridePrice,
                totalOverride: r.totalOverride,
                startDate: r.startDate || null,
                endDate: r.endDate || null,
                deleteRow: r.deleteRow === true
            }));

            const rawResponse = await saveLines({
                quoteId: this.effectiveQuoteId,
                rowsJson: JSON.stringify(payload),
                overrideFieldApiName: this.overrideFieldApiName || null,
                startDateFieldApiName: this.startDateFieldApiName || null,
                endDateFieldApiName: this.endDateFieldApiName || null
            });

            const response = JSON.parse(rawResponse);

            if (!response.success) {
                this.toast('Save failed', response.message || 'Unknown server error', 'error');
                return;
            }

            await this.loadLines();
            this.saved = true;
            this.dispatchEvent(new FlowAttributeChangeEvent('saved', true));

            if (response.saved === true && response.repriced !== true) {
                this.toast(
                    'Saved — pricing needs attention',
                    response.message || 'Quote lines saved, but Revenue Cloud pricing did not complete.',
                    'warning'
                );
            } else {
                this.toast(
                    'Saved & Repriced',
                    response.message || 'Quote lines saved and repriced successfully.',
                    'success'
                );
            }
        } catch (e) {
            this.toast('Save failed', this.message(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }


    async handleReprice() {
        if (!this.effectiveQuoteId) {
            this.toast('Missing Quote Id', 'Pass the Quote Id into the component.', 'error');
            return;
        }

        this.isBusy = true;
        try {
            const rawResponse = await repriceQuote({
                quoteId: this.effectiveQuoteId,
                overrideFieldApiName: this.overrideFieldApiName || null,
                startDateFieldApiName: this.startDateFieldApiName || null,
                endDateFieldApiName: this.endDateFieldApiName || null
            });

            const response = JSON.parse(rawResponse);

            if (!response.success) {
                this.toast(
                    'Reprice failed',
                    response.message || 'Revenue Cloud repricing failed.',
                    'error'
                );
                return;
            }

            await this.loadLines();

            this.toast(
                'Repriced',
                response.message || 'Revenue Cloud repricing completed.',
                'success'
            );

            // Give the surrounding record page/CLE a signal that quote-line data
            // has changed, so standard Lightning regions can refresh if supported.
            this.dispatchEvent(new CustomEvent('repricecomplete', {
                detail: { quoteId: this.effectiveQuoteId }
            }));
        } catch (e) {
            this.toast('Reprice failed', this.message(e), 'error');
        } finally {
            this.isBusy = false;
        }
    }

    message(e) {
        if (e?.body?.message) return e.body.message;
        if (Array.isArray(e?.body)) {
            return e.body.map((x) => x.message).filter(Boolean).join('; ');
        }
        if (e?.body?.output?.errors?.length) {
            return e.body.output.errors.map((x) => x.message).filter(Boolean).join('; ');
        }
        if (e?.message) return e.message;
        try {
            return JSON.stringify(e);
        } catch (ignore) {
            return 'Unknown error';
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}
