# MowBite Updater

Keeps the apps on your OpenMower up to date: **OpenMower**, **MowBite**, the **MowBite Planner** and any other
app you add.

It only updates while the mower is **idle in its dock**. If a new version doesn't work, it **goes back to the old one**
by itself.

## What it does

- Shows each app's version and whether a new one is out. It looks every 6 hours, "Check for updates" looks right away.
- Updates an app right away when you tap "Update", with the newest version even if the page doesn't show it yet. Or by
  itself at night, if you switch that on. Out of the box, nothing updates by itself.
- Only while the mower is idle in the dock: at night it tries again every 10 minutes, a tap while the mower is out
  isn't done and its card says so. It stops if the mower drives off.
- Checks that the new version really works. If not, it goes back to the old version.
- Checks there's enough free space first and cleans up old versions afterwards.
- Shows what it does from the moment you tap: a progress bar while it gets ready, downloads and restarts an app, and
  while it checks for updates.
- Keeps itself up to date too: "Update" on its own card, or at night after the automatic updates, also when the mower
  isn't in the dock (its own update doesn't touch the mower). If its new version doesn't come up, the one before starts
  again.

## Install

**With MowBite:** nothing to do, it's part of MowBite's `compose.yaml`.

**Without MowBite**, in Dockge on the mower (OpenMowerOS has it on port 5001):

1. Tap "+ Compose" and name the stack `mowbite-updater`.
2. Paste the content of [compose.yaml](compose.yaml).
3. Tap "Deploy".

Then open `http://<your-mower>:8083`.

A stack of its own and the updater in MowBite's `compose.yaml` can't run at the same time, both are named
`mowbite-updater`. Installing MowBite later: remove this stack first, or leave the `updater:` block out of MowBite's
`compose.yaml`. (Its settings are in this stack's `.updater` folder, the one in MowBite's stack starts with its own.)

<details>
<summary>Or in a terminal on the mower</summary>

```bash
mkdir -p /opt/stacks/mowbite-updater && cd /opt/stacks/mowbite-updater
curl -O https://raw.githubusercontent.com/mkaaaaaay/mowbite-updater/main/compose.yaml
docker compose up -d
```

</details>

## Use it

On its page `http://<your-mower>:8083`, or in MowBite under Settings, Updates:

- **Update** updates that app now.
- **Automatically at night** lets it update that app by itself, at the time and on the days you pick.
- **Back to the version before** if something is wrong after an update (MowBite and other apps, and OpenMower as long
  as its registry still has the version before).
- **Make room** shows old versions and leftovers you can delete. After each update it clears leftovers without a name,
  the unused build cache and older versions beyond the ones it keeps by itself.
- **MowBite Updater** has a card of its own: "Update" there updates the updater itself.

Its page looks like MowBite, in the design picked in MowBite when you open it from there. MowBite shows this page under
Settings, Updates, so whatever a newer updater can do shows up there without a new MowBite.

An app it knows but can't reach (its stack in another folder, or not started from a compose file) is listed with the line
that gives it the folder.

## Add another app

On its page (or in MowBite): **Add an app**, pick it from the list of your stacks' apps and tap "Add". "Take out" on its
card removes it again.

Or give the app these lines in its compose file (under its service) and deploy it again:

```yaml
    labels:
      mowbite.update: "on"
```

It then shows up on the updater's page. Optional labels:

| Label | What it does |
| --- | --- |
| `mowbite.update.name: My app` | the name shown |
| `mowbite.update.check: ":8080/health"` | the address that answers when the app works (on the app, or a full url) |
| `mowbite.update.log: "Server started"` | or: a line that shows up in its log when it works |
| `mowbite.update.gate: none` | may update while the mower is out mowing |
| `mowbite.update.stable: github:owner/repo` | offers "stable": the newest release of that repo, as a tag of the same image named like the release without a leading v (release v1.2.3: `:1.2.3`) |

Without a check it waits for Docker's own health check, or else half a minute without a crash.

## Good to know

- **OpenMower:** it switches between edge, release (`latest`) and the version in its `.env` and updates only the
  OpenMower container. The MowBite Planner needs edge for now, the page warns you.
- **OpenMower and its firmware:** a new OpenMower that keeps the motors off because the firmware is too old goes back
  to the version before by itself, its card says so. Run `openmower update-firmware`, then tap "Try again". Before an
  update to another version line (1.3 to 1.4) the card warns you.
- **OpenMowerOS 3:** there OpenMower updates with the system (`openmower update-os`). The updater leaves OpenMower alone
  and keeps the other apps up to date.
- **Apps built from GitHub** (like the MowBite Planner): built again when GitHub has something new. A build that
  changes nothing doesn't restart the app.
- **Your stacks folder:** it works on the stacks in `/opt/stacks` (Dockge's folder). If yours are somewhere else, change
  both sides of that line in `compose.yaml`.
- **Docker access:** like Dockge it needs `/var/run/docker.sock`. It changes your stacks only through their compose
  files, so Dockge shows the same.
- **Settings and log** stay in its own stack folder (`.updater`).
- **Stopped halfway** (power gone): at its next start it puts things back or finishes checking. Only if the power goes
  in the few seconds it swaps itself for its new version, it may not come back: then tap "Update" on its stack in Dockge.
- **Tested** before every new version, which only goes out when all tests pass: `test/run.sh` runs it against a
  made-up mower on the machine's own docker (update and back, a version that doesn't start, the mower leaving the dock,
  a stop halfway, a request while it checks, picked apps, stable, OpenMower and the planner built on it, the night, no
  answer from the registry, making room, builds, itself).

<details>
<summary>Settings (environment)</summary>

All optional, in `compose.yaml` under `environment`:

| | |
| --- | --- |
| `PORT` | its page, default `8083` |
| `MQTT_HOST`, `MQTT_PORT` | the mower's MQTT broker, default `127.0.0.1:1883` |
| `MQTT_USER`, `MQTT_PASSWORD`, `MQTT_PREFIX` | if your broker needs them |

</details>

<details>
<summary>For other apps: the interface</summary>

The same one its page and MowBite use, on port 8083. A `POST` needs the header `Content-Type: application/json`
(the body stays plain lines): so a web page some browser has open can't change anything directly, programs and its own
page can. Through MowBite (its `update` script) MowBite's rules apply: its page, the app and pages from your home
network.

- `GET /cgi-bin/updater`: settings, apps, status, what can go and the log as JSON. While it updates, `status.progress`
  says what it does: `<app> <step> <percent or -> <since> [<done> <of>]`, steps `prepare`, `download`, `extract`,
  `build`, `restart`, `wait`, `back`. `requested` is true while a request waits for it, `status.taken`
  (`<since> now:<app> self back:<app> ...`) from when it takes one until its run shows, `status.looking` (`<since>`)
  while it looks for updates
- `POST /cgi-bin/updater?conf` with lines like `openmower edge`, `mowbite stable`, `mowbite_auto 1`, `at 03:00`,
  `days daily` (or `days 1,3,5`, Monday is 1), `picked app1,app2` (or `picked none`). Lines left out stay as they are
- `POST ?now` (all apps, then itself) or `?now=<app>`, `?self` (only itself), `?back=<app>`, `?check`, `?room`,
  `?free=img:<id>`, `?free=cache`, `?free=all`. Its own state is in `status` as `updater_running`, `updater_available`
  and `updater`. What came of an app last is `status.<app>`, from when `status.<app>_at` (unix time), the mower's time
  zone `status.clock` (`+0100`)

</details>

## License

GPL-3.0, see [LICENSE](LICENSE).
