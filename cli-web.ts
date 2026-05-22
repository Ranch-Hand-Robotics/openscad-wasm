#!/usr/bin/env deno
/**
 * OpenSCAD WASM CLI - Web-based approach with local testing
 * 
 * This version uses the web build which already exists
 */

import { resolve } from "https://deno.land/std@0.208.0/path/mod.ts";

// Comprehensive browser environment setup BEFORE any imports
declare global {
  var window: any;
  var document: any;
  var navigator: any;
  var XMLHttpRequest: any;
}

// Set up window as global context
globalThis.window = globalThis;
globalThis.document = {
  createElement: () => ({}),
  getElementsByTagName: () => [],
};
globalThis.navigator = {
  userAgent: "OpenSCAD WASM CLI"
};

// Create a simple fetch implementation for local files
globalThis.fetch = async (url: string) => {
  try {
    if (url.startsWith("file://") || url.startsWith("./")) {
      const filePath = url.replace("file://", "").replace(/^\.\//, "");
      const fullPath = resolve(filePath);
      const data = await Deno.readFile(fullPath);
      return {
        ok: true,
        arrayBuffer: async () => data.buffer,
        text: async () => new TextDecoder().decode(data),
      } as any;
    }
  } catch (e) {
    throw new Error(`Failed to fetch ${url}: ${e.message}`);
  }
  throw new Error(`Unsupported fetch: ${url}`);
};

console.log("[*] Browser environment configured");

// NOW import the web version
import OpenScad from "./build/openscad.js";
import { addFonts } from "./build/openscad.fonts.js";

async function main() {
  const args = Deno.args;

  if (args.length === 0) {
    console.error("Usage: openscad-cli <input.scad> [options]");
    console.error("Example: openscad-cli cube.scad -o cube.stl");
    Deno.exit(1);
  }

  // Initialize the WASM instance
  console.log("[*] Initializing OpenSCAD WASM...");

  const instance = await OpenScad({
    noInitialRun: true,
    print: (text: string) => console.log(text),
    printErr: (text: string) => console.error(text),
    locateFile: (filename: string) => "./build/" + filename,
  });

  // Add fonts support
  addFonts(instance);

  // Process input file
  const inputFile = args[0];
  const fullInputPath = resolve(inputFile);

  console.log(`[*] Loading: ${inputFile}`);

  try {
    const fileContent = await Deno.readFile(fullInputPath);

    // Write to WASM virtual filesystem
    const wasmInputPath = "/" + inputFile.split(/[\\\/]/).pop();
    instance.FS.writeFile(wasmInputPath, fileContent);
    console.log(`[*] File written to WASM FS: ${wasmInputPath}`);

    // Build the command arguments for WASM
    const wasmArgs = [wasmInputPath, ...args.slice(1)];
    console.log(`[*] Running: openscad ${wasmArgs.join(" ")}`);
    console.log("---");

    // Run OpenSCAD
    const exitCode = instance.callMain(wasmArgs);

    console.log("---");
    console.log(`[*] OpenSCAD exited with code: ${exitCode}`);

    // Handle output file if specified
    const outputIndex = wasmArgs.indexOf("-o");
    if (outputIndex !== -1 && outputIndex + 1 < wasmArgs.length) {
      const outputFile = wasmArgs[outputIndex + 1];
      const outputPath = resolve(
        outputFile.startsWith("/") ? outputFile.substring(1) : outputFile
      );

      try {
        const outputData = instance.FS.readFile(outputFile);
        await Deno.writeFile(outputPath, new Uint8Array(outputData));
        console.log(`[*] Output written to: ${outputPath}`);
        console.log(`[*] File size: ${outputData.length} bytes`);
      } catch (e) {
        console.error(`[!] Failed to read output from WASM FS: ${e.message}`);
        Deno.exit(1);
      }
    }

    Deno.exit(exitCode);
  } catch (error) {
    console.error(`[!] Error: ${error.message}`);
    Deno.exit(1);
  }
}

if (import.meta.main) {
  await main();
}
