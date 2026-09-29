// @ts-check
import { defineConfig } from 'astro/config';
import { unified } from '@astrojs/markdown-remark';
import starlight from '@astrojs/starlight';

const base = '/Gala-Engine';

/** Prefix root-relative Markdown links with the GitHub Pages base path. */
function baseLinks() {
	const walk = (node) => {
		if ((node.type === 'link' || node.type === 'image') && node.url.startsWith('/') && !node.url.startsWith('//') && !node.url.startsWith(base + '/')) {
			node.url = base + node.url;
		}
		node.children?.forEach(walk);
	};
	return (tree) => walk(tree);
}

export default defineConfig({
	site: 'https://shlok-bhakta.github.io',
	base,
	trailingSlash: 'always',
	markdown: { processor: unified({ remarkPlugins: [baseLinks] }) },
	integrations: [
		starlight({
			title: 'Gala',
			description:
				'Build iPhone and iPad apps from Linux on your own Mac, and install every new build with one tap over your private tailnet.',
			logo: { src: './src/assets/gala-icon.svg', alt: 'Gala' },
			favicon: '/favicon.svg',
			customCss: ['./src/styles/theme.css'],
			social: [{ icon: 'github', label: 'GitHub', href: 'https://github.com/Shlok-Bhakta/Gala-Engine' }],
			editLink: { baseUrl: 'https://github.com/Shlok-Bhakta/Gala-Engine/edit/main/website/' },
			lastUpdated: true,
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://shlok-bhakta.github.io/Gala-Engine/og.png' } },
				{ tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
				{ tag: 'meta', attrs: { name: 'theme-color', content: '#0b0b0c' } },
			],
			sidebar: [
				{
					label: 'Getting started',
					items: [
						{ label: 'Introduction', slug: 'getting-started/introduction' },
						{ label: 'Quickstart', slug: 'getting-started/quickstart' },
						{ label: 'How Gala works', slug: 'getting-started/how-it-works' },
					],
				},
				{
					label: 'Setup',
					items: [
						{ label: 'Mac build worker', slug: 'setup/mac-worker' },
						{ label: 'Signing and profiles', slug: 'setup/signing' },
						{ label: 'Client machines', slug: 'setup/client' },
						{ label: 'iPhone and iPad', slug: 'setup/devices' },
					],
				},
				{
					label: 'Tutorials',
					items: [
						{ label: 'Your first SwiftUI app', slug: 'tutorials/first-swiftui-app' },
						{ label: 'UIKit without Xcode', slug: 'tutorials/uikit-without-xcode' },
						{ label: 'An existing Xcode project', slug: 'tutorials/xcode-project' },
						{ label: 'Deliver on every save', slug: 'tutorials/continuous-delivery' },
						{ label: 'USB install from Linux', slug: 'tutorials/usb-install' },
					],
				},
				{
					label: 'Guides',
					items: [
						{ label: 'Build recipes', slug: 'guides/recipes' },
						{ label: 'Delivery and installs', slug: 'guides/delivery' },
						{ label: 'The Gala app', slug: 'guides/gala-app' },
					],
				},
				{
					label: 'Reference',
					items: [
						{ label: 'CLI', slug: 'reference/cli' },
						{ label: 'Configuration', slug: 'reference/configuration' },
						{ label: 'Storage and ports', slug: 'reference/storage' },
						{ label: 'Security model', slug: 'reference/security' },
						{ label: 'Troubleshooting', slug: 'reference/troubleshooting' },
						{ label: 'FAQ', slug: 'reference/faq' },
						{ label: 'Changelog', slug: 'reference/changelog' },
					],
				},
			],
		}),
	],
});
