#!/usr/bin/env python3
"""Create original multitrack QA media; outputs stay outside the app bundle."""
from pathlib import Path
import subprocess
import imageio_ffmpeg

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/playback-options-fixtures'
OUT.mkdir(parents=True, exist_ok=True)
for language, text in [('tr', 'Mirivo altyazı testi'), ('en', 'Mirivo subtitle test')]:
    (OUT / f'{language}.srt').write_text(f'1\n00:00:00,000 --> 00:01:30,000\n{text}\n')
ffmpeg = imageio_ffmpeg.get_ffmpeg_exe()
subprocess.run([
    ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
    '-stream_loop', '-1', '-i', str(ROOT / 'Resources/ConnectionProbe.mp4'),
    '-f', 'lavfi', '-i', 'sine=frequency=440:duration=90',
    '-f', 'lavfi', '-i', 'sine=frequency=880:duration=90',
    '-i', str(OUT / 'tr.srt'), '-i', str(OUT / 'en.srt'),
    '-map', '0:v:0', '-map', '1:a:0', '-map', '2:a:0', '-map', '3:s:0', '-map', '4:s:0',
    '-c:v', 'copy', '-c:a', 'aac', '-c:s', 'mov_text',
    '-metadata:s:a:0', 'language=tur', '-metadata:s:a:0', 'title=Türkçe',
    '-metadata:s:a:1', 'language=eng', '-metadata:s:a:1', 'title=English',
    '-metadata:s:s:0', 'language=tur', '-metadata:s:s:0', 'title=Türkçe',
    '-metadata:s:s:1', 'language=eng', '-metadata:s:s:1', 'title=English',
    '-t', '90', '-movflags', '+faststart', str(OUT / 'options.mp4'),
], check=True)
subprocess.run([ffmpeg, '-hide_banner', '-loglevel', 'error', '-y',
                '-i', str(OUT / 'options.mp4'), '-map', '0', '-c', 'copy', '-c:s', 'srt',
                str(OUT / 'options.mkv')], check=True)
print('Created MP4/MKV with two audio languages and two subtitle languages.')
