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
