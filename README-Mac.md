# HQR Metadata Mover for Mac

Free Salesforce deployment tool from House of Quintanilla-Reese LLC. This is the Mac (and Linux) edition;
it works the same as the Windows app. Everything runs on your Mac with your own Salesforce CLI logins.
No account, no tracking, nothing leaves your computer except calls to the orgs you connect.

## Install

1. Install the Salesforce CLI: https://developer.salesforce.com/tools/salesforcecli
2. Install Node.js 18 or newer (LTS is fine): https://nodejs.org
3. Unzip this download.
4. Right-click **Start-MetadataMover.command**, choose **Open**, then **Open** again. macOS asks this once
   for apps that are not from the App Store. Next time, double-click it.

It opens in its own Chrome or Edge window (or your default browser if neither is installed).
Closing the window stops it after 10 minutes; closing the Terminal window stops it right away.

If macOS says the file "can't be opened", run this once in Terminal from the unzipped folder:

    xattr -dr com.apple.quarantine . && chmod +x Start-MetadataMover.command

## Using it

Same steps as the Windows version: Orgs, Find Changes, Package, Validate & Deploy, Rollback, Package History.
See the Windows README for the full walkthrough, including the Experience Cloud notes.

## Your files

Packages, rollback points, deploy history and templates are saved in `~/Documents/HQR Metadata Mover`.
They are copies of your orgs' metadata, so keep them as private as the orgs themselves.

## License

MIT. Not affiliated with or endorsed by Salesforce, Inc. Provided as is. Validate before you deploy to production.
Copyright (c) 2026 House of Quintanilla-Reese LLC
