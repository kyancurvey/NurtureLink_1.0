// Public files (logo set) resolved against the Vite base so they also load on GitHub Pages and offline.
export const asset = (file) => `${import.meta.env.BASE_URL}${file}`;
