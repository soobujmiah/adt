# Layouts

## Landing page layout
- Source: `index.html`
- Static Jekyll page; shared header/footer are `_includes/header.html` and `_includes/footer.html`, with base structure in `_layouts/default.html`.
- The main landing page has sticky navigation, a hero, product/toolchain sections, installation and workflow sections, evidence, Ternux ecosystem link, and footer.

## Shared header
```html
<header class="site-header">
  <div class="wrap">
    <a class="brand" href="/adt/">
      <svg width="18" height="18" viewBox="0 0 64 64" aria-hidden="true"><path d="M14 18l14 14-14 14M34 46h16" fill="none" stroke="#22c55e" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>
      <span>ADT</span><span class="tag">arm64</span>
    </a>
    <nav class="site-nav" aria-label="Sections">What is ADT · Toolchain · Install · Workflows · Evidence · Ternux · Docs · GitHub</nav>
  </div>
</header>
```

## Shared footer
Source: `_includes/footer.html` (shared project navigation and ecosystem links).

