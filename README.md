# Bullseye

An on-device campus directory and volunteer-authored indoor guide for USF Tampa. Built with SwiftUI, ARKit, RealityKit, Apple Speech, AVSpeechSynthesizer and MapKit. No third-party iOS dependencies, hosted database, account, Apple API key or LiDAR entitlement is needed.

## Run on the team iPhone

1. Open **bullseye.xcodeproj** in Xcode. This repository uses the Xcode 27 project format (`project.xcproj`); use the Xcode version that created this workspace or newer. The app deployment target is iOS 18.
2. Select the **bullseye** scheme. In Signing & Capabilities, use your Personal Team and **Automatically manage signing**. Existing bundle ID `com.yousefibrahimpersonalteam.bullseye` and team `8997D8V95T` were preserved. Keep that identity for updates to the team's saved installation.
3. Connect the iPhone by cable, unlock it, and choose Trust on both devices if prompted. Enable Settings → Privacy & Security → Developer Mode if requested, then restart and confirm.
4. Select the connected iPhone in the run destination picker and press **Cmd+R**. Accept the developer-app trust prompt in Settings if iOS requests it.
5. Camera permission is requested when starting a capture or automatic tracking. Microphone and Speech permissions are requested only for voice search. Typed search and manual waypoint authoring remain available after denial.

**Do not delete the app to update it.** Cmd+R with the same bundle ID retains its Documents directory. Before reinstalling, changing bundle identity, resetting the device, or replacing a map, export verified maps to Files and keep a second copy on the Mac.

## First real ENB route

The installed app starts with **no invented ENB room or route**. The separately labeled practice guide is reachable from Map a building and never enters campus search. No ENB PDF is used. The team must supply room signs, landmarks and verification on site.

1. Home → **Map a building** → **New building draft**. Enter Engineering II, ENB, and the observed floor label. Reopen the draft.
2. Stand at a recognizable public start. Read the capture checklist. Choose **Capture or add waypoints** → **Start camera capture**. Slowly look around in good lighting.
3. Confirm the status reads **LiDAR active** on supported hardware. Mesh patches appear as live capture feedback. On unsupported LiDAR hardware, AR camera tracking still works; manual authoring works without AR. Live mesh feedback and a saved ARWorldMap are different things.
4. Enter the start's public landmark name and facing direction. Mark it at the position where a person can actually stand or stop. The first point is offered as a named start and requires a facing direction.
5. Walk the actual public route. Mark each turn, junction, corridor stop, ramp, stair or elevator landing. Stop and wait for stable tracking before each capture. Use the point picker and **Recapture selected point** to correct a position within the same capture.
6. At a door, capture a usable hallway stopping point. Select that point, type the room number from its real sign and an optional label, then **Add room**. Repeat for additional doors on the same scan. Do not substitute the doorway's visual center for a usable stopping point.
7. **Save capture & review** obtains the ARWorldMap and atomically saves the draft. Mapping must be extending or mapped and tracking must be stable. On failure, stay in capture, scan more of the surroundings and retry. AR points remain in memory until the world map is saved; finish this step before force-quitting.
8. In Review, add each **directed connection** between the actual consecutive stops you walked. Set corridor/door/ramp/stairs/elevator, choose a direction symbol, and write a landmark instruction. Check observed/verified only after checking the complete connection. Check step-free only when that full connection is verified step-free. Add a separate reverse connection with its own instruction if needed; adjacency is never inferred.
9. Tap waypoints to correct names/facing or delete them. Deleting a point removes dependent room labels and connections and returns the map to draft. Room labels and aliases can be corrected separately. Close a blocked connection immediately using its Closed toggle, or unpublish the whole map.
10. **Publish reviewed map**. Tap a room's **Test route**, choose the correct start, keep Step-free selected, inspect the schematic and launch guidance. Newly published rooms immediately appear in Home search without recompiling.
11. Export, unplug, quit/relaunch, search the exact real room and repeat the route. Record a passing manual-guidance take before relying on automatic recognition.

Opening capture on an already published map returns it to draft. Republish after reviewing additions. A published room may have no verified route; the app preserves Step-free and explains why rather than generating directions.

### Second floor and elevator

Save the first floor before leaving it. Add a **separate floor / capture zone**, then capture the other floor independently. Name the elevator landings distinctly and record facing directions. Never reuse coordinates from one capture in another. Author an explicit elevator connection from one landing to the other and its reverse separately if desired. Record the intended floor in each instruction, verify operation at capture time, and enable step-free only after observation. The team's report that the elevator works does not automatically mark graph links verified.

Guidance pauses at an elevator transfer. Confirm the displayed floor **after exiting**. Automatic mode then loads that floor's saved map and waits for relocalization. Manual guidance remains usable throughout.

### Student guidance

Search by building name/code, room number or comma-separated aliases. A number shared across buildings returns a choice. Exact numbered queries remain local. Dictated text is editable; tap Search after speaking. Only one push-to-talk recording runs at a time, with a 20-second limit.

Choose a named start. Step-free excludes closed links, unverified links, stairs and links not explicitly verified step-free. All route modes exclude unverified/closed connections. Routing uses directed shortest-path costs from captured horizontal distances where available; manual segments use equal costs. The graphic is a labeled ordered-stop schematic, not an ENB floor plan or GPS view.

Each instruction is displayed and narrated. Repeat, Next step, End route confirmation and arrival confirmation are available. VoiceOver uses accessibility announcements instead of simultaneous synthesized narration. Backgrounding pauses automatic tracking and narration; return to the current instruction and continue manually or recover at a landmark.

Automatic mode restores the active zone's ARWorldMap, waits for stable tracking, and considers only the next expected waypoint. It uses sustained horizontal proximity and consistency with the authored segment. It pauses for tracking loss and latches a deviation until recovery. It cannot detect walls, obstacles or current clearance; volunteers must mark every turn and validate the actual route. No timer advances a route. Automatic arrival still requires confirmation.

### Packages and suggestions

Map a building → **Export all** saves a version-1 JSON package through Files. It includes stable map/zone/waypoint/room/link IDs, draft/published status, verification dates, pending suggestions, and base64-encoded ARWorldMaps. It excludes raw video and microphone audio. Share the saved file using Files → Share → AirDrop.

On the receiving phone, save the AirDrop file to Files; open Bullseye → Map a building → **Import**. The app checks schema version, duplicate IDs, graph/floor references and AR archives before one atomic write. Existing-ID conflicts reject the entire import without replacement. This first version does not merge competing edits; keep the authoritative device's map or import into an installation without the conflicting map. Keep a backup before any reinstall. Packages over 100 MB are rejected.

Home → **Suggest a location** saves a pending building/floor/number/label/public-landmark note. Suggestions travel in the same exported package. Volunteer maps → Location suggestions supports reject or accept-and-link to a verified waypoint. Acceptance returns the target map to draft; publication remains a separate review action.

Local persistence is `Documents/bullseye-v1.json`. A read failure is visible and blocks overwriting the original. Preserve the file for recovery. No existing maps or data formats were present in the starter project.

## Campus services and Maps

The bundled directory was checked against these exact official pages on 2026-11-21:

- [USF Career Services: Suit-A-Bull](https://careers.usf.edu/resources/suit-a-bull/) — professional clothing to keep, SVC 2060.
- [USF Student Health Services: Feed-A-Bull](https://www.usf.edu/student-affairs/student-health-services/services/feed-a-bull-food-pantry.aspx) — student food assistance, Tampa SVC 0002, ground floor.
- [USF Registrar: Contact / Directions to SVC Building](https://www.usf.edu/registrar/faq/contact_us.aspx) — its directions link identifies destination 28.0625264, -82.4124365, 12220 Leroy Collins Blvd. Bullseye accepts a MapKit Student Services building search result only within 120 m of this official destination. Multiple candidates require a choice; no candidate leaves the directory result intact.

Ask “Where can I rent a suit?” or type SVC2060. Bullseye shows the local official facts and source. **Open walking directions** hands off to the building, not room 2060. SVC indoor coverage is explicitly unavailable. Maps walking routes are not represented as verified step-free. The final Apple Maps item/arrival must still be checked on the real iPhone before filming.

## Optional live service matching proxy

Python 3.10+; standard library only. API use is optional and requires separate OpenAI API billing. Create a host-only key at [OpenAI API keys](https://platform.openai.com/api-keys). Never put it in the app, Xcode build settings, tracked files, a screenshot or logs.

From the repository root:

```sh
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r proxy/requirements.txt
read -s 'OPENAI_API_KEY?OpenAI API key: '
export OPENAI_API_KEY
export OPENAI_MODEL=gpt-4.1-mini
export BULLSEYE_HOST=0.0.0.0
export BULLSEYE_PORT=8787
python proxy/server.py
```

The `read` command above is for macOS's default zsh and does not echo the key. `proxy/.env.example` documents nonsecret configuration; the server reads environment variables, not an automatically loaded .env file. To run without AI, omit the key and the server returns local fallback.

In a second terminal:

```sh
curl --silent --show-error http://127.0.0.1:8787/health
curl --silent --show-error http://127.0.0.1:8787/search \
  -H 'Content-Type: application/json' \
  --data '{"query":"Where can I rent a suit?"}'
```

Health returns `status: ok` and whether a key is configured; it does not claim successful API authentication. A successful real API match returns `live: true`. A no-key, timeout, malformed/refused response or API failure uses local fallback with `live: false`.

In a **Debug** app build, scroll Home → **Debug settings**. Set `http://Your-Mac.local:8787` using the Mac's actual local hostname, then tap **Check proxy health** on the physical iPhone. The Mac and phone must be on the same trusted network. `localhost` on iPhone means the iPhone, not the Mac. Allow the Mac firewall connection and iOS Local Network permission. Campus Wi-Fi may isolate clients; use a trusted hotspot/shared network if health fails. Hosted proxy access must use HTTPS.

Only query text and the two public service records go to the proxy/API. The model has no tools, map data, camera access or device data. Responses API Structured Outputs limits it to an allowed service ID, clarification or no match, and the app validates again before displaying local facts. Queries are limited to 300 characters, bodies to 2 KB, output tokens to 150, concurrency to two and requests to 30/minute. Request/exception logging is disabled. The demo server is intended for a trusted team network; put authentication and TLS in front of any public deployment.

The app falls back after an 8-second request timeout. Debug diagnostics distinguish validated live AI from local fallback without logging query text. Release builds use the local directory. `Info-Debug.plist` permits local networking only; `Info-Release.plist` has no ATS exception. No arbitrary-load exception is enabled.

Implementation references: [Responses Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs?api-mode=responses), [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini).

## Checks and evidence

Build with Xcode's bullseye scheme. Pure model checks use the same `Models.swift` through a small Swift package and the **Testing** framework:

```sh
swift test
python3 -m unittest discover -s proxy -v
```

In a restricted workspace where the normal module cache is unavailable, the exact successful model-check command was:

```sh
env CLANG_MODULE_CACHE_PATH=/tmp/bullseye-swift-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/tmp/bullseye-swift-cache \
  swift test --scratch-path /tmp/bullseye-model-build \
  --cache-path /tmp/bullseye-package-cache --disable-sandbox
```

The Mac model checks cover graph routing and package metadata; they do not establish ARWorldMap relocalization or iOS device behavior. AR archive validation runs in the iOS app. See [VERIFICATION.md](VERIFICATION.md) for actual checks and remaining physical work, and [FILMING.md](FILMING.md) for the two demo takes.

`screenshots/` contains actual simulator/preview captures, not mockups. `#Preview` definitions cover Home, dark/large Home, practice room, practice guidance, Suit-A-Bull and capture controls. Preview practice data is isolated from the published catalog.

The original bullseye icon is generated with Core Graphics by `Tools/generate-icon.swift`. Its 1024 px asset is in AppIcon.appiconset. Bundled size variants are also configured through CFBundleIcons because this Xcode tool bridge rejected the asset-compiler app-icon setting. Regenerate with:

```sh
swift -module-cache-path /tmp/bullseye-swift-cache Tools/generate-icon.swift \
  bullseye/Assets.xcassets/AppIcon.appiconset
```
