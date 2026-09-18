# Salesforce Revenue Cloud Quote Experience — Portfolio Edition

A white-labeled portfolio sample of a custom Salesforce Revenue Cloud quoting experience. The package demonstrates a Lightning Web Component line editor, Apex orchestration, Revenue Cloud quote-level repricing, quote line grouping/sorting, pricing overrides, and server-side PDF generation using Salesforce Document Generation.

## Included

### Custom Quote Line Editor
- Product search/picker with Product Code, Product Name, and List Price
- Draft line creation and inline editing
- Quantity, dates, unit-price override, and total-price override
- Revenue Cloud quote-level forced repricing
- Total-price override calibration after Revenue Cloud proration
- Quote Line Groups with name, start/end dates, and description
- Per-line group assignment
- Drag/drop line sorting persisted to standard `QuoteLineItem.SortOrder`
- Sequential line numbering
- Group totals and overall grand total
- Full-page Reload action

### Custom Document Generator
- Custom LWC + Apex controller for PDF generation
- Direct `TokenData` architecture rather than relying on client-side Context Service hydration
- Supports grouped and ungrouped quote lines
- Preserves line sort order and line numbers
- Formats line and grand totals
- Supports quote Notes and Renewal Terms tokens
- Supports a conditional signature-block token
- Polls `DocumentGenerationProcess` and exposes the generated PDF when complete
- Includes a record-access guard before running `without sharing` document assembly

## Architecture

`Quote → Custom Line Editor LWC → Apex → Revenue Cloud Pricing → Quote/QLI/Groups → Custom Document Generator LWC → Apex TokenData → DocumentGenerationProcess → PDF`

## Portfolio / Deployment Notes

This is intentionally white-labeled. Company names, org IDs, user IDs, template IDs, customer-specific document templates, and customer-specific legal language are not included.

The code is a portfolio sample, not a drop-in managed product. It assumes Salesforce Revenue Cloud / Revenue Management and Document Generation features are licensed and configured. Some Quote custom field API names are configurable in the line editor; the document generator also checks a set of optional field names. Review those field mappings for any target org before deployment.

The package does **not** include production document templates or customer branding. Supply your own Salesforce Document Template ID to the document generator.

## Notable Design Decisions

- Repricing uses Salesforce Revenue Cloud's quote-level transaction execution pattern rather than directly attempting to update calculated net-price fields.
- Total-price override calibration re-reads the Revenue Cloud-calculated total and adjusts the override when proration causes the initial target to differ.
- PDF generation builds token JSON server-side so standard sales users do not depend on a managed client-side document-generation component to hydrate Context Service data.
- The controller checks the caller's `UserRecordAccess` before using `without sharing` to assemble document data.

## Suggested Portfolio Description

> Designed and built a custom Salesforce Revenue Cloud quoting experience using LWC and Apex, including product selection, inline quote-line editing, pricing overrides, Revenue Cloud repricing, quote line groups, drag-and-drop sorting, calculated totals, and server-side PDF generation. Replaced unreliable standard UI/document-generation behavior with a controlled custom workflow while preserving Salesforce pricing and document-generation services.
