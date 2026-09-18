import { LightningElement, api } from 'lwc';
import startGeneration from '@salesforce/apex/PortfolioDocumentGeneratorController.startGeneration';
import getStatus from '@salesforce/apex/PortfolioDocumentGeneratorController.getStatus';

export default class PortfolioDocumentGenerator extends LightningElement {
    @api recordId;
    @api documentTemplateId;
    @api documentTitle = 'Quote';

    busy = false;
    started = false;
    success = false;
    errorMessage;
    technicalDetails;
    statusText = 'Starting document generation…';
    processId;
    fileUrl;
    pollTimer;
    pollCount = 0;

    disconnectedCallback() { this.stopPolling(); }

    async handleGenerate() {
        this.started = true;
        this.busy = true;
        this.success = false;
        this.errorMessage = null;
        this.technicalDetails = null;
        this.fileUrl = null;
        this.pollCount = 0;
        try {
            const result = await startGeneration({
                recordId: this.recordId,
                documentTemplateId: this.documentTemplateId,
                title: this.documentTitle
            });
            this.processId = result.processId;
            this.statusText = `Generating PDF… Process ${this.processId}`;
            this.pollTimer = window.setInterval(() => this.poll(), 2000);
            await this.poll();
        } catch (e) {
            this.fail(this.messageFromError(e), this.detailsFromError(e));
        }
    }

    async poll() {
        if (!this.processId || !this.busy) return;
        this.pollCount += 1;
        if (this.pollCount > 90) {
            this.fail(
                'Generation is taking longer than expected. The request may still finish in Salesforce Files.',
                `DocumentGenerationProcess Id: ${this.processId}`
            );
            return;
        }
        try {
            const result = await getStatus({ processId: this.processId });
            this.statusText = result.status ? `Generating PDF… ${result.status}` : 'Generating PDF…';
            if (result.done) {
                this.stopPolling();
                this.busy = false;
                if (result.success) {
                    this.success = true;
                    this.fileUrl = result.fileUrl;
                } else {
                    this.errorMessage = result.message || 'Document generation failed.';
                    this.technicalDetails = result.technicalDetails || `DocumentGenerationProcess Id: ${this.processId}`;
                }
            }
        } catch (e) {
            this.fail(this.messageFromError(e), this.detailsFromError(e));
        }
    }

    handleViewPdf() {
        if (this.fileUrl) window.open(this.fileUrl, '_blank');
    }

    reset() {
        this.stopPolling();
        this.busy = false;
        this.started = false;
        this.success = false;
        this.errorMessage = null;
        this.technicalDetails = null;
        this.statusText = 'Starting document generation…';
        this.processId = null;
        this.fileUrl = null;
        this.pollCount = 0;
    }

    stopPolling() {
        if (this.pollTimer) {
            window.clearInterval(this.pollTimer);
            this.pollTimer = null;
        }
    }

    fail(message, technicalDetails) {
        this.stopPolling();
        this.busy = false;
        this.success = false;
        this.errorMessage = message;
        this.technicalDetails = technicalDetails;
    }

    messageFromError(e) {
        if (Array.isArray(e?.body)) {
            return e.body.map(x => x?.message).filter(Boolean).join(' | ') || 'Unexpected document generation error.';
        }
        return e?.body?.message || e?.message || 'Unexpected document generation error.';
    }

    detailsFromError(e) {
        const details = [];
        if (this.processId) details.push(`DocumentGenerationProcess Id: ${this.processId}`);
        if (e?.body?.exceptionType) details.push(`Exception: ${e.body.exceptionType}`);
        if (e?.body?.stackTrace) details.push(`Stack: ${e.body.stackTrace}`);
        if (e?.status) details.push(`HTTP/Action status: ${e.status}`);
        if (e?.statusText) details.push(`Status text: ${e.statusText}`);
        try {
            details.push(`Raw error: ${JSON.stringify(e)}`);
        } catch (ignored) {
            // Nothing else useful to add.
        }
        return details.join('\n');
    }
}
