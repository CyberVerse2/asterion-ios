const baseUrl = process.env.SMOKE_BASE_URL ?? "http://127.0.0.1:3001";

async function assertStatus(path, expectedStatus, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, options);
  if (response.status !== expectedStatus) {
    const body = await response.text();
    throw new Error(`Expected ${expectedStatus} for ${path}, got ${response.status}. Body: ${body}`);
  }
}

async function run() {
  await assertStatus("/health", 200);
  await assertStatus("/me", 401);
  await assertStatus("/me/progress", 401);
  console.log(`Smoke tests passed against ${baseUrl}`);
}

run().catch((error) => {
  console.error(error);
  process.exit(1);
});
