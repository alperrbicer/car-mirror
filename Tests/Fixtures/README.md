# Inline video regression fixture

`InlineVideo.mkv` is the project's `Resources/ConnectionProbe.mp4` remuxed into
Matroska with VLC, without re-encoding. It contains no provider/account data and
is bundled only in `MirivoTests`.

The inline playback test opens this real MKV before mounting `MediaPlayerScreen`,
so the source-list mini player can acquire the shared VLC surface first. It checks
that the visible player takes ownership, has a correctly sized video renderer,
and produces a screenshot attachment without opening full screen.

Rotation coverage mounts the actual full-screen and vehicle players, requests
portrait, landscape left, landscape right, then portrait again, and checks that
the renderer occupies the entire window without replacing the playback session.
The same checks use the original MP4 with AVPlayer. Screenshot attachments cover
landscape playback with the controls visible and after they automatically hide.

Seek coverage uses both real videos while playing, checks forward/backward and
successive targets, then verifies that new video frames reach the output (VLC's
displayed-picture counter or AVPlayer's pixel-buffer timestamps). It also checks
that seeking while paused, including an unchanged position, preserves the pause.

The opt-in provider seek test reads `tmp/mirivo-vod-probe.json` from the simulator
app container. It exercises longer jumps and records only numeric timing/frame
statistics. It does not attach provider screenshots or print the source URL.
Keep that account fixture out of the repository and remove it after the test.

## Library artwork and metadata

`LibraryArtworkUITests` uses an original synthetic catalog, never a provider account.
Generate its PNG logos/posters with `xcrun swift scripts/generate_library_artwork_fixture.swift`,
then run `MIRIVO_FIXTURE_PORT=8774 python3 scripts/capture_store_screenshots.py` during the tests.
The generated files live under the ignored `build/library-artwork-fixtures` directory.
The catalog exercises category collages, artwork rows, search, on-demand Xtream movie
details, unavailable images/metadata, and accessibility text sizes. No demo media
or test account is added to the shipping app.

The `testMovieList…` sorting tests use a separate instance on port 8776:
`MIRIVO_FIXTURE_PORT=8776 python3 scripts/capture_store_screenshots.py`.
Its `/sort-{delayed,failed,missing,embedded}/get.php` lists exercise a six-second
recency response, cached reopening, an HTTP error, missing dates, and dates already
included in the playlist. Film rows must wait for the initial recency result.

Metadata coverage also uses an ordinary `/catalog.m3u` URL, with no API credentials
in the playlist address. The stream routes identify the movie/series API account.
The fixture verifies general series descriptions, episode-specific descriptions,
and a metadata HTTP failure with retry instead of an empty-description claim.

The catalog also includes two series with deliberately shuffled episode numbers,
multiple seasons, and shared posters. Generate the 90-second playback fixture with
`python3 scripts/generate_playback_options_fixture.py` before exercising series playback.
The debug-only `-mirivo-ui-artwork-history` flag seeds older-style history records
without artwork, so UI coverage checks poster recovery from the source as well as
season selection, episode ordering, and resuming the saved position.
