import { defineConfig } from 'vite';
import { exportApi } from './scripts/exportApi';

export default defineConfig({ plugins: [exportApi()] });
