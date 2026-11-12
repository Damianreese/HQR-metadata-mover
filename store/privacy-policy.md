# HQR Metadata Mover privacy policy

*Last updated: November 2026*

HQR Metadata Mover is a free Salesforce deployment tool made by House of Quintanilla-Reese LLC
("we"). This policy explains what the app does with information on your PC. The short version:
**everything stays on your PC and in your own Salesforce orgs, and we never receive any of it.**

## What the app collects

Nothing is collected by us. HQR Metadata Mover has no accounts, no sign-in to our service, no
analytics, no advertising and no tracking of any kind.

## What the app does on your PC

To do its job, HQR Metadata Mover works with the following information **locally, on your PC only**:

- **Your Salesforce metadata.** When you scan, package, validate or deploy, it reads metadata (such as
  objects, fields, code, flows and Experience Cloud sites) from the Salesforce orgs you connect and
  sends it only to the target org you choose. It also reads basic details about each change, such as
  who last changed it and when, so it can show them in the app.
- **Packages, backups and history.** It saves the packages you build, the backups it takes before each
  deploy (for rollback), the results of your deploys and your templates in your Documents folder
  (`HQR Metadata Mover`). These are copies of your orgs' metadata, so keep that folder as private as the
  orgs themselves. If your Documents folder is backed up (for example by OneDrive), these files are
  backed up with it.
- **A log file** (`server.log` in the same folder) that records what the app did, to help you or us
  troubleshoot. It stays on your PC unless you choose to send it to us.
- **Usernames in Experience Cloud sites.** When a site names a site admin or guest record owner who
  doesn't exist in the target org, the app looks up matching users in the target org to pick the right
  one, and lists each change in the Activity Log.

## Your Salesforce logins

HQR Metadata Mover doesn't see or store your Salesforce password. It works through the Salesforce CLI,
a separate free tool made by Salesforce. When you connect an org, the Salesforce login page opens in
your own browser, and the Salesforce CLI keeps the resulting login on your PC. The Salesforce CLI is
covered by Salesforce's own terms and privacy policy.

The only network traffic the app creates is between your PC and the Salesforce orgs you connect.

## The app window

The app is shown in a browser window by a small web server built into the app. That server only
accepts connections from your own PC (`localhost`) and is protected by a key that changes every time it
starts, so other devices and websites can't use it. The app window uses its own separate browser
profile, so it doesn't read your browsing history, bookmarks or sign-ins. Links, such as "View in
Setup", open in your usual browser.

## Sharing the app

If you use "Share with a colleague", the app opens your own email service (or copies a message
for you to paste) with a link to our website. We don't see who you share with.

## Removing your data

Uninstalling HQR Metadata Mover removes the app and its window profile. Your packages, backups and log
in `Documents\HQR Metadata Mover` stay until you delete that folder, and your Salesforce CLI logins
stay until you log out of them in the Salesforce CLI.

## Children

HQR Metadata Mover is a business tool for Salesforce professionals and does not knowingly collect
information from anyone, including children.

## Changes

If this policy changes, we'll update the date above and post the new version at this address.

## Contact

House of Quintanilla-Reese LLC
[quintanillareese.com](https://www.quintanillareese.com)

Not affiliated with or endorsed by Salesforce, Inc. Salesforce is a trademark of Salesforce, Inc.
