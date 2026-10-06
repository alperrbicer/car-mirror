Mirivo App Store screenshot capture — 2026-10-05

Order in every locale:
01-iptv.png       User-provided IPTV source library
02-channels.png   Playlist channels
03-player.png     Actual video playback, paused after playback starts
04-sharing.png    Screen and personal-media sharing controls
05-xtream.png     Xtream Codes source form
06-carplay.png    Current CarPlay Audio connection guidance

All 22 shipping UI languages have six iPhone screenshots (132 PNG files).
All 22 public App Store sets were uploaded, reordered, then verified after a
full Media Manager reload. The 6.5-inch slot inherits its own locale's 6.9-inch
set. The same six filenames and order were verified in every locale.

iPhone: 1320x2868 RGB; iPhone 16 Pro Max, iOS 26.5.
The captures are unedited XCUIScreen images of the actual application.
Selected build 11 is iPhone-only (Apple Device Family and UIDeviceFamily=[1]).
The old tr/en iPad captures are compatibility-window references, not store sets.
No actual CarPlay Video screenshot exists for the Audio-only candidate.

Resources/ConnectionProbe.mp4 and a temporary localhost M3U fixture provided
original demo content without provider credentials or third-party channels.
The fixture server was stopped. No demo source is added to the shipping app.

Capture evidence:
- tr/en: build/store-iphone-screenshots-r3-20261005.xcresult — passed
- 12 additional locales: passing cases in
  build/store-iphone-additional-languages-20261005.xcresult;
  that whole initial suite failed; failed partial captures are excluded
- remaining eight: build/store-iphone-additional-languages-retry-20261005.xcresult
  — all eight passed
- 14 localized player images: build/store-localized-player-20261005.xcresult
  — all 14 passed; nine previously English labels were translated and included
  in distribution build 11, which Apple processed as Validated

Per-file resultBundle/testCase evidence and SHA-256: iphone-provenance.json.
Upload, inheritance, common order and reload verification: upload-manifest.json.
All 22 version metadata records were saved and re-read in App Store Connect.
Product review screenshots were uploaded separately from pro-plans/.
