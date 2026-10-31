import { cp, mkdir, rm, writeFile } from "node:fs/promises";
import { resolve } from "node:path";

const root = resolve(".");
const out = resolve(root, "dist");
await rm(out, { recursive: true, force: true });
await mkdir(out, { recursive: true });
for (const file of ["index.html", "styles.css", "app.js"]) {
  await cp(resolve(root, file), resolve(out, file));
}
const config = {
  supabaseUrl: process.env.SUPABASE_URL || "",
  supabaseKey: process.env.SUPABASE_PUBLISHABLE_KEY || process.env.SUPABASE_ANON_KEY || ""
};
await writeFile(resolve(out, "config.js"), "window.VIALSEG_INVENTORY_CONFIG = " + JSON.stringify(config) + ";\n", "utf8");
console.log("Sitio compilado en dist/");
