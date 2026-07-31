#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(scriptPath), "../..");
const sourceRoot = path.join(root, "Sources", "PalmierPro");

function filesUnder(directory, suffix) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const child = path.join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(child, suffix) : entry.name.endsWith(suffix) ? [child] : [];
  });
}

function decodeSwiftLiteral(value) {
  return value
    .replaceAll("\\\"", "\"")
    .replaceAll("\\n", "\n")
    .replaceAll("\\t", "\t")
    .replaceAll("\\\\", "\\");
}

export function sourceKeys() {
  const keys = new Set();
  const pattern = /L10n\.key\("((?:\\.|[^"\\])*)"\)/g;

  for (const file of filesUnder(sourceRoot, ".swift")) {
    const source = fs.readFileSync(file, "utf8");
    for (const match of source.matchAll(pattern)) keys.add(decodeSwiftLiteral(match[1]));
  }

  return [...keys].sort();
}

function localizedSourceNames() {
  const names = new Set();
  const pattern = /L10n\.string\(\s*(?:#*)?"/;

  for (const file of filesUnder(sourceRoot, ".swift")) {
    if (!pattern.test(fs.readFileSync(file, "utf8"))) continue;
    const name = path.basename(file, ".swift");
    if (names.has(name)) throw new Error(`Duplicate Swift filename prevents localization sync: ${name}.swift`);
    names.add(name);
  }

  return [...names].sort();
}

function argumentValues(name) {
  const values = [];
  for (let index = 2; index < process.argv.length; index += 1) {
    if (process.argv[index] === name) {
      const value = process.argv[index + 1];
      if (!value) throw new Error(`${name} requires a value`);
      values.push(value);
      index += 1;
    }
  }
  return values;
}

function escapeStringsValue(value) {
  return value
    .replaceAll("\\", "\\\\")
    .replaceAll('"', '\\"')
    .replaceAll("\n", "\\n")
    .replaceAll("\r", "\\r")
    .replaceAll("\t", "\\t");
}

function synchronize() {
  const outputPaths = argumentValues("--output");
  const stringsDataPaths = argumentValues("--stringsdata");
  if (outputPaths.length !== 1) throw new Error("--output is required exactly once");
  if (stringsDataPaths.length === 0) throw new Error("at least one --stringsdata is required");

  const keys = new Set(sourceKeys());
  for (const stringsDataPath of stringsDataPaths) {
    const data = JSON.parse(fs.readFileSync(stringsDataPath, "utf8"));
    const entries = data.tables?.Localizable ?? [];
    if (entries.length === 0) {
      throw new Error(`${stringsDataPath} contains no compiler-extracted localization keys`);
    }
    for (const entry of entries) {
      if (!entry.key) throw new Error(`${stringsDataPath} contains an empty localization key`);
      keys.add(entry.key);
    }
  }

  const entries = [...keys]
    .sort()
    .map((key) => `"${escapeStringsValue(key)}" = "${escapeStringsValue(key)}";`);
  const output = [
    "/* Generated from app-owned UI copy. Translate values only in other locales. */",
    "",
    ...entries,
    "",
  ].join("\n");

  const outputPath = outputPaths[0];
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, output);
  console.log(`Synchronized ${keys.size} source strings.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === scriptPath) {
  if (process.argv.includes("--list-localized-source-names")) {
    for (const name of localizedSourceNames()) console.log(name);
  } else {
    synchronize();
  }
}
