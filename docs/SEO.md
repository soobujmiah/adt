# SEO Record — adt

| Field | Value |
|---|---|
| **SEO standard** | [soobujmiah SEO Standard v1](https://github.com/soobujmiah/soobujmiah.github.io/blob/main/docs/SEO_STANDARD.md) |
| **Last audit** | 2026-09-16 |
| **Site status** | `LIVE_SITE` — https://soobujmiah.github.io/adt/ (GitHub Pages, workflow deploy) |
| **Search intent** | native ARM64 Android development toolchain for Linux · aarch64 build-tools / platform-tools · AOSP · Termux / PRoot |
| **Identity hub** | https://soobujmiah.github.io/ (author: Sobuj Miah) |

## Audit result (2026-09-16)

| Check | Result |
|---|---|
| `<title>`, description, canonical, `lang`, viewport | PASS |
| `robots` meta | **missing → added** (`index,follow`; robots.txt already allowed all) |
| `author` meta | **missing → added** |
| `robots.txt`, `sitemap.xml` (2 URLs: `/adt/`, `/adt/docs/`) | PASS |
| Open Graph (title, description, url, image 1200×630 + alt, locale + bn_BD alternate, site_name) | PASS |
| Twitter card | image + alt present; **title/description were missing → added** |
| JSON-LD | PASS — `SoftwareApplication` (author Person → portfolio), `BreadcrumbList` (Portfolio → ADT) |
| Backlink to portfolio / GitHub source / Ternux | PASS |
| Repository description, homepage, 10 topics | PASS — description already says "ARM64 Android development toolchain" |
| README author + portfolio link | **GAP → added** |
| Intent phrase "native ARM64 Android development toolchain for Linux" | **GAP → one sentence added to README** |

## Changes made

- `index.html`: `author`, `robots`, `twitter:title`, `twitter:description` meta added (values mirror existing OG tags).
- `README.md`: SEO badge; one positioning sentence; author → portfolio link; sibling link to Ternux.
- GitHub topics: added `aarch64`, `android-sdk`, `platform-tools`, `adb`, `android-development`.

## Deliberately NOT changed

Site layout, copy, docs page, sitemap, canonical, JSON-LD, OG image, repository description, release artifacts.
