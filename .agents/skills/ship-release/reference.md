# Ship Storefront Release — Reference

Command cookbook and constants. Read from [SKILL.md](SKILL.md) only when executing a step.

## Version sources

| File | Keys |
|------|------|
| `Storefront/Resources/Info.plist` | `CFBundleShortVersionString`, `CFBundleVersion` |
| `project.yml` → target `info.properties` | same string values |

GitHub remote / releases: `nuotsu/storefront-macos-menubar`  
Sparkle feed (in Info.plist): `…/releases/latest/download/appcast.xml`

**Asset naming contract:** DMG is always `Storefront.dmg` (never versioned). Site + Sparkle use `…/releases/latest/download/Storefront.dmg` (`web/src/lib/download-macos.ts`). Only the dSYM zip includes the version: `Storefront-X.Y.Z.dSYM.zip`.

## Gather

```bash
git describe --tags --abbrev=0
PREV=$(git describe --tags --abbrev=0)
git log "$PREV"..HEAD --pretty=format:'%h %s%n%b'
git diff "$PREV"..HEAD --stat
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Storefront/Resources/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Storefront/Resources/Info.plist
curl -sS 'https://storefront.nuotsu.dev/docs.md'
```

## Bump + generate

Edit both plist and `project.yml`, then:

```bash
xcodegen generate
```

## Release build

```bash
xcodebuild \
  -project Storefront.xcodeproj \
  -scheme Storefront \
  -configuration Release \
  -derivedDataPath build \
  -destination 'platform=macOS' \
  build
```

Verify:

```bash
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  build/Build/Products/Release/Storefront.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
  build/Build/Products/Release/Storefront.app/Contents/Info.plist
```

## Notarize DMG

Requires Developer ID Application cert + notary profile `storefront-notary` (or API key env vars — see `scripts/release-dmg.sh`).

```bash
./scripts/release-dmg.sh build/Build/Products/Release/Storefront.app
```

Output: `dist/Storefront.dmg`

## Sparkle appcast

```bash
GENERATE_APPCAST=$(find build -name generate_appcast -type f | head -1)
mkdir -p dist/appcast-staging
rm -rf dist/appcast-staging/*
cp dist/Storefront.dmg dist/appcast-staging/
"$GENERATE_APPCAST" dist/appcast-staging
cp dist/appcast-staging/appcast.xml dist/appcast.xml
cat dist/appcast.xml
```

Confirm `sparkle:shortVersionString` and `sparkle:version` match the release. Enclosure URL may point at `…/releases/latest/download/Storefront.dmg` (intentional). `generate_appcast` also emits `sparkle:hardwareRequirements` `arm64` from the thinned bundle — expected, and it keeps Sparkle from offering the build to Intel Macs.

## Archive the dSYM

The Release binary ships stripped, so the `.dSYM` is the only way to symbolicate a crash report from a released build. Derived data is gitignored, so it must leave the machine as a release asset.

```bash
VER=X.Y.Z
ditto -c -k --keepParent \
  build/Build/Products/Release/Storefront.app.dSYM \
  "dist/Storefront-$VER.dSYM.zip"

# UUIDs must match
dwarfdump --uuid build/Build/Products/Release/Storefront.app.dSYM
dwarfdump --uuid build/Build/Products/Release/Storefront.app/Contents/MacOS/Storefront
```

## Artifact sanity checks

```bash
ls -lh dist/Storefront.dmg                                    # ~5 MB, not ~9.5
lipo -archs build/Build/Products/Release/Storefront.app/Contents/MacOS/Storefront   # arm64
# English-only Sparkle (strip-sparkle-locales.sh runs from release-dmg.sh)
find build/Build/Products/Release/Storefront.app/Contents/Frameworks/Sparkle.framework \
  -type d -name '*.lproj' | grep -v '/en.lproj$' | grep -v '/Base.lproj$' && echo 'FAIL: non-English Sparkle locales' || echo 'OK: Sparkle locales English-only'

MP=$(hdiutil attach dist/Storefront.dmg -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)
lipo -archs "$MP/Storefront.app/Contents/MacOS/Storefront"
find "$MP/Storefront.app/Contents/Frameworks" -name Sparkle -type f -exec lipo -archs {} \;
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MP/Storefront.app/Contents/Info.plist"
hdiutil detach "$MP" -quiet
```

## Commit, tag, release

```bash
git add Storefront/Resources/Info.plist project.yml
# plus any other files intentionally included in this ship commit
git commit -m "$(cat <<'EOF'
Ship Storefront vX.Y.Z.

Short why / what landed in this cut.
EOF
)"

git push -u origin HEAD
git tag -a vX.Y.Z -m "Storefront vX.Y.Z"
git push origin vX.Y.Z

gh release create vX.Y.Z \
  dist/Storefront.dmg \
  dist/appcast.xml \
  dist/Storefront-X.Y.Z.dSYM.zip \
  --title "Storefront vX.Y.Z" \
  --notes "$(cat <<'EOF'
## What's new

- **Feature** — description

Sparkle auto-update from PREV should offer this build.
EOF
)"

# Must list Storefront.dmg (never Storefront-X.Y.Z.dmg)
gh release view vX.Y.Z --json assets --jq '.assets[].name'
```

## Sanity

| | |
|--|--|
| Project | `esz74z9f` |
| Dataset | `production` |
| Docs page | `b947dba6-bbda-4671-b30c-56552a468f51` — callout intro `Latest: vX.Y.Z`; prose module + `markdown.code` for body copy |
| Footer nav | `dc49cd75-e8ef-4a28-b9bb-bab6d84880ea` — `blurb[].html.code` `<code>vX.Y.Z</code>` |
| Auth | `~/.config/sanity/config.json` → `authToken` (CLI login). MCP often cannot write this org/project. |

### Version strings

```bash
python3 .agents/skills/ship-release/scripts/update-sanity-version.py 0.0.7 0.0.8
```

### Docs copy — fetch current

Public markdown mirror (good for drafting diffs):

```bash
curl -sS 'https://storefront.nuotsu.dev/docs.md'
```

Published document (prose PT + markdown field):

```bash
python3 - <<'PY'
import json, pathlib, urllib.parse, urllib.request
cfg = json.loads((pathlib.Path.home() / ".config/sanity/config.json").read_text())
token = cfg["authToken"]
DOC = "b947dba6-bbda-4671-b30c-56552a468f51"
API = "https://esz74z9f.api.sanity.io/v2024-01-01/data"
q = f'*[_id == "{DOC}"][0]'
url = f"{API}/query/production?query=" + urllib.parse.quote(q)
req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
print(json.dumps(json.load(urllib.request.urlopen(req))["result"], indent=2))
PY
```

Docs body lives in:

- `modules[_type == "callout"]` — eyebrow / intro (version line)
- `modules[_type == "prose"].content` — Portable Text for `/docs`
- `markdown.code` — verbatim Markdown for `/docs.md`

Keep prose and `markdown.code` in sync after any copy edit. Convert PT → Markdown with the same rules as `web/.agents/skills/generate-markdown/SKILL.md` (verbatim; image CDN URLs from `asset._ref`; skip callout version line in body markdown if the curated file historically omits it — match the existing `/docs.md` shape).

### Docs copy — mutate (after approval)

Same auth/API as the version script. Typical flow:

1. Fetch the full Docs page document.
2. Edit `modules` prose blocks (and only the approved spans/blocks).
3. Set `markdown.code` to the full regenerated Markdown string (preserve `markdown.language` / `markdown.filename` when present).
4. `POST` a `createOrReplace` (strip `_rev` / `_updatedAt` / `_createdAt` first) or a `patch` with `set` paths.
5. Refetch and confirm both surfaces match the approved copy.

Do not leave Docs copy updates as unpublished drafts when shipping a release — publish via the mutate API the same way version bumps land.

### Live checks (allow ~30s for CDN/ISR)

```bash
curl -sS 'https://storefront.nuotsu.dev/' | rg -o 'v0\.0\.[0-9]+' | sort | uniq -c
curl -sS 'https://storefront.nuotsu.dev/docs' | rg -o 'v0\.0\.[0-9]+' | sort | uniq -c
curl -sS 'https://storefront.nuotsu.dev/docs.md' | head -n 40
# If Docs copy changed, also spot-check new wording:
# curl -sS 'https://storefront.nuotsu.dev/docs.md' | rg -n 'relevant phrase'
```

Callout version lives in modules PT (`Latest: vX.Y.Z`); `/docs.md` usually has **no** hardcoded app version in the body. Ignore `SanityPress v0.0.127` in `<meta name="generator">` — that is the site template, not the macOS app.

## Local open after ship

```bash
pkill -x Storefront 2>/dev/null || true
sleep 0.2
open build/Build/Products/Release/Storefront.app
```

Do not send Cmd+, or otherwise open Settings.
