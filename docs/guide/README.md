# Guide: from a fresh install to a paid invoice

Every screen below is the real Odoo 20 Community built by this repo's `./setup.sh` on a fresh
Ubuntu 24.04 VM (2 vCPU / 2 GB / 20 GB), with Odoo's demo data for six apps. Captured on 2026-11-13
in headless Chrome at 1440×900. The errors are real too: they are the most useful part.

Contents: [1. Install](#1-install) · [2. Log in](#2-log-in) · [3. Contacts and CRM](#3-contacts-and-crm) ·
[4. Quotation to sales order](#4-quotation-to-sales-order) · [5. Deliver](#5-deliver) ·
[6. Invoice and payment](#6-invoice-and-payment) · [7. Where to look next](#7-where-to-look-next) ·
[8. Errors you will meet](#8-errors-you-will-meet)

## 1. Install

On a Linux host with Docker:

```
git clone https://github.com/laris-co/odoo20-stack-template odoo20-stack && cd odoo20-stack
./setup.sh
```

`setup.sh` writes random secrets into `.env`, pulls the images, creates the database `odoo`, starts
Postgres, Odoo, Kong and Dagu, then verifies. On the 2 GB VM it took 102 s, most of it pulling the
1 GB `odoo:20.0` image. The verify block it ends with:

```
odoo  /web/login (direct)        200
kong  /web/login                 200
kong  /web/database/manager      404  (must be 404)
url   http://127.0.0.1:8100/web/login   200
modules installed: 16
backup none yet
```

Demo data (optional, for trying it out) was loaded on the same VM with
`odoo -d odoo -i base,sale_management,account,stock,crm,contacts --with-demo --stop-after-init`:
81 modules in 51 s. In Odoo 20 the flag is `--with-demo`; no demo is the default.

## 2. Log in

Open the URL (`http://127.0.0.1:8100` locally, your `tailscale serve` URL on the tailnet). The admin
login is `admin`; its password is the one you set, never `admin`.

![Odoo 20 login page: Email, Password, Log in, Use a Passkey](images/S01-login.jpg)

The database manager is never reachable. Kong answers it itself, before Odoo sees the request:

![/web/database/manager returns Kong's JSON "not here"](images/S03-dbmanager-404.jpg)

After login, the grid icon at the top left lists the installed apps:

![App menu open over Contacts: Discuss, Calendar, Contacts, CRM, Sales, Invoicing, Inventory, Apps, Settings](images/S02-apps-home.jpg)

## 3. Contacts and CRM

**Contacts** holds every company and person; everything else points at them.

![Contacts list: Acme Corporation, Azure Interior, Gemini Furniture and their people](images/S04-contacts.jpg)

Open a company to see its address, tax ID, people, and the smart buttons (opportunities, sales,
invoiced) across the top:

![Acme Corporation contact form with address, TIN and three related contacts](images/S05-contact-acme.jpg)

**CRM** is a pipeline: drag a card from New to Qualified, Proposition, Won.

![CRM pipeline kanban with New, Qualified, Proposition and Won columns](images/S06-crm-pipeline.jpg)

A card opens into the opportunity: expected revenue, probability, the customer, and **New Quotation**
to turn it into a sale.

![Opportunity "Open Space Design": $11,000 expected, 45% probability, Acme Corporation](images/S07-crm-lead.jpg)

## 4. Quotation to sales order

**Sales** lists quotations and orders, with what is left to invoice:

![Quotations list with status and invoice status columns](images/S08-sales-quotations.jpg)

Open a draft quotation and press **Confirm**:

![Draft quotation S00005 for Acme Corporation, Office Lamp, total $465.75](images/S09-quotation-draft.jpg)

It becomes a sales order and a delivery is created (the **Delivery** smart button):

![S00005 now a Sales Order, Not Delivered, with a Delivery button](images/S10-order-confirmed.jpg)

## 5. Deliver

Products whose invoicing policy is *delivered quantities* (most stockable products) can only be
invoiced after they ship. This walk-through continues with order S00018 (Gemini Furniture), whose
delivery is **Ready**:

![Delivery WH/OUT/00039: Acoustic Bloc Screens 0 of 2 available, Office Chair Black 2 of 2](images/S15-delivery.jpg)

Press **Validate**. Only one of the two products was in stock, so Odoo asks about the rest:

![Create Backorder? dialog: Create Backorder, No Backorder, Discard](images/S22-backorder-dialog.jpg)

**Create Backorder** ships what is there now and keeps the rest as a new delivery. A fresh install
then asks about SMS confirmations; **Disable SMS** turns that off for good:

![SMS dialog: Confirm, Disable SMS, Discard](images/S23-sms-dialog.jpg)

The delivery is **Done**, and its chatter names the backorder:

![WH/OUT/00039 Done with Office Chair Black 2 of 2](images/S24-delivery-done.jpg)

## 6. Invoice and payment

Back on the order, **Create Invoice** → **Regular invoice** → **Create Draft**:

![Create invoice(s) dialog with Regular invoice selected](images/S25-invoice-wizard-regular.jpg)

The draft invoice holds only what was delivered (2 chairs, $241.00):

![Draft customer invoice for Gemini Furniture, Office Chair Black x2, $241.00](images/S26-invoice-draft.jpg)

**Confirm** posts it and gives it a number:

![Posted invoice INV/2026/00010, $241.00 due](images/S27-invoice-posted.jpg)

**Pay** opens the payment dialog (journal Bank, amount, date):

![Pay dialog: Journal Bank, Amount $241.00](images/S28-payment-wizard.jpg)

**Create Payment**, and the invoice is marked paid, amount due $0.00:

![INV/2026/00010 with the PAID ribbon and Amount Due $0.00](images/S29-invoice-paid.jpg)

## 7. Where to look next

**Inventory** overview: receipts and deliveries waiting.

![Inventory Overview: 7 to receive, 24 to deliver](images/S14-inventory-overview.jpg)

**Invoicing**: every customer invoice and credit note with its status.

![Invoices list with amounts and Posted status](images/S18-invoices.jpg)

**Settings**: users, languages, companies (the demo data has three).

![General Settings: Users, Languages, Companies, Document Layout](images/S20-settings.jpg)

## 8. Errors you will meet

Each of these happened while making this guide.

**Create Invoice defaults to a down payment and fails at 0.** On an order with nothing delivered,
the wizard picks *Down payment* with amount 0.00:

![Invalid Operation: The value of the down payment amount must be positive](images/L0-downpayment-default.jpg)

**Regular invoice before delivery fails too.** Nothing is invoiceable until it ships; the message says
how to change the product's invoicing policy to *Ordered quantities* if you sell that way:

![Invalid Operation: Cannot create an invoice. No items are available to invoice.](images/L3-invoice-nothing-delivered.jpg)

**A delivery with no stock waits.** Order S00005's Office Lamp had 0 available:

![WH/OUT/00040 Waiting: Office Lamp demand 1.00, quantity 0.00](images/L1-delivery-no-stock.jpg)

and validating it anyway is refused:

![Invalid Operation: Validating a zero quantity transfer](images/L2-validate-zero-qty.jpg)

Receive stock first (Inventory → Receipts), or set the quantity by hand if it really shipped.

**The Accounting dashboard says Access Error** for the demo admin of this Community install
(opened at `/odoo/accounting`). The **Invoicing** app is the one to use here:

![Access Error: You do not have access to the Accounting Dashboard](images/S17-accounting-dashboard.jpg)
