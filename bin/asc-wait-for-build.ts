// Poll App Store Connect until the specified build version (CFBundleVersion)
// for ExpressCharge is in `processingState=VALID`, then exit 0. Times out
// after 15 minutes (App Store processing usually finishes in 3-8 min).
//
// Usage: deno run --allow-read=KEY_PATH --allow-net=api.appstoreconnect.apple.com \
//   bin/asc-wait-for-build.ts <buildVersion>
//
// Env vars consumed (so the shell script holds the secrets):
//   ASC_API_KEY_PATH, ASC_API_KEY_ID, ASC_API_ISSUER_ID, ASC_APP_ID

const buildVersion = Deno.args[0];
if (!buildVersion) {
  console.error("usage: asc-wait-for-build.ts <buildVersion>");
  Deno.exit(2);
}

const KEY_PATH = Deno.env.get("ASC_API_KEY_PATH")!;
const KEY_ID = Deno.env.get("ASC_API_KEY_ID")!;
const ISSUER_ID = Deno.env.get("ASC_API_ISSUER_ID")!;
const APP_ID = Deno.env.get("ASC_APP_ID")!;

async function jwt(): Promise<string> {
  const pem = await Deno.readTextFile(KEY_PATH);
  const body = pem.replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", der.buffer,
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"],
  );
  const header = { alg: "ES256", kid: KEY_ID, typ: "JWT" };
  const payload = {
    iss: ISSUER_ID,
    exp: Math.floor(Date.now() / 1000) + 1200,
    aud: "appstoreconnect-v1",
  };
  const b64u = (s: string) =>
    btoa(s).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
  const input = `${b64u(JSON.stringify(header))}.${b64u(JSON.stringify(payload))}`;
  const sig = new Uint8Array(
    await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(input),
    ),
  );
  let bin = "";
  for (const b of sig) bin += String.fromCharCode(b);
  return `${input}.${
    btoa(bin).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "")
  }`;
}

async function fetchBuild(): Promise<{
  state: string;
  uploaded: string;
} | null> {
  const token = await jwt();
  const url =
    `https://api.appstoreconnect.apple.com/v1/builds?filter%5Bapp%5D=${APP_ID}&filter%5Bversion%5D=${buildVersion}&sort=-uploadedDate&limit=1`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    console.error(`ASC API ${res.status}: ${await res.text()}`);
    return null;
  }
  const json = await res.json();
  const build = json.data?.[0];
  if (!build) return null;
  return {
    state: build.attributes.processingState,
    uploaded: build.attributes.uploadedDate,
  };
}

const DEADLINE = Date.now() + 15 * 60_000;
let lastState = "";
while (Date.now() < DEADLINE) {
  const info = await fetchBuild();
  if (info) {
    if (info.state !== lastState) {
      console.log(
        `  [${new Date().toLocaleTimeString()}] build ${buildVersion}: ${info.state}`,
      );
      lastState = info.state;
    }
    if (info.state === "VALID") Deno.exit(0);
    if (info.state === "FAILED" || info.state === "INVALID") {
      console.error(`build ${buildVersion} processing failed`);
      Deno.exit(1);
    }
  } else if (lastState === "") {
    process.stdout?.write?.(".") ?? Deno.stdout.writeSync(new TextEncoder().encode("."));
  }
  await new Promise((r) => setTimeout(r, 15_000));
}
console.error(`timed out waiting for build ${buildVersion}`);
Deno.exit(1);
