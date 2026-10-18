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

Series poster cards and the standalone heart on the series detail page toggle the whole series. The detail heart sits in the empty space to the right of the centered poster, aligned with the page's trailing content margin. It does not cover the artwork; Play and Content Details retain their original two-button layout. In the player, Continue Watching, downloads, and external playback, an episode's heart is selected only when that episode is saved. Saving its series does not fill the episode's heart. Every heart directly adds or removes its displayed item with one tap; there is no series/episode selection menu. Series controls toggle the whole series, while episode controls toggle only that episode. Episode rows have no added favorite control. Series identity includes the source and catalog group; opening a saved series resolves the current catalog so later seasons are included. Older saved episode favorites retain their identity.

Favorites use a mixed three-column poster grid for series, movies, episodes, and channels, with distinct series/episode badges. Series open their season list; playable items open the player. At accessibility text sizes the grid becomes a single column with artwork beside the title. A favorite card removes only that exact saved item. Removing an episode does not remove the separately saved series. The external-screen drawer also opens series favorites into an episode list.

Audio/subtitle options remain available in the phone player and remote playback panel even when no alternate tracks are available. Single audio tracks remain visible, and empty audio/subtitle sections explain that the stream has no selectable tracks. The decorative series backdrop is excluded from accessibility so its oversized image cannot cover episode controls.

Final verification used a separate iOS 26.5 simulator to avoid concurrent app installs from another task. All **4 app tests and 6 UI scenarios** passed in their final runs: `build/series-favorites-tests-isolated.xcresult` plus `build/series-favorites-large-final.xcresult`. The latter reruns the accessibility scenario with a carousel gesture above the floating playback bar. Coverage includes legacy favorites, source isolation, new seasons, series versus episode identity, persistence across launch, removal, poster-card/header/continuation hearts, episode playback, and audio/subtitle panels with and without tracks. Localization validation passed with 472 keys in 22 languages; staged and unstaged whitespace checks passed. Screenshots and the per-test result summary are in `build/favorites-preview/`.

The earlier favorite-scope regression run (`build/favorite-scope-regression.xcresult`) passed **4 app tests and 4 UI tests**. It covered the former inherited-heart behavior, a separately saved episode lighting its Continue Watching card, both selections surviving relaunch, independent removal, source isolation, legacy records, and accessibility text sizes. The inherited-heart behavior was superseded by the October 17 correction: series and episode hearts now reflect their own saved state. The native scope menu and episode badges were also checked in simulator screenshots under `build/favorite-scope-preview/`. Localization validation passed with 481 keys across 22 languages. These results are from the simulator; this regression fix was not installed on a physical device.

The October 17 episode-heart correction passed **1 app test and 4 UI tests** in `build/episode-favorite-isolation.xcresult`. Coverage includes a saved series leaving episode hearts empty, explicitly saved episodes showing filled hearts, removing an episode while retaining its series, persistence across relaunch, independent series card/header state, the full Continue Watching list, and accessibility text sizes. The shared button applies the same episode-only rule to phone and external playback, Continue Watching, and downloads. Screenshots and the result summary are under `build/episode-favorite-preview/`. Localization validation passed for 481 keys in 22 languages; staged and unstaged whitespace checks passed. This correction was tested in the simulator and was not installed on a physical device.

The detail-poster placement passed **3 UI scenarios** in their final runs: favorite toggling and persistence, single-season details/playback, and season playback with accessibility text sizes. Evidence is split between `build/series-favorite-placement.xcresult` and `build/series-favorite-placement-large-final.xcresult`. The large-text test first confused the poster title with an episode row; its selector now targets the episode control. Its first retry encountered a simulator keyboard-focus failure, and the final retry passed. Normal and large-text screenshots plus the full run history are in `build/series-favorite-placement-preview/`. Localization and whitespace checks passed; no physical-device install was performed.

The poster-overlay placement was subsequently replaced after visual review. The heart now occupies the empty area beside the poster, aligned to the page's right content margin, with its own circular material surface. The existing series/episode favorite UI regression passed in `build/series-favorite-spacing.xcresult`; the final screen was visually checked in `build/series-favorite-spacing-preview/mirivo-favorites-series-header.png`.

## Favorite entry points

Movie rows omit the favorite button in both catalog and search results. Live-channel and radio rows retain their direct favorite controls. The live player channel switcher keeps its favorite button independent of channel selection and uses the playing source's identity. Continue Watching's full list and carousel both directly toggle the resumable item. Movies can still be favorited from their player, Continue Watching, or downloads. Series episode rows and the mini player remain unchanged.

Downloads resolve their original remote channel by the download's asset hash within the original source catalog, including the encrypted catalog cache after relaunch. The list favorites that source item; deleting a downloaded file does not remove its favorite. Downloads whose original source or channel is no longer available cannot be mapped to a valid remote favorite. No provider URL is added to the plaintext download manifest.

The CarPlay root menu now links to a mixed Favorites list. Series navigate to their current episodes, while individual items retain their source and playback configuration. The menu handles empty state and pagination and refreshes when favorites change on the phone. CarPlay template tests exercise item types, callbacks, source identity, page navigation, and deletion while viewing a later page; physical head-unit validation remains separate.

Final verification on the isolated iOS 26.5 simulator passed **3 app tests and 6 UI scenarios**. The final evidence is split across `build/favorite-placements.xcresult` (CarPlay templates, offline identity, downloaded-item persistence/removal, live switcher at both text sizes), `build/favorite-placements-final-2.xcresult` (catalog/search/movie/live/radio favorites and relaunch), and `build/favorite-placements-menu.xcresult` (full Continue Watching list at both text sizes). Earlier UI attempts exposed test interactions with an offscreen lazy category and XCTest's automatic menu hit point; the final tests scroll the full category into view and tap the visible menu row center. Continue Watching's large-text layout also moves the actions beside its artwork so the title retains the full row width. Screenshots and per-test run history are under `build/favorite-placements-preview/`. Localization validation passed for 481 keys in 22 languages, and staged/unstaged whitespace checks passed. No physical-device install or vehicle test was performed for these additions.

The subsequent October 17 direct-toggle correction supersedes those movie-row and scope-menu checks. **3 UI scenarios passed** across `build/direct-favorites.xcresult` and `build/direct-favorites-final.xcresult`: full-list/carousel synchronization, episode/movie favorites with removal and relaunch, and movie-row omission with live/radio catalog and search controls. The isolated series/episode retry in `build/direct-favorites-series.xcresult` completed its functional assertions, including header toggling, independent episode state, media options, and both records after relaunch, but exceeded the 180-second allowance and failed during app termination; it is **not a passing test run**. The detail heart's decorative border now excludes hit testing, and the UI check waits for deselection. Build and localization validation passed (481 keys, 22 languages); screenshots and full run results are under `build/direct-favorites-preview/`. No physical-device installation was performed.

## Performance and regression audit — October 18, 2026

Existing application, release and navigation changes were preserved. The audit reduces repeated work without changing playback access rules or upgrading media dependencies:

- CarPlay menus observe relevant state changes instead of polling every second. Cached catalogs open immediately, refreshes do not push a duplicate page, and disconnects cancel pending selection work and complete callbacks once.
- Channel classification is calculated once from immutable media information. Library filtering is reused within each render; unchanged playback/capture state and saved playback records no longer trigger redundant publications or Keychain writes.
- Artwork requests share in-flight work; cancelling one reader leaves other readers intact. The source catalog memory cache is bounded and evicted catalogs can return from encrypted disk storage. The concurrently added artwork disk cache is preserved.
- HLS preparation cancels cleanly even when an underlying loader returns late. Download progress is throttled before dispatching onto the main actor. Source removal writes the new source list before deleting credentials and rolls back on credential deletion failure.
- Stream readers wake when new fragments arrive instead of polling every 20 ms. Static screen frames reuse rendered pixels while retaining fresh encoded timestamps; changes to source pixels, orientation, dimensions and captions invalidate that cache. Existing backpressure, connection limits and session revocation remain in effect.
- Deprecated app APIs were migrated to current CarPlay completion handlers, view-controller orientation invalidation and current external-display roles. Unused view types and download projections were removed. Install/simulator commands retain their build cache by default and still offer explicit cleanup. Device discovery supports both current and older `devicectl` JSON layouts.
- The phone's remote-playback episode buttons now use their full 44×44-point hit area. XCTest captured a no-op next-episode tap when the accessible area had shrunk to roughly 13×11 points; explicit rectangular content shapes fixed the control, and the CarPlay UI test verifies its size and both navigation directions.

### Measurements

`scripts/benchmark_catalog.swift` was compiled with `-O` for macOS 14 and run in three alternating before/after pairs, with a warm-up and nine measurements per operation in each run. The baseline uses `MediaLibrary.swift` from `f4661ef`; the other Core files and benchmark are identical. For a synthetic 20,000-item catalog, medians were:

| Operation | Before | After | Reduction |
| --- | ---: | ---: | ---: |
| Construct catalog and first grouping | 116.47 ms | 114.80 ms | 1.4% |
| Category and series grouping | 55.80 ms | 27.12 ms | 51.4% |
| Search and sort | 54.95 ms | 32.80 ms | 40.3% |

These are local operation measurements, not iPhone frame-rate, vehicle latency or battery-life claims. Construction time was essentially unchanged. The first implementation's construction regression was detected and corrected before this final comparison. The static-screen media test verifies more than 20 encoded frames with one render and checks cache invalidation and decodability.

### Verification evidence

Evidence is in `build/performance-audit-20261018/` (ignored build artifacts):

- `core-final.log`: 9/9 Media tests and 77 Core tests passed; one provider integration test was skipped because its opt-in configuration was absent.
- `scripts-final.log`: 29/29 deployment tests passed. `release-latest.log`: the later CarPlay panel translations passed validation across 22 languages, 515 keys and 11,330 translated values.
- `iphone-final.xcresult`: 18/18 selected tests passed on the physical iPhone 16 Pro with iOS 27.0. Coverage includes artwork coalescing, encrypted cache eviction/reload, failed source removal, CarPlay cancellation/cached selection, download cancellation/progress, PiP teardown/readiness and audio/video transitions. These tests used isolated data; they did not reset the user's library.
- `install-final.log`: `bun run mobile:ios:install --device … --build 37` installed and launched successfully, with zero compiler warnings and zero `deprecated` diagnostics. A later user-started build 38 install also completed. The final Mac regression run includes the intervening navigation changes; the physical run predates those navigation changes.
- `final-regression.xcresult`: 211 simulator app tests executed: 203 passed, seven skipped and one failed on two assertions about VLC-owned wrapper bounds. The corrected inline-video test passed in `repaired-regression-reboot.xcresult`, giving 204 passing app scenarios across those runs. The seven skips cover optional provider fixtures and three PiP checks that require a capable runtime; all three PiP checks passed on the physical phone.
- The live fragment-stream test passed: first frame in 0.247 s, decoded-frame delay 1.308 s, and continued advancement over 20 seconds. This measures the local simulator transport fixture, not CarPlay video output.
- UI verification covers 16 distinct passing scenarios across runs: the 15,348-channel picker in `final-regression.xcresult`, 12 cases in `repaired-regression-reboot.xcresult`, and three in `final-targeted-ui.xcresult` (CarPlay/TV episode controls and stop/relaunch persistence). The broad retry's two failures were resolved by the 44-point hit-area fix and the updated persistent-dismissal expectation. The final targeted run also passed all 12 related app tests with no skips or failures. Earlier broad runs retain their failing status; this is an aggregate of the passing scenarios, not a claim that every historical run passed.

Earlier failed runs remain in the evidence directory. Corrections to outdated tests restore the real player orientation policy, use the current fit-mode API and avoid imposing app bounds on VLC-owned internal wrappers; app viewport, decoder identity, PiP source and rotation assertions remain. UI helpers account for source restoration at launch, scroll controls fully into view and identify episode rows separately from their poster titles. The stop/relaunch test now verifies the existing persistent dismissal policy: stopping hides the bar across launches, history survives, and explicitly resuming playback restores the bar. The movie-sort fixture now supplies the category and date metadata that its test asserts. An interrupted retry waited for XCTest animation quiescence; a process sample showed the app's main thread in its normal run loop, and restarting only the test simulator allowed execution to resume. Source fingerprints record concurrent edits; `MirivoRootView`, `MirrorModel` and `TVConnectionView` changed during the broad UI run, so the final targeted run rebuilt those changes and rechecked 12 related app scenarios plus the affected UI flows.

The physical phone was connected to the Mac, not a vehicle. The initial CarPlay Simulator connection failure was traced to the absence of an iPhone USB device: Xcode/CoreDevice could reach the phone over the local network, but CarPlay Simulator could not establish its USB session. After the user changed cable/port with the phone unlocked, the iPhone appeared in the USB registry and CarPlay Simulator connected. A copy of Apple's existing signed simulator is available at `~/Applications/CarPlay Simulator.app`; the bundle and security settings were not modified.

With the physical iPhone and build 38, the Standard profile displayed Mirivo's external-display connected screen. Switching to **Standard Video Playback** reconnected successfully and displayed Mirivo's CarPlay template menu. Opening Sources, selecting the saved source, displaying its channel list and navigating back twice were verified in the Mac UI. The debug screen test failed to display video: the copied app journal records `externalPlaybackChanged = true` followed by AVFoundation error `-11870` (`AVErrorExternalPlaybackNotSupportedForAsset`) on both attempts. Its automatic stop completed. The journal is under `carplay-device-diagnostics/`; this is an **open video-output failure**, not a video-playback pass. It does not establish whether user/provider media has the same limitation. Real-vehicle reconnects, locked-phone cold launch and parked/driving transitions remain outside this evidence.

To reproduce the working simulator connection, use a USB data cable, unlock/trust the phone when prompted, open CarPlay Simulator and select **Standard Video Playback** for video-capable template testing. Xcode's network device visibility alone does not prove USB connectivity. Apple's setup and video-session behavior are described in [Turbocharge your app for CarPlay](https://developer.apple.com/videos/play/wwdc2025/216/) and [Rev up your CarPlay app](https://developer.apple.com/videos/play/wwdc2026/212/).

iOS 27's runtime advisory about synchronous `AVAudioSession` activation and Apple's `StoreKitTest` header deprecation are distinct from the clean install compiler output. Redundant audio category changes were removed; the activation ordering contract was retained rather than introducing an unverified asynchronous playback migration.

## CarPlay local video transport — 2026-10-18

The `-11870` failure above was reproduced on build 39 with the physical iPhone 16 Pro (iOS 27.0) connected by USB to Apple's CarPlay Simulator, using **Standard Video Playback**. The bundled `ConnectionProbe.mp4` reached external playback and was immediately rejected as `AVError.externalPlaybackNotSupportedForAsset`. The same MP4 bytes played successfully when supplied over HTTP. The clip, codec, resolution and frame rate were not changed or transcoded.

Native video now serves a selected regular local file through the existing `PersonalMediaServer` when CarPlay reports video support and the system owns the video output. The original file URL remains the playback request; each HTTP URL exposes only that file under a random per-playback path, supports byte ranges, uses bounded reads, and is revoked on Stop. Callback identity checks prevent a cancelled preparation from replacing a newer item. If a file already playing on the phone receives `-11870` after an external route is selected, playback retries once through HTTP while preserving the position and pause request. A second rejection remains an error. Phone playback, audio-only/unknown CarPlay capabilities, app-owned external windows, remote media URLs and the compatibility decoder retain their existing paths. Capability changes are assigned before being propagated to playback.

The physical-device runs passed **14 tests, zero failures and zero skips**: 11 personal-media/CarPlay tests in `build/carplay-video-fix-20261018/fixed-device.xcresult`, plus the late-route recovery and two native PiP tests in `device-recovery.xcresult`. Coverage includes actual external playback and timeline advancement, byte-for-byte content equality, URL revocation, cancelled/replaced preparation, paused seek/phone handoff, imported audio queues and slideshow output. The later capability propagation guard is covered separately by the simulator regression.

Simulator verification covers **122 distinct passing scenarios and eight explicit skips** across `simulator-final.xcresult` and `simulator-confirmed.xcresult`. The broad run initially found stale capability propagation and an 800 ms VLC timestamp assumption. The corrected final run passed **20 tests, zero failures**, with only the physical-receiver test skipped. It rechecked all personal-media tests, capability/connection lifetimes, membership, external-window ownership and native/VLC audio-subtitle switching. The timestamp test retains its actual-progress assertion and now polls within a bounded wait. The eight broad-run skips require a physical receiver, optional provider/live-stream fixtures or a PiP-capable runtime. Sources were stable during the final run; subsequent unrelated UI-test edits are outside this verification. Earlier failed/interrupted bundles are retained: one lacked the local HTTP fixtures, and an intermediate rebuild encountered a concurrently edited series-view expression before its existing refactor was picked up.

For the physical receiver test, opt in with `TEST_RUNNER_MIRIVO_TEST_CARPLAY_VIDEO=1` and select `MirivoTests/PersonalMediaIntegrationTests/testCarPlayReceivesLocalVideoThroughHTTP` on a connected iPhone/CarPlay video receiver. This test asserts actual external playback, advancing media time and absence of playback failures; a simulator-only run cannot replace it.

Normal app launch and the CarPlay menu's **Ekran bağlantı testi** were also checked outside XCTest. The receiver displayed the full-screen Mirivo test pattern with the `00:06.02` frame clock and color bars, then returned to the menu at the automatic stop. Its journal records external playback after 0.35 seconds, playing after 0.36 seconds, automatic stop after 15.27 seconds, and no failure. These are diagnostic event timings, not a measured frame-delivery latency. The copied journal, baseline failure, resource hash and per-run results are in `build/carplay-video-fix-20261018/evidence.json` and the adjacent result bundles.

This resolves the reproduced local-MP4 failure in the physical-iPhone/CarPlay-Simulator setup. It does not establish real-vehicle behavior, locked-phone cold launch, parked/driving transitions or compatibility with every provider format. Apple's [error definition](https://developer.apple.com/documentation/avfoundation/averror-swift.struct/externalplaybacknotsupportedforasset) and [CarPlay video presentation guidance](https://developer.apple.com/videos/play/wwdc2026/212/) describe the API context; the transport diagnosis above comes from the before/after device measurements.

### Independent recheck — build 40, 2026-10-18

The current fix was rechecked on the physical iPhone 16 Pro (iOS 27.0) with Apple's CarPlay Simulator **Standard Video Playback** over USB. `build/carplay-video-recheck-20261018/device.xcresult` passed **15 tests, zero failures and zero skips**: all 13 `PersonalMediaIntegrationTests` plus the two native PiP teardown/readiness checks. The physical receiver test was enabled with `TEST_RUNNER_MIRIVO_TEST_CARPLAY_VIDEO=1`; it confirmed active external playback, more than six seconds of advancement, HTTP transport and no diagnostic failures. Source hashes were unchanged between test start and finish. The tested app was Debug 1.0 (40), not an App Store/TestFlight binary.

After XCTest, the app was launched normally and the CarPlay **Ekran bağlantı testi** menu item was selected again. The receiver visibly showed the Mirivo display test and color bars with the counter at **00:14.17**. The corresponding journal recorded external playback at 0.350386 s, playing at 0.365076 s and automatic Stop at 15.398921 s, with no failures. These event timings are not frame-delivery latency measurements. Evidence: `Release/AppStore/carplay-video-recheck-20261018.json`.

The reproduced local-MP4 `-11870` failure is resolved in this setup. Real-vehicle playback, starting a new source with a locked phone, and park → drive → park remain unverified; this recheck does not close those acceptance items.

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
