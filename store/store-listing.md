# HQR Metadata Mover: Microsoft Store listing and submission notes

Copy each block into the matching Partner Center field (Store listings > English).

---

## Product name
HQR Metadata Mover

## Short description  (Store limit: 1,000 characters; shown in search results)
Move your Salesforce changes from one org to another: find what changed, package it, validate, deploy, and roll back if you need to. Free, and it runs on your own PC.

## Description
Change Sets miss things. HQR Metadata Mover finds them.

HQR Metadata Mover moves metadata between your Salesforce orgs, from a developer sandbox to INT, UAT and production. Scan two orgs to see what you changed, build a package, validate it, deploy it, and roll it back if something goes wrong. It finds the pieces an Experience Cloud site needs, so a whole site moves in one click.

Built for Salesforce admins, developers and consultants who want a simple, free way to deploy, without a subscription.

WHAT YOU GET
• Find what changed: compare two orgs and filter by date, by who changed it, and by whether it's new to the target
• A warning when someone changed the same component in the target after you, before you overwrite their work
• Whole Experience Cloud sites in one click: the network, branding, site, bundle, configuration, navigation menus and static resource, for Aura and LWR sites
• Validate, Quick Deploy and Deploy, with errors, test failures and code coverage shown as they come in
• Rollback: before each deploy it saves the target's current versions, so you can put things back and remove what the deploy added
• Reuse packages: deploy the same package to INT, then UAT, then production, with every result kept in Package History
• Site admin and guest record owner usernames are matched to the right user in each sandbox and in production
• Templates for the kinds of changes you make often
• Extra confirmation before anything touches a production org

PRIVATE BY DESIGN
No accounts, no ads, no tracking, no data collection. Everything stays on your PC. It only talks to the Salesforce orgs you connect, through your own Salesforce CLI logins.

Requires the free Salesforce CLI from Salesforce. The app shows the download link if it isn't installed.

Free from House of Quintanilla-Reese LLC. Not affiliated with or endorsed by Salesforce, Inc. Salesforce is a trademark of Salesforce, Inc.

## What's new in this version
First Microsoft Store release.

## Product features  (up to 20, one per line)
Compare two Salesforce orgs and see what changed
Filter changes by date, by who made them, and by new or existing
Warns before you overwrite someone else's newer change
Whole Experience Cloud sites in one click, Aura and LWR
Validate, Quick Deploy and Deploy with live results
Test failures and code coverage shown as they come in
Rollback that restores the target's previous versions
Reuse one package from sandbox to UAT to production
Package History with the result of every deploy
Matches site usernames between sandboxes and production
Templates for changes you make often
Extra confirmation for production orgs
Private: no accounts, ads or tracking

## Search terms  (up to 7)
salesforce
deployment
metadata
change sets
sandbox
experience cloud
devops

## Category
Developer tools  (subcategory: none required)

## Privacy policy URL
Publish store\privacy-policy.md on your website, for example at
https://www.quintanillareese.com/metadata-mover-privacy/
and paste that address here (Partner Center: Properties > Privacy policy URL).

## Website
https://www.quintanillareese.com/downloads/  (add the anchor for the Metadata Mover section if it has one)

## Support contact info
Your support email address or a contact page on quintanillareese.com.

## Copyright and trademark info
Copyright (c) 2026 House of Quintanilla-Reese LLC. Salesforce is a trademark of Salesforce, Inc.; HQR Metadata Mover is not affiliated with or endorsed by Salesforce.

---

## Submission notes (Partner Center fields)

**Pricing and availability:** Free. All markets is fine.

**Properties:**
- Category: Developer tools
- "This product accesses, collects, or transmits personal information": **No**. We don't collect or
  receive anything. The app sends metadata only between the user's own PC and the Salesforce orgs the user
  connects, through the user's own Salesforce CLI logins. (A privacy policy URL is still required
  because the app uses the network.)
- System requirements: Windows 10 version 1809 or later, and the free Salesforce CLI. The app opens in
  Google Chrome or Microsoft Edge, and Edge comes with Windows.
- Dependencies: if Partner Center asks whether the app depends on non-Microsoft software, answer yes and
  name the Salesforce CLI (free, from developer.salesforce.com/tools/salesforcecli). The description
  already says so.

**Age ratings:** Complete the questionnaire. Answer "No" to violence, sex, language, drugs, and
gambling. There's no user-to-user communication, no purchases, and no sharing of location. This
should come out as rated for everyone (3+).

**Restricted capability, runFullTrust:** Partner Center asks why the app needs it. Suggested
answer:
> HQR Metadata Mover is a desktop (Win32) app. It needs full trust to run the user's installed
> Salesforce CLI, save deployment packages and backups in the user's Documents folder, and show its
> interface in a local browser window served from localhost.

**Notes for certification** (helps the tester):
> Launch HQR Metadata Mover from Start. It opens in its own window within a few seconds. The app
> deploys metadata between Salesforce orgs and needs the free Salesforce CLI
> (developer.salesforce.com/tools/salesforcecli) and a Salesforce org to do that; a free Developer
> Edition org from developer.salesforce.com/signup works. Without the CLI, the app still opens and
> shows a notice with the download link. With it, "Connect an Org…" opens the Salesforce login page in
> the default browser. "Stop Server" closes the app; closing the window also stops it after 10
> minutes. No sign-in to our service is required.

**Screenshots:** At least 1, ideally 4. Use 1366×768 or larger, PNG. Don't show real org names,
usernames or components: open the app, then open `http://localhost:8770/?demo` in Chrome or Edge
(F12 > device toolbar can set the exact 1366×768 size). Demo mode shows a made-up company
("Brightwater Health") with three orgs, changes, an Experience site and package history; scans,
builds, validations, deploys and rollbacks are all simulated and never touch a real org. Suggested shots:
1. Find Changes with a scan result and the filters
2. An Experience Site added in one click, on the Package step
3. A validation or deploy with results and code coverage
4. Package History with Roll Back…

**Store logos:** Partner Center can use the icons already in the package. If it asks for a
300×300 Store logo, use `store\StoreLogo-300.png`.

**Building the upload file:** run `build-store.ps1` and upload `dist\store\HQR-MetadataMover-<version>.msix`
under Packages. For an update, raise `$Version` in `server.ps1` first; the Store needs a higher version
every time.
