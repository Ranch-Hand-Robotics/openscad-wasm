/**
 * OpenSCAD WASM CLI - Main logic
 * Import this from cli-init.ts to ensure proper environment setup
 */

import * as fs from "https://deno.land/std@0.208.0/fs/mod.ts";
import { resolve, dirname } from "https://deno.land/std@0.208.0/path/mod.ts";

// Import the fonts module using the web version since it's ES6
import { addFonts } from "./build/openscad.fonts.js";

// Create a dynamic import wrapper for the Node.js build
async function loadOpenSCAD() {
  // For Node.js builds, we need to use dynamic import or read and eval
  // Instead, let's use the web version which works in Deno
  const { default: OpenScadWeb } = await import("./build/openscad.wasm.js");
  return OpenScadWeb;
}

export async function main() {
  const args = Deno.args;

  if (args.length === 0) {
    console.error("Usage: openscad-cli <input.scad> [options]");
    console.error("Example: openscad-cli cube.scad -o cube.stl");
    Deno.exit(1);
  }

  // Load OpenSCAD WASM
  console.log("[*] Loading OpenSCAD WASM...");
  const OpenScad = await loadOpenSCAD();

  // Initialize the WASM instance
  console.log("[*] Initializing OpenSCAD WASM...");
  
  const instance = await OpenScad({ 
    noInitialRun: true,
    print: (text: string) => console.log(text),
    printErr: (text: string) => console.error(text),
    locateFile: (filename: string) => {
      // Help the WASM module find its dependencies
      return "./build/" + filename;
    }
  });

  // Add fonts support
  addFonts(instance);

  // Process input file
  const inputFile = args[0];
  const fullInputPath = resolve(inputFile);

  console.log(`[*] Loading: ${inputFile}`);

  // Read the input file from the host filesystem
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
      const outputPath = resolve(outputFile.startsWith("/") ? outputFile.substring(1) : outputFile);

      try {
        const outputData = instance.FS.readFile(outputFile);
        await Deno.writeFile(outputPath, new Uint8Array(outputData));
        console.log(`[*] Output written to: ${outputPath}`);
      } catch (e) {
        console.error(`[!] Failed to read output from WASM FS: ${e.message}`);
      }
    }

    Deno.exit(exitCode);
  } catch (error) {
    console.error(`[!] Error: ${error.message}`);
    Deno.exit(1);
  }
}
