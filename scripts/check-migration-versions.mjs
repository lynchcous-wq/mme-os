import { readdirSync } from "node:fs";
import { join } from "node:path";

const directory = join(process.cwd(), "supabase", "migrations");
const files = readdirSync(directory).filter((file) => file.endsWith(".sql"));
const versions = new Map();
let failed = false;

for (const file of files) {
  const match = /^(\d{14})_[a-z0-9_-]+\.sql$/i.exec(file);
  if (!match) {
    console.error(`Invalid migration filename: ${file}`);
    failed = true;
    continue;
  }
  const version = match[1];
  const previous = versions.get(version);
  if (previous) {
    console.error(`Duplicate migration version ${version}: ${previous} and ${file}`);
    failed = true;
  } else {
    versions.set(version, file);
  }
}

if (files.length === 0) {
  console.error("No SQL migrations found.");
  failed = true;
}

if (failed) process.exit(1);
console.log(`Migration filename check passed: ${files.length} unique versions.`);
