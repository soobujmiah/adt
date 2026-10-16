# Extractable components

## SiteHeader
- Source: `index.html` and `_includes/header.html`
- Category: layout
- Description: sticky brand navigation with section links, language switch and repository links.
- Extractable props: active section, locale.
- Hardcoded: ADT brand, arm64 tag, nav labels, colors.

## EvidenceBadge
- Source: `assets/css/adt.css` and `index.html`
- Category: basic
- Description: compact evidence state labels such as Verified or Not yet tested.
- Extractable props: evidence status and label.

## ActionButton
- Source: `assets/css/adt.css` and `index.html`
- Category: basic
- Description: primary and secondary links for install, docs, releases, and repository.
- Extractable props: label, href, primary state.

