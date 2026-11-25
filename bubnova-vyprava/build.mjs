// Zabalí index.html (fragment pre Claude artifact) do samostatnej aplikácie v priečinku www/.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync } from 'node:fs';
const page = readFileSync('index.html', 'utf8');
mkdirSync('www', { recursive: true });
writeFileSync('www/index.html', `<!doctype html>
<html lang="sk">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#17143a">
<link rel="manifest" href="manifest.webmanifest">
<link rel="icon" href="icon-192.png">
<style>html{background:#17143a}body{margin:0;font:14px system-ui,sans-serif}img{max-width:100%}[hidden]{display:none!important}</style>
</head>
<body>
${page}
<script>if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});</script>
</body>
</html>
`);
for (const f of ['manifest.webmanifest', 'sw.js', 'icon-192.png', 'icon-512.png']) copyFileSync(f, 'www/' + f);
console.log('www/ je pripravené');
