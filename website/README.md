# Gala documentation site

This is the public Gala Engine site, built with Astro and Starlight. The landing page is `src/pages/index.astro`; documentation lives in `src/content/docs/`. The sidebar is configured in `astro.config.mjs`.

## Work locally

```sh
cd website
npm ci
npm run build
```

For an interactive preview, run `npm run dev -- --background`. Use `npm run astro -- dev status`, `npm run astro -- dev logs`, and `npm run astro -- dev stop` to manage that background server. The production build goes to `dist/`, which Git ignores.

The site is configured for `https://shlok-bhakta.github.io/Gala-Engine/`. Keep internal links under the `/Gala-Engine` base path. The `baseLinks` remark plugin in `astro.config.mjs` prefixes root-relative links in Markdown and MDX; Astro page templates use `import.meta.env.BASE_URL`.

## Publish

`.github/workflows/docs.yml` builds the site from `website/` and deploys it with GitHub Pages whenever `website/` changes on `main`. The repository's Pages source must be **GitHub Actions**. The workflow can also be run manually from the Actions tab.

Documentation should follow the behavior in the repository's `README.md`, `bin/gala`, and the example recipes. Do not describe an unsigned IPA as installable or a completed IPA transfer as proof that iOS finished installing an app.
