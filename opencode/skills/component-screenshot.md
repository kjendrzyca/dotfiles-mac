---
name: component-screenshot
description: Take clean, isolated screenshots of specific UI components from a running web app. Use when the user needs a pretty screenshot of a section, card, modal, or any DOM element — cropped with no surrounding chrome.
---

# Component Screenshot

Take production-quality retina screenshots of isolated UI components from a running web app using Playwright.

**Important:** Do NOT use `agent-browser` for screenshots — its `set viewport ... 2` flag does not actually capture at 2x resolution. Use Playwright directly with `deviceScaleFactor: 2` in the browser context, which produces true retina screenshots (2x pixel dimensions).

## Quick Reference

Write and run a Node.js script using `@playwright/test` (or `playwright` if installed). The script should:

1. Launch a headed browser with `deviceScaleFactor: 2` and a narrow viewport (~600px)
2. Navigate to the page (handle auth if needed)
3. Isolate the target element by replacing `document.body` contents
4. Resize the viewport to fit the element
5. Take a full-page screenshot

```javascript
const { chromium } = require('@playwright/test');
const fs = require('fs');

(async () => {
  const browser = await chromium.launch({ headless: false });
  const ctx = await browser.newContext({
    viewport: { width: 600, height: 1400 },
    deviceScaleFactor: 2,
  });
  const page = await ctx.newPage();

  // 1. Navigate to the page
  await page.goto('http://localhost:3001/some-page');
  await page.waitForLoadState('networkidle');

  // 2. Isolate the target element
  await page.evaluate(() => {
    // Find the element — adapt the selector to your case
    const sections = document.querySelectorAll('section, .card, [class*="section"]');
    for (const s of sections) {
      const title = s.querySelector('h1, h2, h3, [class*="title"]');
      if (title && title.textContent.includes('TARGET TEXT')) {
        document.body.innerHTML = '';
        document.body.style.padding = '20px';
        document.body.style.background = '#1a1a1a';
        document.body.appendChild(s);
        break;
      }
    }
  });
  await page.waitForTimeout(500);

  // 3. Resize viewport to fit the element
  const box = await page.evaluate(() => {
    const el = document.querySelector('section') || document.querySelector('.card') || document.body.firstElementChild;
    const r = el.getBoundingClientRect();
    return { width: Math.ceil(r.width + 60), height: Math.ceil(r.height + 60) };
  });
  await page.setViewportSize({ width: box.width, height: box.height });
  await page.waitForTimeout(300);

  // 4. Capture
  await page.screenshot({ path: 'screenshot.png', fullPage: true });

  await browser.close();
})();
```

## Finding the Right Element

Adapt the `page.evaluate` selector to your case:

```javascript
// By heading text
const sections = document.querySelectorAll('section, [class*="section"]');
for (const s of sections) {
  const title = s.querySelector('h1, h2, h3, [class*="title"]');
  if (title && title.textContent.includes('API Token')) {
    // use s
  }
}

// By test ID
const el = document.querySelector('[data-testid="my-component"]');

// By class name
const el = document.querySelector('.my-component');
```

## Advanced Options

### Dark/light mode
```javascript
// Force dark mode before isolating
await page.evaluate(() => {
  document.documentElement.setAttribute('data-theme', 'dark');
});
// Or use Playwright's color scheme
const ctx = await browser.newContext({
  colorScheme: 'dark',
  deviceScaleFactor: 2,
  viewport: { width: 600, height: 1400 },
});
```

### Custom background
```javascript
// Set in the isolation step
document.body.style.background = '#0d1117'; // GitHub dark
```

### Multiple components in one shot
```javascript
await page.evaluate(() => {
  const container = document.createElement('div');
  container.style.display = 'flex';
  container.style.flexDirection = 'column';
  container.style.gap = '20px';

  const els = document.querySelectorAll('.card');
  els.forEach(el => container.appendChild(el.cloneNode(true)));

  document.body.innerHTML = '';
  document.body.style.padding = '20px';
  document.body.style.background = '#1a1a1a';
  document.body.appendChild(container);
});
```

### Higher density (3x)
```javascript
const ctx = await browser.newContext({
  deviceScaleFactor: 3,
  viewport: { width: 600, height: 1400 },
});
```

## Verify Output

After capturing, confirm pixel dimensions are 2x the viewport:

```bash
sips -g pixelWidth -g pixelHeight screenshot.png
# A 600px viewport at 2x should produce pixelWidth: 1200
```
