# HQR Metadata Mover

**A free Salesforce deployment tool for Windows, from House of Quintanilla-Reese LLC.**
[quintanillareese.com](https://quintanillareese.com)

HQR Metadata Mover moves your Salesforce changes from one org to another: find what you changed, build a
package, validate it, deploy it, and roll it back if you need to. It finds the metadata Change Sets miss,
including everything an Experience Cloud site needs, and it runs on your own PC with your own Salesforce logins.

## What you get

- **Find what changed:** scan both orgs and filter by date, by who changed it, and by whether it's new to the
  target. A warning shows when someone changed the same component in the target after you.
- **Whole Experience Cloud sites in one click:** the Network, branding, CustomSite, the site bundle and config,
  navigation menus and the site's static resource. Aura and LWR sites both work.
- **Validate, Quick Deploy and Deploy,** with errors, test failures and code coverage shown as they come in.
- **Rollback:** before each deploy it saves the target's current versions, so you can put things back,
  including removing the components the deploy added.
- **Reuse packages:** deploy the same package to INT, then UAT, then production, with the results of every deploy
  kept in Package History.
- **Templates** for the kinds of changes you make often.

## Install

1. **Install the Salesforce CLI** if you don't have it:
   [developer.salesforce.com/tools/salesforcecli](https://developer.salesforce.com/tools/salesforcecli) (Windows installer).
2. **Extract the download.** Right-click the zip file, choose **Extract All**, then **Extract**.
3. Open the extracted folder and double-click **Install HQR Metadata Mover**.
4. It opens in its own window when setup finishes. Next time, use the **HQR Metadata Mover** shortcut on your
   desktop or in the Start menu.

No administrator rights are needed. It installs for your Windows account only.

### "Windows protected your PC"?

Windows shows this for new programs from small publishers that aren't code-signed yet.
Click **More info**, then **Run anyway**. HQR Metadata Mover is open source: every file is plain text
you (or your IT department) can read before running it.

### Requirements

- Windows 10 or 11
- The Salesforce CLI (`sf`)
- Google Chrome or Microsoft Edge (Edge comes with Windows) to show it in its own window
- For Aura-based Experience sites only: in **both** orgs, turn on Setup › Digital Experiences › Settings ›
  **Enable ExperienceBundle Metadata API**. LWR sites don't need this.

## Using it

1. **Orgs.** Pick the source (where you made changes) and the target. **Connect an Org…** logs in to a new one through
   the Salesforce login page. Each org is labeled Sandbox, Developer Edition or **PRODUCTION**. **Rename** gives an org a
   friendlier nickname.
2. **Find Changes.** Click **Scan Orgs**, then narrow the list with **Filter Results**. **Target newer ⚠** means someone
   changed that component in the target after your change, and deploying would overwrite it. The **Experience Sites**
   buttons add a whole site. Add the site's flows, profiles and other pieces yourself.
3. **Package.** Check the selection, name the package and click **Build Package from Source**. Anything the scan didn't
   list can be added by hand as `Type: Name`.
4. **Validate & Deploy.**
   - **Validate** checks the deploy without changing anything. With tests, a passed validation enables **Quick Deploy**
     for 10 days.
   - **Deploy** makes the changes. Production deploys ask you to type `DEPLOY`.
   - Always validate against production before deploying there.

Finished steps shrink to a one-line summary. Click one to open it again.

**Package History** lists every package you built and how each deploy went. To move a package to the next org, pick
that org as the target in step 1, click **Use for Deploy** on the package, then Validate and Deploy. **Archive** hides
packages you won't reuse, and **Delete** removes one for good.

**When you're done,** close the window. HQR Metadata Mover stops by itself 10 minutes later, or right away if you click
**Stop Server** first. Deployments you started keep going in Salesforce either way. Clicking the shortcut while it's
running brings its window back to the front.

Links, such as **View in Setup**, open in your usual browser, where you're signed in to Salesforce. Connecting an org
also opens the Salesforce login page there.

### Rollback

With **Back up target first** ticked (the default), every Deploy first saves the target's current versions of the
package's components. **Roll Back…** (after the deploy, and in Package History) then puts back everything that already
existed and removes what the deploy added.

- Rollback restores metadata, not data. Removing a field or object the deploy added also removes its data.
- A failed deploy changes nothing (Salesforce undoes it), so there's nothing to roll back.
- Some things can't be removed through the Metadata API, such as an Experience site's Network. If a removal fails,
  nothing is changed: remove that item by hand in Setup and roll back again.
- Production rollbacks ask you to type `ROLLBACK`.

### Experience Cloud sites

- Deploy the site's Network, CustomSite and bundle together (the site button does this). Leave `SiteDotCom` out.
- If the site doesn't exist in the target yet and the deploy fails, create it there with the same name and URL first,
  then deploy again.
- A site names its site admin and guest record owner by username, and sandbox usernames differ per org. If that user
  isn't in the target, HQR Metadata Mover uses the same person under the target's naming (`…uat` instead of `…int`, or no
  suffix in production), or your own user if there's no match. Each change is listed in the Activity Log, so read it
  after validating against production.

### Good to know

- Deploys only add and update. The only removals are a rollback undoing its own deploy.
- Profiles only carry the permissions for the other components in the same package. Permission sets are usually the
  better thing to move.
- "Changed Since" uses each component's Last Modified date. A few types don't update it reliably, so untick
  **Changed Since** to see everything if something seems missing.

## Your files

Packages, rollback points, deploy history and templates are saved in `Documents\HQR Metadata Mover`. The link at the
bottom of the app opens that folder. These are copies of your orgs' metadata, so keep them as private as the orgs
themselves. If OneDrive backs up your Documents folder, they're backed up too.

## Uninstall

Open **Settings > Apps > Installed apps**, find **HQR Metadata Mover**, and choose **Uninstall**.
Your packages in `Documents\HQR Metadata Mover` and your Salesforce CLI logins are kept. Delete that folder too if you
don't need it.

## Privacy

Everything stays on your PC. HQR Metadata Mover has no accounts, no tracking and no data collection. It only talks to
the Salesforce orgs you connect, through your own Salesforce CLI logins. The app is served by a tiny web server that only
this PC can reach (`localhost`), protected by a key that changes every time it starts, so other websites can't use it.

## Feedback and problems

When something goes wrong, send us what you clicked, the text of the **Activity Log** (bottom of the app), and the file
`Documents\HQR Metadata Mover\server.log`. Ideas and annoyances are just as welcome.

## For the curious

| File | What it is |
| --- | --- |
| `app\server.ps1` | The local server: runs the Salesforce CLI and the Metadata API calls (PowerShell) |
| `app\index.html` | The app page |
| `app\Launch-MetadataMover.cmd` | Starts it (used by the shortcuts) |
| `setup\install.ps1` | The installer |
| `app\uninstall.ps1` | The uninstaller |

Installed files live in `%LOCALAPPDATA%\Programs\HQR Metadata Mover`.

## License

MIT License. Free to use, share and modify; keep the copyright notice. See `LICENSE.txt`.

Not affiliated with or endorsed by Salesforce, Inc. Salesforce is a trademark of Salesforce, Inc.
Provided as is, without warranty of any kind. Validate before you deploy to production.

Copyright (c) 2026 House of Quintanilla-Reese LLC
