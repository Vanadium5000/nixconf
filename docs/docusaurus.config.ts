import type { Config } from '@docusaurus/types';
import type { Options, ThemeConfig } from '@docusaurus/preset-classic';
import { themes as prismThemes } from 'prism-react-renderer';

const config: Config = {
  title: 'Nixconf Docs',
  tagline: 'Operational notes for this NixOS fleet',
  favicon: 'img/favicon.svg',

  url: 'https://docs.local',
  baseUrl: '/',

  organizationName: 'matrix',
  projectName: 'nixconf',

  onBrokenLinks: 'throw',

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'warn',
    },
  },
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          routeBasePath: '/',
          sidebarPath: './sidebars.ts',
          editUrl: 'https://github.com/matrix/nixconf/tree/main/docs/',
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Options,
    ],
  ],

  themeConfig: {
    image: 'img/social-card.svg',
    navbar: {
      title: 'Nixconf Docs',
      logo: {
        alt: 'Nixconf Docs',
        src: 'img/logo.svg',
      },
      items: [
        {
          type: 'docSidebar',
          sidebarId: 'mainSidebar',
          position: 'left',
          label: 'Docs',
        },
        {
          href: 'https://github.com/facebook/docusaurus',
          label: 'Docusaurus',
          position: 'right',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Local references',
          items: [
            {
              label: 'Repository guide',
              to: '/operations/repository',
            },
            {
              label: 'Public routes',
              to: '/operations/public-routes',
            },
            {
              label: 'DNS recovery',
              to: '/operations/dns',
            },
          ],
        },
        {
          title: 'Upstream references',
          items: [
            {
              label: 'Docusaurus docs',
              href: 'https://docusaurus.io/docs',
            },
            {
              label: 'NixOS manual',
              href: 'https://nixos.org/manual/nixos/stable/',
            },
          ],
        },
      ],
      copyright: `Built from ./docs during NixOS rebuilds.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
  } satisfies ThemeConfig,
};

export default config;
