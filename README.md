# Storefront

A macOS menu bar app for jumping into any Shopify store’s admin panel. Pick a store, open the section you need, and get on with it.

![Storefront panel](/screenshot.png)

## Features

- Multi-store rail: search, pin, hide, and reorder the stores you manage
- Section deep links: Products, Orders, Themes, Settings, and more, with quick actions
- Appearance, widget background (Liquid Glass or Opaque), and App Icon preferences
- Section presets: built-in role layouts plus custom presets, with Library CSV import/export
- Global hotkey and full keyboard navigation (editable in Settings → Keybindings)
- CSV import/export for stores and section presets

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
