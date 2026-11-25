# Storefront

A macOS menu bar app for jumping into any Shopify store’s admin panel. Pick a store, open the section you need, and get on with it.

![Storefront panel](/screenshot.png)

## Features

- Multi-store rail: search, pin, hide, and reorder the stores you manage
- Sync from Shopify: bring in every store your Shopify organizations can reach (dev, client transfer, and collaborator stores) through the Shopify CLI
- Section deep links: Products, Orders, Themes, Settings, and more, with quick actions
- Live theme shortcut: the published theme appears below Theme library, with a direct link to its editor
- Appearance, widget background (Liquid Glass or Opaque), and App Icon preferences
- Section presets: built-in role layouts plus custom presets, with Library CSV import/export
- Global hotkey and full keyboard navigation (editable in Settings → Keybindings)
- CSV import/export for stores and section presets

### Sync from Shopify

Settings → Stores → **Sync Now** adds every store your Shopify organizations can reach. Storefront reads them through the [Shopify CLI](https://shopify.dev/docs/api/shopify-cli) (`npm install -g @shopify/cli@latest`), signed in with your own Shopify account, so there's no separate login or API key.

- Stores already in your list keep their name, color, visibility, order, and pin.
- New stores arrive hidden (unless your list was empty), so turn on the ones you want. The **New** filter lists them.
- Nothing is ever removed, so stores you added by hand stay put.
- Stores where you're staff directly, outside an organization, don't show up in the CLI. Add those by domain or CSV.

The widget preloads live themes when it opens: the selected store first, then the other visible stores. Hovering or selecting a store moves it to the front of the line. Themes load one store at a time, because overlapping Shopify CLI runs can sign the CLI out. The last known live theme for each store is saved on your Mac and shown right away, then refreshed once it's more than five minutes old. You can also refresh a theme using its card's refresh button. The nested list reserves one row for the theme, with a spinner while loading. Your Shopify account needs theme access for that store.

If a store needs separate theme authorization, click **Sign in to load live theme** in its Themes card. Storefront opens a read-only theme lookup in Terminal so the CLI can complete sign-in for that store, then retries when you return.

### CSV import and export

Storefront can import and export CSV for **stores** and for saved **section presets**.

**Stores** — Settings → Stores. Header row plus one store per line. Color is hex without `#`.

```csv
Display Name,Domain,Color
Acme Coffee,acme-coffee.myshopify.com,1f6f4a
Northwind Outfitters,northwind-outfitters.myshopify.com,c07a2c
Brightleaf,brightleaf-studio.myshopify.com,3a6ea8
```

**Section presets (Library)** — Settings → Sections → Library. One row per section per saved custom preset (`Preset,Section,Title,Enabled`). Built-ins are omitted; import upserts by preset name.

```csv
Preset,Section,Title,Enabled
Store Ops,orders,Orders,true
Store Ops,products,Products,true
```

Details and column notes are in the [docs](https://storefront.nuotsu.dev/docs#csv-import-and-export).

## Docs

Read the full guide: **[storefront.nuotsu.dev/docs](https://storefront.nuotsu.dev/docs)**

## Download

**[Download the latest release](https://github.com/nuotsu/storefront-macos-menubar/releases/latest/download/Storefront.dmg)** (macOS 14+, Apple Silicon)

### Requirements

- macOS 14.0+
- Apple Silicon (arm64). Intel Macs are not supported.

## License

[MIT](LICENSE). Developed by [nuotsu](https://nuotsu.dev).
