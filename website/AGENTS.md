# Website instructions

This is an Astro/Starlight site for the Gala Engine repository. Read the root `README.md` and the relevant `bin/gala` commands before changing product documentation. Keep examples aligned with the checked-in recipes. An unsigned IPA needs signing before install, and a completed transfer does not prove iOS finished installing an app.

Build with `npm run build` from `website/`. For a dev server, use `astro dev --background`; inspect it with `astro dev status` or `astro dev logs`, and stop it with `astro dev stop`.

GitHub Pages serves this project under `/Gala-Engine/`. Use root-relative links in Markdown and MDX; the `baseLinks` plugin prefixes the base path. Astro page templates should use `import.meta.env.BASE_URL`. Check local links and assets in the production output before publishing.

Consult the official [Astro routing](https://docs.astro.build/en/guides/routing/), [content collections](https://docs.astro.build/en/guides/content-collections/), [styling](https://docs.astro.build/en/guides/styling/), and [GitHub Pages deployment](https://docs.astro.build/en/guides/deploy/github/) guides for framework changes.
