import assert from "node:assert/strict";
import { test } from "node:test";
import { listSkillFiles, loadCatalog, readSkillFile, repositoryRoot } from "../src/catalog.js";

test("catalog contains public network and operations skills", async () => {
  const catalog = await loadCatalog();
  assert.equal(catalog.version, 1);
  assert.ok(catalog.skills.length >= 18);
  assert.ok(catalog.skills.some((entry) => entry.category === "network"));
  assert.ok(catalog.skills.some((entry) => entry.category === "operations"));
});

test("catalog only serves bounded package files", async () => {
  const catalog = await loadCatalog();
  const entry = catalog.skills.find((item) => item.id === "validator-upgrade");
  assert.ok(entry);
  assert.match(await readSkillFile(repositoryRoot(), entry), /validator upgrade/i);
  assert.ok((await listSkillFiles(repositoryRoot(), entry)).includes("SKILL.md"));
  await assert.rejects(() => readSkillFile(repositoryRoot(), entry, "../LICENSE"));
  await assert.rejects(() => readSkillFile(repositoryRoot(), entry, "/etc/passwd"));
});

test("exported operations skills contain no private workspace identifiers", async () => {
  const catalog = await loadCatalog();
  const forbidden = /(?:\b10\.\d{1,3}\.\d{1,3}\.\d{1,3}\b|\b192\.168\.\d{1,3}\.\d{1,3}\b|\b172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}\b|https?:\/\/[^/\s]*\.internal\b|-----BEGIN (?:OPENSSH|EC|RSA) PRIVATE KEY-----)/i;
  for (const entry of catalog.skills.filter((item) => item.category === "operations")) {
    for (const file of await listSkillFiles(repositoryRoot(), entry)) {
      assert.doesNotMatch(await readSkillFile(repositoryRoot(), entry, file), forbidden, `${entry.id}/${file}`);
    }
  }
});
