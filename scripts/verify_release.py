#!/usr/bin/env python3
"""Offline release checks. Does not claim provisioning or vehicle acceptance."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json, plistlib, re, sys, zipfile
ROOT=Path(__file__).resolve().parents[1]
errors=[]; count=0
class Page(HTMLParser):
 def __init__(self):super().__init__();self.links=[];self.lang=None;self.h1=0;self.tracking=False
 def handle_starttag(self,tag,attributes):
  a=dict(attributes)
  if tag=='html':self.lang=a.get('lang')
  if tag=='h1':self.h1+=1
  if tag in ['script','iframe','form']:self.tracking=True
  for key in ['href','src']:
   if key in a:self.links.append(a[key])
web=ROOT/'Web'
for path in web.rglob('*.html'):
 count+=1; page=Page(); text=path.read_text();page.feed(text)
 if page.lang not in ['tr','en'] or page.h1!=1:errors.append(f'{path}: language or heading invalid')
 if page.tracking:errors.append(f'{path}: unexpected active content')
 if re.search(r'\b(?:TODO|TBD|PLACEHOLDER)\b',text):errors.append(f'{path}: placeholder')
 for link in page.links:
  parts=urlsplit(link)
  if parts.scheme in ['https','mailto']:continue
  if parts.scheme:errors.append(f'{path}: unexpected URL scheme {parts.scheme}');continue
  if not parts.path:continue
  target=(path.parent/unquote(parts.path)).resolve()
  if not target.is_relative_to(web) or not target.is_file():errors.append(f'{path}: broken local link {link}')
for lang in ['tr','en']:
 for kind in ['privacy','terms','support']:
  public=web/lang/(kind+'.html');bundled=ROOT/'Resources/Legal'/lang/(kind+'.html')
  if public.read_bytes()!=bundled.read_bytes():errors.append(f'{kind}: offline and public content differ')
for path in ['Config/App-Info.plist','Config/Broadcast-Info.plist','Config/App.entitlements','Config/CarPlay.entitlements','Resources/PrivacyInfo.xcprivacy']:
 with (ROOT/path).open('rb') as f:plistlib.load(f)
base=(ROOT/'Config/Base.xcconfig').read_text()
if not re.search(r'^MIRIVO_PRO_SALES_ENABLED = NO$',base,re.M):errors.append('First release must keep Pro sales disabled')
if not re.search(r'^MARKETING_VERSION = 1.0$',base,re.M):errors.append('Version must match App Store Connect 1.0')
tr=(ROOT/'Resources/tr.lproj/Localizable.strings').read_text();en=(ROOT/'Resources/en.lproj/Localizable.strings').read_text()
keys=lambda s:set(json.loads(x) for x in re.findall(r'^("(?:[^"\\]|\\.)*")\s*=',s,re.M))
if keys(tr)!=keys(en):errors.append('Localization catalog mismatch')
for source in (ROOT/'Sources').rglob('*.swift'):
 for key in re.findall(r'L10n\.tr\("([^"\\]*)"',source.read_text()):
  if key not in keys(tr):errors.append(f'{source.name}: untranslated literal {key}')
with zipfile.ZipFile(ROOT/'Release/mirivo-netlify.zip') as archive:
 if archive.testzip():errors.append('Corrupt ZIP')
 if 'index.html' not in archive.namelist():errors.append('ZIP index is not at root')
 for path in web.rglob('*'):
  if path.is_file() and archive.read(str(path.relative_to(web)))!=path.read_bytes():errors.append(f'Stale ZIP: {path}')
report={'htmlPages':count,'localizedKeys':len(keys(tr)),'errors':errors,'passed':not errors}
(ROOT/'build/release-static-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(bool(errors))
