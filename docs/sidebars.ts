import type { SidebarsConfig } from '@docusaurus/plugin-content-docs';
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';

type SidebarItem =
  | string
  | {
    type: 'category';
    label: string;
    collapsed?: boolean;
    link?: { type: 'doc'; id: string } | { type: 'link'; label: string; href: string };
    items: SidebarItem[];
  }
  | { type: 'link'; label: string; href: string };

type HeadingNode = {
  level: number;
  title: string;
  anchor: string;
  children: HeadingNode[];
};

const docsRoot = path.join(__dirname, 'docs');
const docExtensions: Record<string, true> = {
  '.md': true,
  '.mdx': true,
};

function titleCase(value: string): string {
  return value
    .split(/[-_\s]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join(' ');
}

function frontmatter(content: string): Record<string, string> {
  const match = content.match(/^---\n([\s\S]*?)\n---\n/);
  if (!match) return {};

  const result: Record<string, string> = {};
  for (const line of match[1].split('\n')) {
    const entry = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (!entry) continue;
    result[entry[1]] = entry[2].replace(/^['"]|['"]$/g, '').trim();
  }
  return result;
}

function stripFrontmatter(content: string): string {
  return content.replace(/^---\n[\s\S]*?\n---\n/, '');
}

function slugifyHeading(title: string): string {
  return title
    .toLowerCase()
    .replace(/[`*_~]/g, '')
    .replace(/<[^>]+>/g, '')
    .replace(/&[a-z0-9#]+;/gi, '')
    .replace(/[^\p{L}\p{N}\s-]/gu, '')
    .trim()
    .replace(/\s+/g, '-');
}

function docIdFor(filePath: string): string {
  const relative = path.relative(docsRoot, filePath);
  return relative.replace(/\.(md|mdx)$/i, '').split(path.sep).join('/');
}

function docRoute(docId: string, metadata: Record<string, string>): string {
  if (metadata.slug) return metadata.slug.startsWith('/') ? metadata.slug : `/${metadata.slug}`;
  return `/${docId}`;
}

function docTitle(filePath: string, metadata: Record<string, string>, content: string): string {
  if (metadata.title) return metadata.title;
  const heading = stripFrontmatter(content).match(/^#\s+(.+)$/m);
  if (heading) return heading[1].trim();
  return titleCase(path.basename(filePath).replace(/\.(md|mdx)$/i, ''));
}

function headingTree(content: string): HeadingNode[] {
  const root: HeadingNode[] = [];
  const stack: HeadingNode[] = [];
  const used = new Map<string, number>();

  for (const line of stripFrontmatter(content).split('\n')) {
    const match = line.match(/^(#{2,3})\s+(.+)$/);
    if (!match) continue;

    const level = match[1].length;
    const title = match[2].replace(/\s+#+$/, '').trim();
    const baseAnchor = slugifyHeading(title);
    const seen = used.get(baseAnchor) ?? 0;
    used.set(baseAnchor, seen + 1);
    const anchor = seen === 0 ? baseAnchor : `${baseAnchor}-${seen}`;
    const node: HeadingNode = { level, title, anchor, children: [] };

    while (stack.length > 0 && stack[stack.length - 1].level >= level) stack.pop();
    if (stack.length === 0) root.push(node);
    else stack[stack.length - 1].children.push(node);
    stack.push(node);
  }

  return root;
}

function headingItems(nodes: HeadingNode[], route: string): SidebarItem[] {
  return nodes.map((node) => {
    const link = {
      type: 'link' as const,
      label: node.title,
      href: `${route}#${node.anchor}`,
    };

    if (node.children.length === 0) return link;
    return {
      type: 'category' as const,
      label: node.title,
      link,
      collapsed: true,
      items: headingItems(node.children, route),
    };
  });
}

function docItem(filePath: string): SidebarItem {
  const content = readFileSync(filePath, 'utf8');
  const metadata = frontmatter(content);
  const id = docIdFor(filePath);
  const headings = headingTree(content);

  if (headings.length === 0) return id;

  return {
    type: 'category',
    label: docTitle(filePath, metadata, content),
    link: { type: 'doc', id },
    collapsed: true,
    items: headingItems(headings, docRoute(id, metadata)),
  };
}

function sidebarForDirectory(directory: string): SidebarItem[] {
  const entries = readdirSync(directory)
    .filter((name) => !name.startsWith('.'))
    .sort((a, b) => a.localeCompare(b));

  const docs: SidebarItem[] = [];
  const categories: SidebarItem[] = [];

  for (const entry of entries) {
    const entryPath = path.join(directory, entry);
    const stat = statSync(entryPath);

    if (stat.isDirectory()) {
      const items = sidebarForDirectory(entryPath);
      if (items.length === 0) continue;
      categories.push({
        type: 'category',
        label: titleCase(entry),
        collapsed: false,
        items,
      });
      continue;
    }

    if (stat.isFile() && docExtensions[path.extname(entry)]) {
      docs.push(docItem(entryPath));
    }
  }

  return [...docs, ...categories];
}

const sidebars: SidebarsConfig = {
  mainSidebar: (existsSync(docsRoot) ? sidebarForDirectory(docsRoot) : []) as SidebarsConfig['mainSidebar'],
};

export default sidebars;
