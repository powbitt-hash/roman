// Zabalí index.html (fragment pre Claude artifact) do samostatnej aplikácie v priečinku www/.
// Samostatná verzia nepotrebuje sieť: písma sú pribalené, zdieľané funkcie Claude sa samy skryjú.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, readdirSync } from 'node:fs';
const page = readFileSync('index.html', 'utf8').replace(/<link [^>]*id="webfonts"[^>]*>\n?/, '')
  .replace('__VERZIA__', process.env.BUILD_VERSION || 'vývojová');
const fonts = readFileSync('fonts/fonts.css', 'utf8');
mkdirSync('www/fonts', { recursive: true });
writeFileSync('www/index.html', `<!doctype html>
<html lang="sk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#17143a">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="icon-192.png">
<style>${fonts}html{background:#17143a}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
${page}
<script>if (!window.Capacitor && 'serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});</script>
</body>
</html>
`);
for (const f of ['manifest.webmanifest', 'sw.js', 'icon-192.png', 'icon-512.png']) copyFileSync(f, 'www/' + f);
for (const f of readdirSync('fonts')) if (f.endsWith('.woff2')) copyFileSync('fonts/' + f, 'www/fonts/' + f);
console.log('www/ je pripravené');
