// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import catppuccin from '@catppuccin/starlight';
import starlightImageZoom from 'starlight-image-zoom';

export default defineConfig({
  site: 'https://ghchinoy.github.io',
  base: '/sonosflow',
  integrations: [
    starlight({
      title: 'SonosFlow',
      description: 'Native macOS Sonos Controller powered by homectl MCP',
      logo: {
        src: './src/assets/app-icon.png',
      },
      plugins: [
        catppuccin({
          dark: { flavor: 'mocha', accent: 'sky' },
          light: { flavor: 'latte', accent: 'sky' },
        }),
        starlightImageZoom(),
      ],
      social: [
        {
          icon: 'github',
          label: 'GitHub',
          href: 'https://github.com/ghchinoy/sonos-swift-mcp',
        },
      ],
      sidebar: [
        {
          label: 'Getting Started',
          items: [
            { label: 'Introduction & Setup', slug: 'guides/getting-started' },
            { label: 'Complete User Guide', slug: 'guides/user-guide' },
          ],
        },
        {
          label: 'User Experience',
          items: [
            { label: 'Mode A MiniPlayer & Proxy Icon', slug: 'guides/miniplayer' },
            { label: 'Menu Bar Extra Companion', slug: 'guides/menubar' },
            { label: 'Media Keys, Streams & Volumes', slug: 'guides/media-controls' },
            { label: 'Internet Radio & Custom Presets', slug: 'guides/radio-presets' },
          ],
        },
        {
          label: 'Architecture Deep Dives',
          items: [
            { label: 'System Architecture', slug: 'architecture/overview' },
            { label: 'Direct MCP Integration', slug: 'architecture/mcp-protocol' },
            { label: 'Two-Tier Artwork Caching', slug: 'architecture/caching' },
            { label: 'Official Sonos 27mcp Comparison', slug: 'architecture/official-mcp-comparison' },
          ],
        },
        {
          label: 'Reference & Operations',
          items: [
            { label: 'Keyboard Shortcuts', slug: 'reference/keyboard-shortcuts' },
            { label: 'Configuration & Settings', slug: 'reference/configuration' },
            { label: 'Troubleshooting & Diagnostics', slug: 'reference/troubleshooting' },
          ],
        },
      ],
    }),
  ],
});
