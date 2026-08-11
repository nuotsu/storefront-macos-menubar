// Isomorphic on purpose: `src/sanity/schemaTypes/objects/link.ts` imports these
// into the Studio bundle. The release lookup lives in `@/ui/download-macos-link`
// so `next/cache` stays out of the browser.

// Release contract (ship-release): GitHub asset must stay `Storefront.dmg` —
// never versioned — so this latest/download URL keeps working across releases.

/** Always resolves to the latest GitHub release DMG via redirect. */
export const MACOS_DMG_URL =
	'https://github.com/nuotsu/storefront-macos-menubar/releases/latest/download/Storefront.dmg'

export const MACOS_DMG_FILENAME = 'Storefront.dmg'

export const MACOS_RELEASES_API =
	'https://api.github.com/repos/nuotsu/storefront-macos-menubar/releases/latest'
