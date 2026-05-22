import { assert, assertEquals, assertStringIncludes, assertNotEquals } from "https://deno.land/std@0.125.0/testing/asserts.ts";
import { dirname, fromFileUrl, join } from "https://deno.land/std/path/mod.ts";
import { loadTestFiles } from "./testing.ts";

import OpenScad, { OpenSCAD } from "../build/openscad.js";
import { addFonts } from "../build/openscad.fonts.js";
import { addMCAD } from "../build/openscad.mcad.js";

type MaterialDef = {
  pbrMetallicRoughness?: {
    baseColorFactor?: number[];
  };
  alphaMode?: string;
};

type GltfJson = {
  materials?: MaterialDef[];
};

const wasmTest = (name: string, fn: () => Promise<void> | void) =>
  Deno.test({
    name,
    sanitizeOps: false,
    sanitizeResources: false,
    fn,
  });

wasmTest("csg", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  await runTest(instance, "./csg");
});

wasmTest("cube", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  await runTest(instance, "./cube");
});

wasmTest("cylinder", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  await runTest(instance, "./cylinder");
});

wasmTest("lib", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  await runTest(instance, "./lib");
});

wasmTest("mcad", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  addMCAD(instance);
  await runTest(instance, "./mcad");
});

wasmTest("text", async () => {
  const instance = await OpenScad({ noInitialRun: true });
  addFonts(instance);
  await runTest(instance, "./text");
});

wasmTest("print stderr", async () => {
  let stderr = "";

  const instance = await OpenScad({ 
    noInitialRun: true,
    printErr: (text: string) => stderr += text + "\n",
   });
  await runTest(instance, "./cube");

  assertStringIncludes(stderr, "Facets:");
});

wasmTest("print stdout", async () => {
  let stdout = "";

  const instance = await OpenScad({ 
    noInitialRun: true,
    print: (text: string) => stdout += text + "\n",
   });
  await runTest(instance, "./cube", "-");

  assertNotEquals(stdout.length, 0);
});

wasmTest("glb export preserves colors and transparency", async () => {
  const instance = await OpenScad({ noInitialRun: true });

  const testScad = `
color([1, 0, 0])
cube([10, 10, 10]);

translate([15, 0, 0])
color([0, 1, 0], alpha=0.5)
sphere(r=8);

translate([30, 0, 0])
color([0, 0, 1], alpha=0.3)
cylinder(h=20, r=5, center=true);
`;

  instance.FS.writeFile("/test.scad", testScad);

  const code = instance.callMain(["/test.scad", "--export-format", "glb", "-o", "out.glb"]);
  assertEquals(0, code);

  const output = instance.FS.readFile("out.glb", { encoding: "binary" });
  const gltf = parseGlbJsonChunk(output);

  const materials = gltf.materials ?? [];
  assert(materials.length >= 3, "expected at least 3 materials in colored GLB output");

  const baseColors = materials
    .map((m) => m.pbrMetallicRoughness?.baseColorFactor)
    .filter((c: number[] | undefined): c is number[] => Array.isArray(c) && c.length === 4);

  assert(baseColors.some((c) => approximatelyColor(c, [1, 0, 0, 1])), "expected red material");
  assert(baseColors.some((c) => approximatelyColor(c, [0, 1, 0, 0.5])), "expected semi-transparent green material");
  assert(baseColors.some((c) => approximatelyColor(c, [0, 0, 1, 0.3])), "expected semi-transparent blue material");

  const blendMaterials = materials.filter((m) => m.alphaMode === "BLEND");
  assert(blendMaterials.length >= 2, "expected transparent materials to use alphaMode=BLEND");
});

function approximatelyColor(actual: number[], expected: number[], epsilon = 1e-3): boolean {
  return expected.every((v, i) => Math.abs((actual[i] ?? 0) - v) <= epsilon);
}

function parseGlbJsonChunk(glb: Uint8Array): GltfJson {
  const view = new DataView(glb.buffer, glb.byteOffset, glb.byteLength);

  const magic = view.getUint32(0, true);
  assertEquals(magic, 0x46546c67, "invalid GLB magic header"); // 'glTF'

  const version = view.getUint32(4, true);
  assertEquals(version, 2, "unsupported GLB version");

  const totalLength = view.getUint32(8, true);
  assertEquals(totalLength, glb.byteLength, "GLB length header mismatch");

  let offset = 12;
  while (offset + 8 <= glb.byteLength) {
    const chunkLength = view.getUint32(offset, true);
    const chunkType = view.getUint32(offset + 4, true);
    const chunkStart = offset + 8;
    const chunkEnd = chunkStart + chunkLength;

    if (chunkEnd > glb.byteLength) {
      break;
    }

    if (chunkType === 0x4e4f534a) { // 'JSON'
      const chunkData = glb.subarray(chunkStart, chunkEnd);
      const jsonText = new TextDecoder().decode(chunkData).replace(/\u0000+$/g, "");
      return JSON.parse(jsonText) as GltfJson;
    }

    offset = chunkEnd;
  }

  throw new Error("GLB JSON chunk not found");
}

async function runTest(instance: OpenSCAD, directory: string, outfile?: string) {
  const __dirname = dirname(fromFileUrl(import.meta.url));

  await loadTestFiles(instance, join(__dirname, directory));
  
  const code = instance.callMain([`/test.scad`, "--export-format", "stl", "-o", outfile ?? "out.stl"]);
  assertEquals(0, code);

  const output = instance.FS.readFile("out.stl", { encoding: "binary" });
  await Deno.writeFile(join(__dirname, directory, "out.stl"), output);
}
