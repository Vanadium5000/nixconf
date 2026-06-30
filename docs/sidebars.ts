import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';

const sidebars: SidebarsConfig = {
  mainSidebar: [
    'intro',
    {
      type: 'category',
      label: 'Operations',
      items: [
        'operations/repository',
        'operations/public-routes',
      ],
    },
  ],
};

export default sidebars;
