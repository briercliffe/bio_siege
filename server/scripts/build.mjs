// Bundles src/main.ts into the single build/index.js Nakama loads.
// Nakama statically parses the script: InitModule and every function passed to
// initializer.registerRpc(...) must be top-level declarations, so the bundle is flat (cjs, no IIFE).
// The stub below only satisfies esbuild's trailing `module.exports = ...`.
import { build } from "esbuild";

await build({
  entryPoints: ["src/main.ts"],
  bundle: true,
  format: "cjs",
  banner: { js: "var module = { exports: {} };" },
  target: "es2015",
  outfile: "build/index.js",
  logLevel: "info",
});
