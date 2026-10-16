# Vehicle playback and mirroring — 2026-10-16

The reported connection is **wired CarPlay**. The six supplied images are visual references; they are not evidence of Mirivo's current output.

## Changes

- The shared VLC surface follows the active phone/external host. Capture protection is enabled on the phone and disabled on the authorized external video surface. AVPlayer no longer competes for a screen already owned by the app.
- External video has a channel/episode drawer, favorites, transport, timeline, and independent fit/stretch controls. Phone controls include “Play on phone”; moving an app-owned surface preserves the decoder and pause state.
- Favorites persist in Keychain, including the source identity. Deleting a source or changing its credentials removes the corresponding saved URLs; renaming a source preserves favorites.
- The connection sheet exposes the native AirPlay picker and Cast discovery directly, with an always-visible entry point. The compact player uses artwork, a progress line, and separate play/stop controls.
- Local screen playback uses independent 0.5-second MP4 fragments over token-protected loopback instead of waiting for an HLS playlist and AVPlayer buffers. Cast/AirPlay receivers retain HLS. Encoding preserves the captured screen aspect ratio; fitting belongs to the destination window. The default quality is High; explicit saved quality choices remain respected.
- Rotation and encoder stalls replace the codec timeline and initialization URL. Local readers rejoin the latest fragment; outstanding writes and retained media remain bounded.

## Evidence and limits

Core/media tests cover rotation, output dimensions, fragment ordering, delayed codec initialization, and token rejection. iOS tests exercise actual decoded VLC output, capture protection on both hosts, native output ownership, favorite persistence, phone handoff, the connection sheet at normal/large text sizes, and compact player controls.

Validated with Xcode 27.1 and an iOS 26.5 simulator. Core: 69 tests, one pre-existing skip, no failures. Media: 9 tests, no failures. The final live-transport run produced its first frame in **0.386 seconds**, continued for **20 seconds**, and measured **1.343 seconds** from the fixture's encoded pixel clock to the displayed frame. These are local simulator transport measurements, excluding the car/head-unit link.

The final iOS run (`build/vehicle-playback-tests-6.xcresult`) passed all 8 selected app tests and 3 UI tests. Across these suites: **88 passed, 1 skipped, 0 failed**. Release localization validation passed for 468 keys in 22 languages, and both staged/unstaged whitespace checks passed. No physical-device install or vehicle test was performed in this task.

The live fixture measures latency from a clock encoded into image pixels, read back from the paused decoder surface. VLC's playback time starts at the first received fragment and cannot be subtracted from the broadcast start time. A previous attempt that used that subtraction produced an invalid latency result and was replaced.

Screenshots and result bundles from this run are under `build/vehicle-preview/` and `build/vehicle-playback-tests-*.xcresult`. The temporary wide window used for layout capture is a simulated display, not an actual vehicle.

Physical wired-CarPlay rendering, long-session stability, end-to-end vehicle latency, real IPTV providers, and Cast/AirPlay receiver behavior still require device verification. System-managed CarPlay presentations retain system controls; custom controls are hosted only in a video window supplied by iOS.

## Series favorites and media options

Series poster cards and the standalone heart on the series detail page toggle the whole series. The detail heart sits in the empty space to the right of the centered poster, aligned with the page's trailing content margin. It does not cover the artwork; Play and Content Details retain their original two-button layout. In the player, Continue Watching, downloads, and external playback, an episode's heart is selected only when that episode is saved. Saving its series does not fill the episode's heart. For episodic content, tapping that heart opens a native menu with separate series and episode add/remove actions; it never silently converts one kind of favorite into the other. Episode rows have no added favorite control. Series identity includes the source and catalog group; opening a saved series resolves the current catalog so later seasons are included. Older saved episode favorites retain their identity.

Favorites use a mixed three-column poster grid for series, movies, episodes, and channels, with distinct series/episode badges. Series open their season list; playable items open the player. At accessibility text sizes the grid becomes a single column with artwork beside the title. A favorite card removes only that exact saved item. Removing an episode does not remove the separately saved series. The external-screen drawer also opens series favorites into an episode list.

Audio/subtitle options remain available in the phone player and remote playback panel even when no alternate tracks are available. Single audio tracks remain visible, and empty audio/subtitle sections explain that the stream has no selectable tracks. The decorative series backdrop is excluded from accessibility so its oversized image cannot cover episode controls.

Final verification used a separate iOS 26.5 simulator to avoid concurrent app installs from another task. All **4 app tests and 6 UI scenarios** passed in their final runs: `build/series-favorites-tests-isolated.xcresult` plus `build/series-favorites-large-final.xcresult`. The latter reruns the accessibility scenario with a carousel gesture above the floating playback bar. Coverage includes legacy favorites, source isolation, new seasons, series versus episode identity, persistence across launch, removal, poster-card/header/continuation hearts, episode playback, and audio/subtitle panels with and without tracks. Localization validation passed with 472 keys in 22 languages; staged and unstaged whitespace checks passed. Screenshots and the per-test result summary are in `build/favorites-preview/`.

The earlier favorite-scope regression run (`build/favorite-scope-regression.xcresult`) passed **4 app tests and 4 UI tests**. It covered the former inherited-heart behavior, a separately saved episode lighting its Continue Watching card, both selections surviving relaunch, independent removal, source isolation, legacy records, and accessibility text sizes. The inherited-heart behavior was superseded by the October 17 correction: series and episode hearts now reflect their own saved state. The native scope menu and episode badges were also checked in simulator screenshots under `build/favorite-scope-preview/`. Localization validation passed with 481 keys across 22 languages. These results are from the simulator; this regression fix was not installed on a physical device.

The October 17 episode-heart correction passed **1 app test and 4 UI tests** in `build/episode-favorite-isolation.xcresult`. Coverage includes a saved series leaving episode hearts empty, explicitly saved episodes showing filled hearts, removing an episode while retaining its series, persistence across relaunch, independent series card/header state, the full Continue Watching list, and accessibility text sizes. The shared button applies the same episode-only rule to phone and external playback, Continue Watching, and downloads. Screenshots and the result summary are under `build/episode-favorite-preview/`. Localization validation passed for 481 keys in 22 languages; staged and unstaged whitespace checks passed. This correction was tested in the simulator and was not installed on a physical device.

The detail-poster placement passed **3 UI scenarios** in their final runs: favorite toggling and persistence, single-season details/playback, and season playback with accessibility text sizes. Evidence is split between `build/series-favorite-placement.xcresult` and `build/series-favorite-placement-large-final.xcresult`. The large-text test first confused the poster title with an episode row; its selector now targets the episode control. Its first retry encountered a simulator keyboard-focus failure, and the final retry passed. Normal and large-text screenshots plus the full run history are in `build/series-favorite-placement-preview/`. Localization and whitespace checks passed; no physical-device install was performed.

The poster-overlay placement was subsequently replaced after visual review. The heart now occupies the empty area beside the poster, aligned to the page's right content margin, with its own circular material surface. The existing series/episode favorite UI regression passed in `build/series-favorite-spacing.xcresult`; the final screen was visually checked in `build/series-favorite-spacing-preview/mirivo-favorites-series-header.png`.

## Favorite entry points

Movie, live-channel, and radio rows now expose the shared favorite button in catalog and search results. The live player channel switcher keeps its favorite button independent of channel selection and uses the playing source's identity. Continue Watching's full list uses the same episode/series menu and state as its carousel. Series episode rows and the mini player remain unchanged.

Downloads resolve their original remote channel by the download's asset hash within the original source catalog, including the encrypted catalog cache after relaunch. The list favorites that source item; deleting a downloaded file does not remove its favorite. Downloads whose original source or channel is no longer available cannot be mapped to a valid remote favorite. No provider URL is added to the plaintext download manifest.

The CarPlay root menu now links to a mixed Favorites list. Series navigate to their current episodes, while individual items retain their source and playback configuration. The menu handles empty state and pagination and refreshes when favorites change on the phone. CarPlay template tests exercise item types, callbacks, source identity, page navigation, and deletion while viewing a later page; physical head-unit validation remains separate.

Final verification on the isolated iOS 26.5 simulator passed **3 app tests and 6 UI scenarios**. The final evidence is split across `build/favorite-placements.xcresult` (CarPlay templates, offline identity, downloaded-item persistence/removal, live switcher at both text sizes), `build/favorite-placements-final-2.xcresult` (catalog/search/movie/live/radio favorites and relaunch), and `build/favorite-placements-menu.xcresult` (full Continue Watching list at both text sizes). Earlier UI attempts exposed test interactions with an offscreen lazy category and XCTest's automatic menu hit point; the final tests scroll the full category into view and tap the visible menu row center. Continue Watching's large-text layout also moves the actions beside its artwork so the title retains the full row width. Screenshots and per-test run history are under `build/favorite-placements-preview/`. Localization validation passed for 481 keys in 22 languages, and staged/unstaged whitespace checks passed. No physical-device install or vehicle test was performed for these additions.

## Reproduce the live transport test

From the repository root, compile the fixture with production encoder/server sources:

```sh
mkdir -p build
swiftc -O -parse-as-library -o build/vehicle-stream-probe \
  Sources/Core/HLSBuffer.swift Sources/Core/StreamHTTPRouter.swift \
  Sources/Core/ProductPolicy.swift Sources/Core/AudioTimeline.swift \
  Sources/Media/ScreenStreamEncoder.swift Sources/Media/PCMUtilities.swift \
  Sources/Media/CaptionRenderer.swift Sources/Media/LocalStreamServer.swift \
  scripts/vehicle_screen_fixture.swift
build/vehicle-stream-probe
```

The process writes its loopback endpoint and clock origin to `build/vehicle-stream-probe.json`. Keep it running while testing and terminate it afterwards. In another terminal, set `VEHICLE_SIMULATOR_ID` to the test simulator UUID and run:

```sh
python3 - <<'PY'
import json, os, subprocess
with open('build/vehicle-stream-probe.json') as file:
    fixture = json.load(file)
env = os.environ.copy()
env['TEST_RUNNER_MIRIVO_TEST_STREAM_URL'] = fixture['url']
env['TEST_RUNNER_MIRIVO_TEST_STREAM_STARTED'] = str(fixture['started'])
raise SystemExit(subprocess.call([
    'node', 'scripts/test_app.mjs', os.environ['VEHICLE_SIMULATOR_ID'],
    '--only-testing=MirivoTests/VehiclePlaybackTests/testLiveFragmentStreamDecodesAtTheExternalSurface',
    '--keep-cache'
], env=env))
PY
```

`VehiclePlaybackTests.testVehicleAndPhoneLayouts` and the phone-handoff UI test also need a local HTTP video fixture on port 18779; the layout fixture expects a seekable 90-second MP4. The live-transport test is independent of that server. Run `swift test --jobs 2` for the portable Core/Media checks.
