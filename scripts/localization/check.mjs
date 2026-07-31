#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { sourceKeys } from "./sync.mjs";

const scriptPath = fileURLToPath(import.meta.url);
const root = path.resolve(path.dirname(scriptPath), "../..");
const sourceRoot = path.join(root, "Sources", "PalmierPro");
const catalogRoot = path.join(sourceRoot, "Resources", "Localization");
const sourceLocale = "en";
const tableNames = ["Localizable", "InfoPlist"];
const errors = [];

function filesUnder(directory, suffix) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const child = path.join(directory, entry.name);
    return entry.isDirectory() ? filesUnder(child, suffix) : entry.name.endsWith(suffix) ? [child] : [];
  });
}

function relative(file) {
  return path.relative(root, file);
}

function lineNumber(source, index) {
  return source.slice(0, index).split("\n").length;
}

function placeholders(value) {
  const result = [];
  const pattern = /%%|%(?:\d+\$)?[-+#0 ']*\d*(?:\.\d+)?(?:hh|h|ll|l|L|z|t|j|q)?([@diuoxXfFeEgGaAcCsSp])/g;
  for (const match of value.matchAll(pattern)) {
    if (match[0] === "%%") continue;
    const type = match[1].toLowerCase();
    result.push("diuox".includes(type) ? "integer" : "fega".includes(type) ? "floating" : type);
  }
  return result.sort().join(",");
}

function parseStrings(file) {
  try {
    const output = execFileSync(
      "/usr/bin/plutil",
      ["-convert", "json", "-o", "-", file],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
    );
    const values = JSON.parse(output);
    if (Array.isArray(values) || values === null || typeof values !== "object") {
      throw new Error("expected a string dictionary");
    }
    for (const [key, value] of Object.entries(values)) {
      if (typeof value !== "string") throw new Error(`${JSON.stringify(key)} does not contain a string value`);
    }
    return new Map(Object.entries(values));
  } catch (error) {
    const detail = error.stderr?.trim() || error.message;
    errors.push(`${relative(file)}: ${detail}`);
    return null;
  }
}

let locales = [];
try {
  locales = fs.readdirSync(catalogRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory() && entry.name.endsWith(".lproj"))
    .map((entry) => entry.name.slice(0, -".lproj".length))
    .sort();
} catch (error) {
  errors.push(`${relative(catalogRoot)}: ${error.message}`);
}

if (!locales.includes(sourceLocale)) {
  errors.push(`${relative(catalogRoot)}: missing ${sourceLocale}.lproj source localization`);
}

const targetLocales = locales.filter((locale) => locale !== sourceLocale);
const sourceTables = new Map();

for (const tableName of tableNames) {
  const fileName = `${tableName}.strings`;
  const sourceFile = path.join(catalogRoot, `${sourceLocale}.lproj`, fileName);
  const sourceEntries = parseStrings(sourceFile) ?? new Map();
  sourceTables.set(tableName, sourceEntries);

  for (const [key, value] of sourceEntries) {
    if (!key) errors.push(`${relative(sourceFile)}: contains an empty key`);
    if (!value.trim()) {
      errors.push(`${relative(sourceFile)}: empty source value for ${JSON.stringify(key)}`);
    }
    if (tableName === "Localizable" && value !== key) {
      errors.push(`${relative(sourceFile)}: source value must match its key for ${JSON.stringify(key)}`);
    }
  }

  for (const locale of targetLocales) {
    const targetFile = path.join(catalogRoot, `${locale}.lproj`, fileName);
    const targetEntries = parseStrings(targetFile);
    if (!targetEntries) continue;

    for (const key of sourceEntries.keys()) {
      if (!targetEntries.has(key)) {
        errors.push(`${relative(targetFile)}: missing ${JSON.stringify(key)}`);
        continue;
      }
      const value = targetEntries.get(key);
      if (!value.trim()) {
        errors.push(`${relative(targetFile)}: empty translation for ${JSON.stringify(key)}`);
      } else if (placeholders(value) !== placeholders(sourceEntries.get(key))) {
        errors.push(`${relative(targetFile)}: incompatible placeholders for ${JSON.stringify(key)}`);
      }
    }

    for (const key of targetEntries.keys()) {
      if (!sourceEntries.has(key)) {
        errors.push(`${relative(targetFile)}: unknown key ${JSON.stringify(key)}`);
      }
    }
  }
}

const localizable = sourceTables.get("Localizable") ?? new Map();
for (const key of sourceKeys()) {
  if (!localizable.has(key)) {
    errors.push(`en.lproj/Localizable.strings: missing registered source key ${JSON.stringify(key)}`);
  }
}

function firstArgument(source, openIndex) {
  let depth = 1;
  let blockCommentDepth = 0;
  let state = "normal";
  let quoteLength = 0;
  for (let index = openIndex + 1; index < source.length; index += 1) {
    const current = source[index];
    const next = source[index + 1];

    if (state === "lineComment") {
      if (current === "\n") state = "normal";
      continue;
    }
    if (state === "blockComment") {
      if (current === "/" && next === "*") {
        blockCommentDepth += 1;
        index += 1;
      } else if (current === "*" && next === "/") {
        blockCommentDepth -= 1;
        index += 1;
        if (blockCommentDepth === 0) state = "normal";
      }
      continue;
    }
    if (state === "string") {
      if (current === "\\") {
        index += 1;
      } else if (quoteLength === 3 && source.slice(index, index + 3) === '"""') {
        index += 2;
        state = "normal";
      } else if (quoteLength === 1 && current === '"') {
        state = "normal";
      }
      continue;
    }

    if (current === "/" && next === "/") {
      state = "lineComment";
      index += 1;
    } else if (current === "/" && next === "*") {
      state = "blockComment";
      blockCommentDepth = 1;
      index += 1;
    } else if (source.slice(index, index + 3) === '"""') {
      state = "string";
      quoteLength = 3;
      index += 2;
    } else if (current === '"') {
      state = "string";
      quoteLength = 1;
    } else if (current === "(") {
      depth += 1;
    } else if (current === ")") {
      depth -= 1;
      if (depth === 0) return source.slice(openIndex + 1, index);
    } else if (current === "," && depth === 1) {
      return source.slice(openIndex + 1, index);
    }
  }
  return null;
}

const localizedAPIs = new Set([
  "Button", "ColorPicker", "ContentUnavailableView", "GroupBox", "Label", "LabeledContent",
  "Link", "Menu", "NavigationLink", "Picker", "ProgressView", "Section", "SecureField", "Text",
  "TextField", "Toggle", "accessibilityAction", "accessibilityHint", "accessibilityLabel",
  "accessibilityValue", "alert", "confirmationDialog", "help", "navigationTitle",
  "EditorPanelGroup", "GeneratingOverlay", "InspectorRow", "MediaPanelToast", "SettingsGroup",
  "SettingsSection", "SettingsToggleRow",
]);
const appKitAPIs = new Set(["NSMenu", "NSMenuItem", "addItem"]);

function checkUICalls(file, source) {
  const identifierPattern = /[A-Za-z_][A-Za-z0-9_]*/g;
  for (const match of source.matchAll(identifierPattern)) {
    const name = match[0];
    if (!localizedAPIs.has(name) && !appKitAPIs.has(name)) continue;
    let openIndex = match.index + name.length;
    while (/\s/.test(source[openIndex] ?? "")) openIndex += 1;
    if (source[openIndex] !== "(") continue;
    const argument = firstArgument(source, openIndex);
    if (argument === null || !/(?:#*)"/.test(argument)) continue;
    if (argument.includes("L10n.") || argument.includes("verbatim:") || argument.trim() === "String()") continue;
    if (name === "Section" && /^\s*id\s*:/.test(argument)) continue;
    if (name === "NSMenuItem" && !/^\s*title\s*:/.test(argument)) continue;
    if (name === "NSMenu" && !/^\s*title\s*:/.test(argument)) continue;
    if (name === "addItem" && !/^\s*withTitle\s*:/.test(argument)) continue;
    errors.push(`${relative(file)}:${lineNumber(source, match.index)}: ${name} contains an unclassified string literal`);
  }
}

function checkNamedUILiterals(file, source) {
  const patterns = [
    ["panel text", /\bpanel\.(?:message|prompt|title)\s*=\s*(?:#*)"/g],
    ["mediaPanelToast", /\b(?:[A-Za-z_][A-Za-z0-9_]*\.)?mediaPanelToast\s*=\s*(?:#*)"/g],
    ["deletionMessage", /\bdeletionMessage\s*=\s*(?:#*)"/g],
    ["submissionError", /\bsubmissionError\s*=\s*(?:#*)"/g],
  ];
  if (!file.includes(`${path.sep}Agent${path.sep}`)) {
    patterns.push(["labelHelp", /\blabelHelp\s*:\s*(?:#*)"/g]);
  }
  for (const [name, pattern] of patterns) {
    for (const match of source.matchAll(pattern)) {
      errors.push(`${relative(file)}:${lineNumber(source, match.index)}: ${name} contains an unclassified string literal`);
    }
  }
}

for (const file of filesUnder(sourceRoot, ".swift")) {
  const source = fs.readFileSync(file, "utf8");
  checkUICalls(file, source);
  checkNamedUILiterals(file, source);
  if (file.includes(`${path.sep}Agent${path.sep}Tools${path.sep}`) && source.includes("L10n.")) {
    errors.push(`${relative(file)}: Agent tool contracts must not use UI localization`);
  }
}

if (errors.length > 0) {
  for (const error of errors) console.error(`error: ${error}`);
  process.exit(1);
}

const stringCount = [...sourceTables.values()].reduce((sum, entries) => sum + entries.size, 0);
const localeSummary = targetLocales.join(", ") || "source language only";
console.log(`Localization checks passed: ${stringCount} strings; ${localeSummary}.`);
