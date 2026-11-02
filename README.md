# Metadata Mover (v0.1)

A small local tool for moving Salesforce metadata between orgs: find what changed, build a package, validate, deploy.
It runs on your machine. The engine is the free Salesforce CLI (`sf`), and nothing is sent anywhere except your own orgs.

## Trying it out

This is an early version shared for feedback, not a supported product.

- **Windows only** (Windows PowerShell 5.1, which every Windows 10/11 machine has).
- If Windows warns about a downloaded file: right-click the zip › Properties › **Unblock**, then extract it.
- Try it on dev orgs and sandboxes first. Always **Validate** before you **Deploy** to a production org.
- Backups and rollback restore metadata, not data.
- **Feedback:** when something goes wrong, send the Activity Log text (bottom of the page), the console window's output,
  and your sf version (top of the page), plus what you clicked. Ideas and annoyances are just as useful.

## One-time setup

1. Install the Salesforce CLI: https://developer.salesforce.com/tools/salesforcecli (the Windows installer).
2. For Aura-based Experience sites, in **both** orgs turn on: Setup › Digital Experiences › Settings ›
   **Enable ExperienceBundle Metadata API**. (LWR sites use `DigitalExperienceBundle` and don't need this.)

## Run it

Double-click `Start-MetadataMover.cmd`. A console window opens (leave it running) and your browser opens
`http://localhost:8765/`. Close it with the **Stop Server** button or Ctrl+C in the console.

## The workflow

1. **Orgs.** Pick source and target. Use **Connect an Org…** to log in to a new one (opens the Salesforce login page; this is `sf org login web`).
   Each org shows whether it's a sandbox, Developer Edition or **PRODUCTION**. **Rename** next to an org in Connected Orgs
   changes its alias (the nickname in the Salesforce CLI). Package History keeps working because it tracks orgs by username.
2. **Find changes.** Click **Scan Orgs**. It lists every component of the chosen types in the source (and target, to compare).
   Then filter: changed since a date, modified by (defaults to you), new vs. existing in target, search.
   - **Target newer ⚠** means someone changed it in the target after your source change. Deploying overwrites that.
   - **Experience Sites** buttons add a whole site in one click: Network, NetworkBranding, CustomSite, ExperienceBundle or
     DigitalExperienceBundle + DigitalExperienceConfig, navigation menus, and an LWR site's `…_sf_default_cdn_…` static resource
     (scan StaticResource too to get it). Check the list; matching is by name. Add the site's flows, profiles and other pieces yourself.
   - Anything the scan can't find, add by hand in step 3 as `Type: Name`.
3. **Package.** Review the selection and click **Build Package from Source**. This retrieves the components into
   `packages/<name>/` (the `package.xml`, the retrieved zip, and an unzipped `contents/` folder you can look through).
   Retrieve warnings list anything that couldn't be found.
4. **Validate & deploy.**
   - **Validate** runs a check-only deploy. With *No tests* it's a dry run; with any test level it's a real validation.
   - **Quick Deploy** is enabled after a validation that ran tests passes (Salesforce keeps it for 10 days).
   - **Deploy** does a full deploy. Production deploys ask you to type `DEPLOY`.
   - Component errors, test failures and coverage warnings are listed as they come in, with a link to Deployment Status in Setup.

**Rollback.** With **Back Up Target First** ticked (the default), Deploy and Quick deploy first retrieve the target's
current versions of the package's components into `packages/<name>/backups/<target-time>/`. That's the rollback point.
**Roll Back…** (shown after the deploy, and under Package History) then:
- puts every component that already existed back the way it was, and
- deletes the components that deploy added (new objects, fields, classes…). Deleting fields or objects also deletes their data.

Notes: a failed deploy changes nothing (Salesforce undoes it), so there's nothing to roll back. Rollback restores
metadata, not data. Changes made in the target to the same components after the deploy are overwritten.
Some things can't be deleted through the Metadata API (an Experience site's Network, for example). If a delete fails,
the rollback reports it and nothing is changed, so remove that item by hand in Setup and roll back again.
Production rollbacks ask you to type `ROLLBACK`.

**Steps open one at a time.** Picking the target (or **Continue**) moves you on, and the finished step shrinks to a one-line summary. Click any collapsed step to open it again.

**Package History** keeps every package you built and the result of each deploy, so you can redeploy the same package
to the next org (e.g. INT, then UAT, then prod) or copy it back into the selection to change it. **Archive** hides a package you won't reuse (**Archive Failed** does that for every package whose deploys all failed; **Show Archived** brings them back). **Delete** removes the package folder and its rollback points for good.
Pick the next target in step 1, click **Use for Deploy** on the package, then Validate and Deploy.

**Templates** (top of step 2) save the metadata types and filters you use for a kind of change, and optionally a list of
components. Apply one to start a scan the same way next time. They're stored in `templates.json`.

**When you're done:** click **Stop Server** (or close the console window), then close the browser tab.
Packages, history and templates stay on disk.

## Notes and limits

- **Deleting components isn't part of a normal deploy.** Deploys only add and update. The only deletes are a rollback
  removing what its own deploy added.
- **Profiles** only include the permissions for other components in the same package.
  Permission sets are usually the better thing to move.
- **Experience sites:** deploy the site's Network, CustomSite and bundle together. If the site doesn't exist in the target yet
  and the deploy fails, create it in the target with the same name and URL first, then deploy again.
  Leave `SiteDotCom` out when you deploy ExperienceBundle.
  A CustomSite names a site admin and guest record owner by username, and sandbox usernames differ per org. If either user
  doesn't exist in the target, Validate and Deploy look for the same user under the target's naming (`…cfbint` → `…cfbuat`,
  or no suffix in production). Only if there's no such user do they use your connected user. Every change is noted in the
  Activity Log, so check it after validating against production.
- **"Changed since" uses each component's Last Modified date** from the Metadata API. A few types don't update it reliably,
  so untick **Changed Since** under Filter Results to browse everything if something seems missing.
- The local server only answers on `localhost` and needs a per-session key that's built into the page, so other websites can't use it.

## Files

- `server.ps1`: the local server (PowerShell 5.1+, no other installs). Wraps `sf` and the Metadata API's `listMetadata`.
- `index.html`: the UI.
- `packages/`: one folder per package you build.
- `.sf-workspace/`: an empty Salesforce project the CLI runs from. Leave it there.
