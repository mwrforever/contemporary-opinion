// 任务模块 V2 设计稿截图脚本：用本机 Edge 无头渲染，输出整板浅/深两版 + 6 个分屏图
const fs = require('fs');
const path = require('path');
const { chromium } = require('C:/Users/Lenovo/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/playwright-core');

const ROOT = __dirname;
const OUT = path.join(ROOT, 'shots');
const URL = 'file:///' + path.join(ROOT, 'index.html').replace(/\\/g, '/');

// 待截图的 7 个分屏 frame id
const FRAMES = [
  'scr-tasks', 'scr-select', 'scr-voice',
  'scr-voice-rec', 'scr-detail', 'scr-edit', 'scr-bell',
];

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch({
    executablePath: 'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
    headless: true,
  });
  const page = await browser.newPage({ viewport: { width: 1460, height: 3200 }, deviceScaleFactor: 1.5 });
  await page.goto(URL, { waitUntil: 'load' });
  await page.waitForTimeout(800);

  // 整板浅色
  await page.screenshot({ path: path.join(OUT, 'board-light.png'), fullPage: true });
  // 整板深色
  await page.click('#themeToggle');
  await page.waitForTimeout(500);
  await page.screenshot({ path: path.join(OUT, 'board-dark.png'), fullPage: true });
  // 回到浅色后逐个截分屏
  await page.click('#themeToggle');
  await page.waitForTimeout(400);
  for (const id of FRAMES) {
    await page.locator('#' + id).screenshot({ path: path.join(OUT, id + '.png') });
  }
  await browser.close();
  console.log('截图完成：' + OUT);
})();
