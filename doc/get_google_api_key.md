# Getting a Google Maps Embed API key (Street View pane, #49)

Without a key, the Street View pane shows the Google Maps web app (with its large info box over the panorama).
With a key, it shows the Maps Embed API (small address chip only). About 5 minutes, needs a Google account.

1. **Project** — go to https://console.cloud.google.com/, sign in, and create a new project from the project picker
   at the top (e.g. "BikePlanner").
2. **Billing** — Google Maps Platform requires a billing account (credit card) on the project, even for free APIs.
   The Maps Embed API is free and unlimited, so nothing should be charged.
3. **Enable the API** — *APIs & Services ▸ Library*, search **Maps Embed API**, click **Enable**.
4. **Create the key** — *APIs & Services ▸ Credentials ▸ Create credentials ▸ API key*, copy it.
5. **Restrict the key** (click on it to edit):
   - *Application restrictions*: **Websites**, add `https://bikeplanner.invalid/*` (the base URL of the local page
     that holds the iframe, see `StreetViewController.m`; a reserved domain, nothing is loaded from it);
   - *API restrictions*: **Restrict key**, tick only **Maps Embed API**;
   - Save. Changes can take up to 5 minutes to apply.
6. **Put it in `BikePlanner/Secret.h`** (git-ignored; never commit or log the key):
   ```c
   #define GOOGLE_MAPS_API_KEY "AIza…"
   ```
   Rebuild, quit the running app (⌘Q) and relaunch it.

Troubleshooting: if the pane shows a Google error such as `RefererNotAllowedMapError`, or the console does not accept
the `.invalid` referrer, set *Application restrictions* to **None** temporarily to check that the key works, then
change the base URL (`kEmbedPageBaseURL` in `StreetViewController.m`) and the restriction together.
