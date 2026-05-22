#!/usr/bin/env deno
/**
 * OpenSCAD WASM CLI Init
 * 
 * Sets up browser environment shim before loading WASM module
 * Usage: deno run --allow-read --allow-write --allow-env cli-init.ts cube.scad -o cube.stl
 */

// Shim browser globals for Deno - MUST be before importing the WASM module
if (typeof globalThis !== 'undefined') {
  if (!globalThis.window) {
    (globalThis as any).window = globalThis;
  }
  if (!globalThis.document) {
    (globalThis as any).document = {};
  }
  if (!globalThis.navigator) {
    (globalThis as any).navigator = {
      userAgent: "OpenSCAD WASM CLI (Deno)"
    };
  }
}

import { main } from "./cli.ts";
await main();
