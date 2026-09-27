// Run with Playwright available on NODE_PATH. No network is needed by the chart.
const { chromium } = require('playwright');
const { pathToFileURL } = require('node:url');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({ headless: true,
    ...(process.env.PLOT_TEST_BROWSER ? { executablePath: process.env.PLOT_TEST_BROWSER } : {}) });
  try {
    const page = await browser.newPage({ viewport: { width: 1200, height: 850 } });
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route(/^https?:/, route => route.abort());
    await page.goto(pathToFileURL(path.resolve(process.argv[2])).href);
    await page.waitForSelector('#chart svg');
    const before = await page.locator('#chart').innerHTML();
    await page.mouse.move(550, 350);
    await page.mouse.wheel(0, -300);
    await page.waitForTimeout(400);
    if (before === await page.locator('#chart').innerHTML()) throw Error('Axis zoom did not change chart');
    await page.screenshot({path: process.argv[3]});
    if (errors.length) throw Error(errors.join('\n'));
    console.log('PASS: offline browser chart renders and wheel zoom updates axes without page errors');
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
