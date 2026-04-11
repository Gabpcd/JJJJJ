---
**LEGAL MEMORANDUM**

**Subject:** Invoice Factoring Legal Framework — Jolene Marketplace

**Prepared for:** Finqle B.V. — Partnership & Legal Teams
**Prepared by:** Jolene SAS — Gabrielle Picard, President
**Date:** April 8, 2026
**Version:** 1.0

---

## 1. Company Information

| | |
|---|---|
| **Legal Name** | Jolene |
| **Legal Form** | SASU — *Société par Actions Simplifiée Unipersonnelle* (single-shareholder simplified joint-stock company) |
| **SIREN** | 103 305 744 |
| **SIRET (HQ)** | 103 305 744 00015 |
| **RCS** | Paris — 103 305 744 R.C.S. Paris |
| **Intra-EU VAT** | FR75 01103305744 |
| **Share Capital** | €1,000 |
| **APE Code** | 6201Z — Computer Programming |
| **Registered Office** | 103 rue de Vaugirard, 75006 Paris, France |
| **Incorporation Date** | April 7, 2026 |
| **President** | Gabrielle Picard |

---

## 2. Business Model

Jolene operates a **B2B digital marketplace** connecting French healthcare establishments (public hospitals, private clinics, nursing homes, home care services, pharmacies, health centers) with **independent healthcare professionals** (nurses, caregivers, physiotherapists, midwives, doctors, pharmacists) for temporary or recurring assignments.

**Role distribution:**
- **Supply side:** self-employed healthcare professionals under liberal status (professions libérales réglementées), each holding their own RPPS/ADELI professional ID and individual social security registration (URSSAF)
- **Demand side:** healthcare establishments (both public and private sector)
- **Jolene:** matching platform, contract facilitator, invoicing technical agent, payment rail operator (via Stripe Connect)

---

## 3. Invoice Issuance — Legal Basis

Under **Article 289 I-2 of the French General Tax Code** (*Code Général des Impôts*), a taxable person may authorize a third party, through a written mandate, to issue invoices on its behalf. This is the legal mechanism Jolene uses.

**Implementation:**
- At onboarding, each healthcare professional signs an **electronic invoicing mandate** granting Jolene the authority to issue invoices in their name for missions performed via the platform.
- The mandate is accepted via click-wrap, timestamped, and cryptographically hashed (SHA-256 of the signed document content).
- The signature audit record contains: signer ID, timestamp, IP address, user agent, document version, and document hash.
- Invoices issued carry the **legal identity of the freelancer** (name, SIREN if applicable, RPPS number, professional address) — Jolene is named as the technical issuer in a footer, but is **not** the legal seller.

**Key consequence:** the freelancer remains the legal vendor of the professional service. Jolene acts strictly as a technical mandate holder for invoice production and electronic dispatch.

---

## 4. Receivables Assignment — Legal Basis

For factoring purposes, Jolene acquires legal ownership of the receivable at the moment a freelancer requests an advance. This is done via a **receivables assignment agreement** (*cession de créance*) governed by **Articles 1321 to 1326 of the French Civil Code** (*Code civil*).

**Implementation:**
- When a freelancer clicks "Receive payment now" on a specific invoice, a click-wrap modal displays the full receivables assignment agreement (version-controlled, hash-signed).
- Upon acceptance, the freelancer transfers full ownership of that specific receivable to Jolene, in exchange for the net amount (after factoring and platform fees).
- The assignment is **invoice-by-invoice**, not global — each invoice is assigned individually at the moment of the advance request.
- The debtor (healthcare establishment) is notified of the assignment pursuant to **Article 1324 of the Civil Code**, which makes the assignment enforceable against the debtor.

**Key consequence:** as of the moment of signature, Jolene becomes the **sole legal creditor** of the healthcare establishment for that specific invoice and is fully authorized to **resell the receivable to a factor** (such as Finqle) without requiring further consent from the freelancer.

---

## 5. Freelancer Legal Status — Safeguards

The entire legal framework is designed to **preserve the independent status** of healthcare professionals. Specifically:

- Jolene is **not** a temporary work agency (*Entreprise de Travail Temporaire*) and does not hold an ETT license
- Jolene is **not** a wage portage company (*société de portage salarial*)
- Jolene is **not** an employer — there is **no subordination relationship** (*lien de subordination*) with freelancers
- Freelancers retain full autonomy: own URSSAF registration, own professional liability insurance, own tax and social declarations, own pricing authority (within accepted missions)
- The invoicing mandate and the receivables assignment are **purely contractual tools** that do not modify the tax, social, or professional status of the freelancer

This framework is explicitly acknowledged in both legal documents and is consistent with the operational models of major French B2B marketplaces (Malt, Comet, Brigad, Side, StaffMe).

---

## 6. VAT Treatment

Medical and paramedical services performed by regulated healthcare professionals are **VAT-exempt** in France under **Article 261-4 of the General Tax Code**.

- Invoices are issued with no VAT charge
- The VAT-exempt status is explicitly mentioned on each invoice (reference to Article 261-4 CGI)
- Jolene collects no VAT on behalf of freelancers for healthcare services

This treatment is equivalent to the Dutch *btw-vrijstelling voor medische diensten* regime, and should simplify cross-border processing for Finqle.

---

## 7. Debtor Profile & Credit Risk

Healthcare establishments on Jolene fall into two categories:

**Public sector (approx. 40%):**
- Public hospitals (CHU, CH), public EHPAD, public health centers, HAD services
- Payments via Chorus Pro (mandatory e-invoicing platform for French public sector)
- Payment term: legally capped at 50 days (Article L. 2192-12 of the Public Procurement Code)
- **Credit risk: effectively zero** — public sector payers are state-guaranteed

**Private sector (approx. 60%):**
- Private clinics (often part of groups: Ramsay Santé, Elsan, Vivalto, Almaviva)
- Private nursing homes (Korian, Orpea, DomusVi, Emeis)
- Private pharmacies
- Payment term: contractually set at 30 days (France B2B default)
- **Credit risk: low** — healthcare establishments are heavily regulated and financially stable

Average invoice amount: €300 to €600 TTC per mission.

---

## 8. Technical Infrastructure (Ready to Integrate)

Jolene's technical stack is fully prepared for factor integration and is **provider-agnostic** by design:

- **Backend:** Supabase (PostgreSQL, Edge Functions, Auth, Storage, RLS) — hosted in EU
- **Frontend:** React 18 + TypeScript + Vite
- **Payment rail:** Stripe Connect (merchant-of-record model, PSP-licensed)
- **Document trail:** electronic signature audit logs (timestamped, hash-signed, RGPD-compliant, Article 1366-1367 of the Civil Code)
- **Factor integration layer:** generic `FactorProvider` interface with adapter classes — Finqle adapter can be added in < 2 hours of development once API credentials are provided
- **Invoice generation:** PDF Factur-X compatible, automated on mission completion
- **Webhook handling:** HMAC-SHA256 signature verification, automatic state machine transitions
- **UI:** "Receive payment now" modal with click-wrap consent, deployed and waiting for activation

---

## 9. Request to Finqle

Jolene is seeking a **strategic factoring partnership** with Finqle to enable instant payment (24–48h) for healthcare freelancers, backed by Finqle's risk assessment of the debtor establishments.

**What we are offering Finqle:**
- Access to a curated network of vetted French healthcare freelancers (target: 100+ active by Q4 2026)
- A pipeline of low-risk receivables from well-rated healthcare establishments
- A strategic entry point into the French healthcare marketplace sector
- A fast technical integration (days, not months) on our side

**What we are asking Finqle:**
- API-based factoring service (invoice submission + instant decision + funding + collection)
- Reasonable pricing transparent to freelancers (target: 2–3% fee)
- Sandbox access for integration and testing
- Webhook support for status updates

---

## 10. Contact

**Gabrielle Picard**
President, Jolene SAS
103 rue de Vaugirard, 75006 Paris, France
Email: contact@jolene.app
Platform: https://jolene.app

---

*This memorandum is provided for information purposes in the context of commercial discussions between Jolene SAS and Finqle B.V. It does not constitute legal advice and should be read in conjunction with the underlying contractual documents (invoicing mandate, receivables assignment agreement, platform terms of service) available on request.*
