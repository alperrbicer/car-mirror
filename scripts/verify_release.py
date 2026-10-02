#!/usr/bin/env python3
"""Offline release checks. Does not claim provisioning or vehicle acceptance."""
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit, unquote
import json, plistlib, re, subprocess, sys, zipfile
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
for path in ['Config/App-Info.plist','Config/Broadcast-Info.plist','Config/App.entitlements','Config/CarPlayAudio.entitlements','Config/CarPlay.entitlements','Resources/PrivacyInfo.xcprivacy']:
 with (ROOT/path).open('rb') as f:plistlib.load(f)
with (ROOT/'Config/App-Info.plist').open('rb') as f:app_info=plistlib.load(f)
ats=app_info.get('NSAppTransportSecurity',{})
if ats.get('NSAllowsArbitraryLoads') is not True:errors.append('User-provided HTTP playlists require URLSession ATS access')
if any(key in ats for key in ['NSAllowsLocalNetworking','NSAllowsArbitraryLoadsForMedia','NSAllowsArbitraryLoadsInWebContent']):
 errors.append('Fine-grained ATS keys override arbitrary HTTP playlist access on supported iOS versions')
for name,video in [('CarPlayAudio',False),('CarPlay',True)]:
 with (ROOT/f'Config/{name}.entitlements').open('rb') as f:entitlements=plistlib.load(f)
 if entitlements.get('com.apple.developer.carplay-audio') is not True:errors.append(f'{name}: Audio entitlement missing')
 if (entitlements.get('com.apple.developer.carplay-video') is True)!=video:errors.append(f'{name}: Video entitlement does not match build mode')
base=(ROOT/'Config/Base.xcconfig').read_text()
if not re.search(r'^MIRIVO_PRO_SALES_ENABLED = NO$',base,re.M):errors.append('First release must keep Pro sales disabled')
if not re.search(r'^MARKETING_VERSION = 1.0$',base,re.M):errors.append('Version must match App Store Connect 1.0')
languages=json.loads((ROOT/'Config/Localizations.json').read_text())
if len(languages)!=22 or len(set(languages))!=22:errors.append('Expected 22 shipping languages')
if not {'ar','he','th','vi','id','hi'}.issubset(languages):errors.append('A newly supported language is missing')
folders={p.parent.name.removesuffix('.lproj') for p in (ROOT/'Resources').glob('*.lproj/Localizable.strings')}
if folders!=set(languages):errors.append('Unexpected or missing locale resources')
catalogs={}
for lang in languages:
 for filename in ['Localizable.strings','InfoPlist.strings']:
  path=ROOT/f'Resources/{lang}.lproj/{filename}'
  if not path.is_file():errors.append(f'{path}: missing');continue
  native=subprocess.run(['plutil','-convert','json','-o','-',str(path)],capture_output=True,text=True)
  if native.returncode:errors.append(f'{path}: invalid Apple strings format');continue
  values=json.loads(native.stdout)
  lines=re.findall(r'^("(?:[^"\\]|\\.)*")\s*=',path.read_text(),re.M)
  if len(lines)!=len(values):errors.append(f'{path}: duplicate or invalid key')
  if not all(isinstance(v,str) and v.strip() for v in values.values()):errors.append(f'{path}: empty translation')
  if filename=='Localizable.strings':catalogs[lang]=values
  elif set(values)!={'NSLocalNetworkUsageDescription'}:errors.append(f'{path}: permission catalog mismatch')
reference=catalogs.get('en',{})
for lang,values in catalogs.items():
 if set(values)!=set(reference):errors.append(f'{lang}: localization catalog mismatch')
 for key,value in values.items():
  if re.findall(r'%(?:\d+\$)?[@dfius]',value)!=re.findall(r'%(?:\d+\$)?[@dfius]',reference.get(key,'')):
   errors.append(f'{lang}: format arguments differ for {key}')
for filename in ['App','Broadcast']:
 with (ROOT/f'Config/{filename}-Info.plist').open('rb') as f:info=plistlib.load(f)
 if info.get('CFBundleLocalizations')!=languages:errors.append(f'{filename}: declared locales differ')
for lang in ['tr','en']:
 metadata=json.loads((ROOT/f'Release/AppStore/{lang}/metadata.json').read_text())
 for key,limit in {'name':30,'subtitle':30,'keywords':100,'promotionalText':170,'description':4000,'whatsNew':4000}.items():
  value=metadata.get(key,'')
  if not value or len(value)>limit:errors.append(f'{lang}: App Store {key} length invalid')
for source in (ROOT/'Sources').rglob('*.swift'):
 for key in re.findall(r'L10n\.tr\("([^"\\]*)"',source.read_text()):
  if key not in reference:errors.append(f'{source.name}: untranslated literal {key}')
with zipfile.ZipFile(ROOT/'Release/mirivo-netlify.zip') as archive:
 if archive.testzip():errors.append('Corrupt ZIP')
 if 'index.html' not in archive.namelist():errors.append('ZIP index is not at root')
 for path in web.rglob('*'):
  if path.is_file() and archive.read(str(path.relative_to(web)))!=path.read_bytes():errors.append(f'Stale ZIP: {path}')
report={'htmlPages':count,'languages':languages,'localizedKeys':len(reference),'translatedValues':sum(len(v) for v in catalogs.values()),'errors':errors,'passed':not errors}
(ROOT/'build/release-static-checks.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2));sys.exit(bool(errors))
