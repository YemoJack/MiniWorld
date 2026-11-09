import { existsSync, readdirSync } from 'node:fs';
import { defineConfig } from 'vite';

export default defineConfig(({ command }) => {
  const directory = new URL('./local-assets/models/', import.meta.url);
  const files = command === 'serve' && existsSync(directory) ? readdirSync(directory) : [];
  return {
    base: './',
    define: { __LOCAL_MODEL_FILES__: JSON.stringify(files) },
  };
});
