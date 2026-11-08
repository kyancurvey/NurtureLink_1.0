// Copies the licence text shipped with the bundled font packages into ./licenses
// so the licence of the exact files in use stays in the repo (spec 5.1).
import { copyFileSync, existsSync, mkdirSync } from 'node:fs';

const fonts = [
  ['open-sans', 'node_modules/@fontsource/open-sans/LICENSE'],
  ['roboto', 'node_modules/@fontsource/roboto/LICENSE'],
];

mkdirSync('licenses', { recursive: true });
for (const [name, source] of fonts) {
  if (existsSync(source)) {
    copyFileSync(source, `licenses/${name}-LICENSE.txt`);
  } else {
    console.warn(`Licence file not found: ${source}`);
  }
}
