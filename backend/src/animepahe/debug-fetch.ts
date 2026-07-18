import puppeteer from "puppeteer-extra";
import StealthPlugin from "puppeteer-extra-plugin-stealth";
puppeteer.use(StealthPlugin());

async function main() {
  const browser = await puppeteer.launch({
    headless: false,
    userDataDir: "/tmp/animepahe-browser-profile",
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--window-size=1200,800"],
  });
  const page = await browser.newPage();

  console.log("Opening animepahe...");
  await page.goto("https://animepahe.pw/", { waitUntil: "domcontentloaded", timeout: 15000 });

  const title = await page.title();
  console.log("Page title:", title);

  // Check cookies
  const cookies = await page.cookies();
  console.log("\nCookies:");
  cookies.forEach(c => {
    if (c.domain?.includes("animepahe")) {
      console.log(" ", c.name, "=", c.value?.substring(0, 20) + "...");
    }
  });

  // Try calling API from the page context
  console.log("\nCalling API via page.evaluate...");
  const result = await page.evaluate(async () => {
    const resp = await fetch("/api?m=search&q=test", {
      credentials: "include",
      headers: { Accept: "application/json" },
    });
    const text = await resp.text();
    return {
      status: resp.status,
      ok: resp.ok,
      isCF: text.includes("Just a moment") || text.includes("Attention Required"),
      len: text.length,
      preview: text.substring(0, 300),
    };
  });
  console.log("Result:", JSON.stringify(result, null, 2));

  // Also try absolute URL
  console.log("\nCalling API with absolute URL...");
  const result2 = await page.evaluate(async () => {
    const resp = await fetch("https://animepahe.pw/api?m=search&q=test", {
      credentials: "include",
      headers: { Accept: "application/json" },
    });
    const text = await resp.text();
    return {
      status: resp.status,
      isCF: text.includes("Just a moment") || text.includes("Attention Required"),
      len: text.length,
      preview: text.substring(0, 100),
    };
  });
  console.log("Result:", JSON.stringify(result2, null, 2));

  // Try navigating directly to the API URL
  console.log("\nNavigating directly to API URL...");
  await page.goto("https://animepahe.pw/api?m=search&q=test", { waitUntil: "domcontentloaded", timeout: 10000 });
  const body = await page.evaluate(() => document.body.innerText);
  console.log("Direct nav body:", body.substring(0, 300));

  await browser.close();
}
main();
