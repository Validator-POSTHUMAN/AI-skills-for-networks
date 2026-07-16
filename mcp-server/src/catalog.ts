import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import { dirname, extname, posix, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

export interface SkillEntry {
  id: string;
  title: string;
  category: string;
  path: string;
  description: string;
}

interface CatalogDocument {
  version: number;
  skills: SkillEntry[];
}

const MAX_FILE_BYTES = 256 * 1024;
const ALLOWED_EXTENSIONS = new Set([".md", ".json", ".yaml", ".yml", ".txt", ".sh", ".js", ".ts"]);
const ALLOWED_TOP_LEVEL = new Set(["SKILL.md", "assets", "evals", "examples", "references", "scripts", "templates"]);

export function repositoryRoot(): string {
  return resolve(dirname(fileURLToPath(import.meta.url)), "../../..");
}

export async function loadCatalog(root = repositoryRoot()): Promise<CatalogDocument> {
  const parsed = JSON.parse(await readFile(resolve(root, "catalog.json"), "utf8")) as CatalogDocument;
  if (parsed.version !== 1 || !Array.isArray(parsed.skills) || parsed.skills.length === 0) {
    throw new Error("Unsupported or empty catalog");
  }

  const ids = new Set<string>();
  for (const entry of parsed.skills) {
    if (!/^[a-z0-9][a-z0-9-]*$/.test(entry.id) || ids.has(entry.id)) {
      throw new Error(`Invalid or duplicate skill id: ${entry.id}`);
    }
    if (entry.path !== entry.id || entry.path.includes("..") || entry.path.includes("/")) {
      throw new Error(`Unsafe skill path: ${entry.path}`);
    }
    ids.add(entry.id);
  }
  return parsed;
}

function validateRelativeFile(file: string): string {
  if (!file || file.includes("\\") || file.startsWith("/") || file.includes("\0")) {
    throw new Error("Invalid public file path");
  }
  const normalized = posix.normalize(file);
  const parts = normalized.split("/");
  if (normalized === "." || normalized.startsWith("../") || parts.includes("..") || !ALLOWED_TOP_LEVEL.has(parts[0])) {
    throw new Error("File is outside the public skill package");
  }
  if (!ALLOWED_EXTENSIONS.has(extname(normalized).toLowerCase())) {
    throw new Error("File type is not public");
  }
  return normalized;
}

export async function readSkillFile(root: string, entry: SkillEntry, file = "SKILL.md"): Promise<string> {
  const relative = validateRelativeFile(file);
  const packageDir = resolve(root, entry.path);
  const target = resolve(packageDir, relative);
  const unresolvedStat = await lstat(target);
  if (unresolvedStat.isSymbolicLink()) {
    throw new Error("Symbolic links are not public catalog files");
  }
  const packageReal = await realpath(packageDir);
  const targetReal = await realpath(target);
  if (targetReal !== packageReal && !targetReal.startsWith(`${packageReal}${sep}`)) {
    throw new Error("Resolved file escaped the public skill package");
  }
  const stat = await lstat(targetReal);
  if (!stat.isFile() || stat.size > MAX_FILE_BYTES) {
    throw new Error("Public file is unavailable or too large");
  }
  return readFile(targetReal, "utf8");
}

async function walkPublicFiles(base: string, current: string, depth: number): Promise<string[]> {
  if (depth > 4) return [];
  const result: string[] = [];
  for (const item of await readdir(current, { withFileTypes: true })) {
    if (item.isSymbolicLink()) continue;
    const absolute = resolve(current, item.name);
    const relative = absolute.slice(base.length + 1).split(sep).join("/");
    if (item.isDirectory()) {
      result.push(...await walkPublicFiles(base, absolute, depth + 1));
    } else if (item.isFile() && ALLOWED_EXTENSIONS.has(extname(item.name).toLowerCase())) {
      result.push(validateRelativeFile(relative));
    }
  }
  return result;
}

export async function listSkillFiles(root: string, entry: SkillEntry): Promise<string[]> {
  const packageDir = await realpath(resolve(root, entry.path));
  const files = await walkPublicFiles(packageDir, packageDir, 0);
  return files.sort();
}
