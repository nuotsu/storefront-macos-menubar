---
name: ship-release
description: >-
  Ships a Storefront macOS release end-to-end: draft GitHub release notes and
  docs copy updates for review, bump version, Release build, notarize DMG,
  Sparkle appcast, tag and publish on GitHub, then update Sanity Studio version
  strings and Docs page copy. Use when the user asks to release, ship, cut a
  version, write a changelog, refresh the appcast, or update Sanity docs/footer
  for a new app version.
---

# Ship Storefront Release

Full release pipeline for the Storefront macOS menu bar app. **Hard gate:** draft notes, version, and any Docs copy updates for the user to approve before any bump, build, tag, GitHub publish, or Sanity mutation.

For exact command blocks, paths, and Sanity IDs, see [reference.md](reference.md).

## Checklist

Copy and track:

```
Release progress:
- [ ] 1. Gather commits + current version
- [ ] 2. Draft notes + docs copy + proposed version (STOP for approval)
- [ ] 3. Bump version files + xcodegen
- [ ] 4. Release build → notarize DMG → generate appcast → archive dSYM
- [ ] 5. Commit, push, tag, gh release (DMG + appcast + dSYM)
- [ ] 6. Update Sanity versions + docs copy + verify live site
```

## Step 1 — Gather

From the repo root:

1. Latest tag: `git describe --tags --abbrev=0`
2. Commits since tag: `git log <tag>..HEAD --pretty=format:'%h %s%n%b'`
3. Diff summary: `git diff <tag>..HEAD --stat`
4. Current marketing/build from both:
   - `Storefront/Resources/Info.plist` (`CFBundleShortVersionString` / `CFBundleVersion`)
   - `project.yml` (same keys under `info.properties`)

They must match. If they don't, stop and fix before continuing.

Also pull current public Docs for the Step 2 draft:

- `curl -sS https://storefront.nuotsu.dev/docs.md`
- Optionally the published Docs page document from Sanity (id in [reference.md](reference.md))

## Step 2 — Draft notes + docs copy (STOP)

Default version bump: patch on the third number (`0.0.N` → `0.0.N+1`, build `N+1`) unless the user named a version.

### Release notes

Draft GitHub release notes in this shape only — bold lead-in, em dash, user-facing bullets from the actual diff. Do not invent items.

```markdown
## What's new

- **Feature** — short description
…

Sparkle auto-update from X.Y.Z should offer this build.
```

### Docs copy

Compare the release diff / notes against current Docs (`/docs.md` and the live `/docs` prose). Propose **user-facing Docs updates** that this release requires:

- New or changed Settings behavior, shortcuts, CSV columns, section presets, etc.
- Wording that would be wrong or incomplete after this ship
- New headings/sections only when the release adds a real user-facing surface worth documenting

Rules:

- Base edits on the actual diff — do not invent features.
- Match existing Docs tone: short imperative sentences, Settings paths with `→`, keyboard shortcuts in `` `code` ``.
- Prefer surgical edits to existing sections over rewriting the whole page.
- If nothing in the release affects Docs, say **No Docs copy changes** explicitly.
- Do **not** rewrite README unless the user asks.
- Screenshots: only flag when a UI change makes an existing screenshot misleading; do not replace assets unless the user asks.

Present proposed Docs changes as a clear before/after (or a unified diff against `/docs.md`). Keep callout/footer version strings out of this draft — Step 6’s version script handles `Latest: vX.Y.Z` and the footer `<code>`.

Present to the user:

- Proposed tag (`vX.Y.Z`) and build number
- Full draft notes body
- Brief list of commits included
- Proposed Docs copy updates (or **No Docs copy changes**)

**Do not bump, build, tag, push, create a GitHub release, or mutate Sanity until the user explicitly approves** (and any edits they make to the notes / Docs copy).

## Step 3 — Bump (after approval)

1. Set `CFBundleShortVersionString` / `CFBundleVersion` in **both** `Info.plist` and `project.yml`.
2. Run `xcodegen generate`.
3. Commit message style: `Ship Storefront vX.Y.Z.` with one short body sentence on why (include the bump). Prefer committing the version bump together with any last polish already in the working tree that belongs in this release; do not commit unrelated dirty files.

## Step 4 — Build, notarize, appcast, dSYM

1. Release build (see [reference.md](reference.md)).
2. Verify the built app plist shows the new version/build.
3. `./scripts/release-dmg.sh build/Build/Products/Release/Storefront.app`
4. Locate `generate_appcast` under `build/SourcePackages/artifacts/sparkle/`, stage `dist/Storefront.dmg` into `dist/appcast-staging/`, run it, copy `appcast.xml` to `dist/appcast.xml`. Confirm `sparkle:shortVersionString` and `sparkle:version` match the release.
5. **Archive the `.dSYM`.** Zip `build/Build/Products/Release/Storefront.app.dSYM` to `dist/Storefront-X.Y.Z.dSYM.zip` and confirm `dwarfdump --uuid` matches the shipped binary. The Release config strips the binary (`DEPLOYMENT_POSTPROCESSING = YES` in `Config/Release.xcconfig`), so this is the only thing that can symbolicate a crash report from this build — and it otherwise lives only in gitignored derived data.

Sanity-check the artifacts before publishing: DMG around 5 MB (not 9.5), `lipo -archs` on the app binary and `Sparkle.framework` both `arm64`, Sparkle Resources only `en.lproj` (non-English locales stripped), and the DMG mounts.

## Step 5 — GitHub release

Repo: `nuotsu/storefront-macos-menubar`

1. `git push -u origin HEAD`
2. Annotated tag `vX.Y.Z`, push the tag
3. `gh release create vX.Y.Z dist/Storefront.dmg dist/appcast.xml dist/Storefront-X.Y.Z.dSYM.zip --title "Storefront vX.Y.Z" --notes "…"` using the **approved** notes
4. Verify assets: `gh release view vX.Y.Z --json assets --jq '.assets[].name'` must list `Storefront.dmg` (and must not list a versioned DMG)

**Hard rule — DMG filename:** upload as **`Storefront.dmg` only** — never `Storefront-X.Y.Z.dmg` or any other name. Sparkle, README, and the site download (`web/src/lib/download-macos.ts` → `MACOS_DMG_URL`) all depend on the stable `…/releases/latest/download/Storefront.dmg` URL. Only the dSYM zip is versioned (`Storefront-X.Y.Z.dSYM.zip`).

All three assets ship every release. Never force-push tags. Never `--no-verify`.

## Step 6 — Sanity versions + Docs copy

Project `esz74z9f`, dataset `production`.

### 6a — Version strings

Known string homes:

- Docs page callout intro (`Latest: vX.Y.Z`)
- Footer navigation custom HTML (`<code>vX.Y.Z</code>`)

Prefer the skill script (Sanity MCP often cannot write this project):

```bash
python3 .agents/skills/ship-release/scripts/update-sanity-version.py <OLD> <NEW>
```

Example: `… 0.0.7 0.0.8` (script accepts with or without a leading `v`).

### 6b — Docs copy (when Step 2 had approved edits)

Apply the **approved** Docs updates to the Docs page document (`b947dba6-bbda-4671-b30c-56552a468f51`):

1. **Prose module** (`modules[_type == "prose"].content`) — this is what `/docs` renders. Patch Portable Text so the live page matches the approved copy.
2. **`markdown.code`** — this is what `/docs.md` (and `/llms.txt`) serve. Regenerate it from the updated modules so it stays in lockstep with the page (same conversion rules as `web/.agents/skills/generate-markdown/SKILL.md`: verbatim PT → Markdown, resolve image CDN URLs from `asset._ref`, keep existing frontmatter).
3. Mutate published documents via the Sanity HTTP API with the CLI token (same auth as the version script). Prefer `createOrReplace` on the full document after editing, or targeted `patch` sets — do not leave approved copy sitting only in a draft.
4. If Step 2 said **No Docs copy changes**, skip 6b entirely (version script alone is enough).

See [reference.md](reference.md) for fetch/mutate snippets.

### Verify

- Version script reports no remaining old versions
- If Docs copy changed: refetch the Docs document and confirm both prose and `markdown.code` reflect the approved text
- Live: `storefront.nuotsu.dev` footer / docs show `vNEW`, and updated sections appear on `/docs` and `/docs.md` (CDN/ISR may lag ~30s; recheck once)

## Local app rules

If opening a local build after ship:

1. `pkill -x Storefront` first
2. `open` the app only — do **not** send Cmd+, or auto-open Settings

## Out of scope

- Changing Sparkle keys, signing identity, or notary credentials
- README feature rewrites (unless the user asks)
- Force-push / history rewrite
- Replacing Docs screenshots unless the user asks
