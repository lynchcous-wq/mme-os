# Security Policy

## Reporting a vulnerability

Please do not disclose suspected vulnerabilities in public issues or pull requests. Report them privately to the repository owner through GitHub's private vulnerability reporting feature when enabled, or use the repository owner's verified private contact channel.

Include the affected component, impact, reproduction steps, and any suggested mitigation. Do not include real customer, employee, payment, authentication, or other sensitive production data in a report.

## Supported deployment posture

This repository is under active development. A successful source build does not mean the application is production-secure or approved to process real customer, employee, inventory, payroll, or payment data.

Until the relevant controls are implemented and independently verified:

- Do not place real secrets, API keys, access tokens, or credentials in source control.
- Do not commit customer or employee personal information, payment card data, or production exports.
- Do not enable live payment collection.
- Do not treat sample catalog items or prices as actual inventory or approved prices.
- Keep development, preview/staging, and production credentials and data separated.
- Enforce authorization on the server; hiding a user-interface control is not access control.

## Security review expectations

Changes affecting authentication, authorization, payment handling, personal data, payroll, inventory adjustments, pricing, secrets, or deployment permissions require focused review and appropriate automated tests before release.
