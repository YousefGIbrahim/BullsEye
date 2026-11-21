# Bullseye verification — November 21, 2026

## Build and automated checks

- Xcode `BuildProject` succeeded for the iPhone destination “Yousef’s iPhone (2)” at 14:11, with no reported errors. Simulator builds also passed. Original bundle ID and signing team retained.
- Six Swift Testing tests passed at 13:56 against the app's actual model source: directed shortest paths; stairs, closed and unverified link exclusion; explicit floor transfers; invalid references and missing map rejection; package version/conflict atomicity; local service/dictation matching; disk reopening and protection against overwriting corrupt saved data.
- The macOS model test target does not execute iOS ARWorldMap unarchiving or camera tracking.
- Five Python proxy tests passed. Actual HTTP `/health` and `/search` returned valid responses with `ai_configured: false` and `live: false`. No API key was supplied; live OpenAI matching remains unverified. The test server has been stopped.

## Rendered interface and interactions

Actual iPhone 17 simulator screenshots were captured and reviewed, then used to correct row alignment, placeholder contrast, route diagram width and spacing, and guidance responsiveness:

- [Home](screenshots/home-iphone17.png)
- [Suit-A-Bull result](screenshots/service-iphone17.png)
- [Route preview](screenshots/route-iphone17.png): all three ordered stops and bottom action fit at default size. This is explicitly labeled practice data, not an ENB floor plan.
- [Guidance](screenshots/guidance-iphone17.png)
- [Arrival](screenshots/arrival-iphone17.png)
- [Keyboard visible](screenshots/search-keyboard-iphone17.png): Search and microphone remain reachable. Entering SVC2060 and submitting returns Suit-A-Bull and dismisses the keyboard.
- [Dark Home preview](screenshots/home-dark-preview.png): rendered in Xcode on an iPhone 18 Pro preview destination.

Simulator interactions verified: Start directions, Repeat, manual Next, arrival confirmation, Done, and End route confirmation returning to the preview. An initial main-thread audio-session stall was reproduced and fixed by moving AVAudioSession operations to a separate actor; subsequent guidance interactions remained responsive. Audio audibility and recording quality require a physical check.

Accessibility XXXL Home and keyboard were rendered. They exposed excessive header wrapping and narrow result text. The final code rearranges the masthead and result rows vertically and hides the decorative slogan at accessibility sizes. Those final accessibility corrections compile, but the simulator session ended before their final rendering could be rechecked. Existing `home-accessibility-*.png` screenshots show the earlier audit state, not final acceptance. Full VoiceOver traversal, smaller phone widths, increased-contrast rendering and all-screen dark/large-text acceptance remain unverified.

Calculated palette contrast at default appearances: ink/paper approximately 14:1, muted/paper 5.8:1, white/pine 12.4:1, gold/pine 7.4:1. This calculation is not a substitute for checking camera overlays and actual accessibility settings. No custom motion is required for navigation.

The capture camera is pinned above the scrolling labels while active. Capture controls have an independent preview. Live camera rendering and the final pinned capture layout require the physical device; simulator evidence does not establish AR performance.

## Physical and on-site acceptance still required

No real ENB room or route was supplied or fabricated. The complete real-room checkpoint is pending the team's on-site capture and publication. The app is buildable and ready for that workflow.

Follow [README](README.md) and [FILMING](FILMING.md) to verify:

1. Camera permission, supported world tracking, LiDAR mesh feedback, stable capture and saved world map; denied permissions and non-LiDAR/manual operation.
2. Actual ENB scan → signed room label → explicit observed connections → publish → unplug/relaunch → search → Step-free guide.
3. Real-map relocalization, sustained expected-waypoint detection, tracking loss/deviation recovery, manual continuation and background/resume.
4. Elevator landing links, intended-floor confirmation, exit and separate floor-map relocalization. No coordinates are compared across independent maps.
5. Spoken instructions, repeat/next/arrival, push-to-talk transcript, VoiceOver and larger text.
6. Files/AirDrop export/import with real ARWorldMaps; pending suggestion review, correction and publication; new rooms appearing without recompiling.
7. Apple Maps resolving and opening the correct Tampa Student Services Building pin. The app filters candidates against the official SVC location; actual Maps handoff has not been observed. Indoor SVC routing is unavailable unless volunteers publish it.
8. Reachable Mac proxy URL from the physical iPhone, optional live AI diagnostics, offline fallback and recorded audio quality.

Always export verified captures before deleting/reinstalling. Normal builds with the existing bundle ID preserve the app container; uninstalling does not. The app stores no raw camera video or microphone recordings in map packages.

## Reproduce the designed screens

- Home: launch Bullseye.
- Service: tap Suit-A-Bull or search SVC2060.
- Route and guidance without campus data: Map a building → the explicitly labeled practice guide → Start directions. Practice data never populates the published campus catalog.
- Real room: create and publish an observed map, return Home, search its building code and room number, select a named start, choose Step-free and start.
- Capture: Map a building → create/reopen a draft → select its zone → capture. Allow camera access on device.

Earlier simulator stall artifacts are retained only as diagnostic history (`start-directions-hang.*` and `simulator-runtime.log`); they do not describe the final passing guidance flow.
