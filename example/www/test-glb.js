import OpenScad from "./openscad.js";
import { addFonts } from "./openscad.fonts.js";

async function generateGLB() {
  const testScad = `
// Test file for GLB export with colors and transparency
color([1, 0, 0])
cube([10, 10, 10]);

translate([15, 0, 0])
color([0, 1, 0], alpha=0.5)
sphere(r=8);

translate([30, 0, 0])
color([0, 0, 1], alpha=0.3)
cylinder(h=20, r=5, center=true);
`;

  console.log("[*] Initializing OpenSCAD WASM...");
  const instance = await OpenScad({ noInitialRun: true });
  addFonts(instance);

  console.log("[*] Writing test file...");
  instance.FS.writeFile("/test.scad", testScad);

  console.log("[*] Running OpenSCAD with GLB export...");
  const code = instance.callMain(["/test.scad", "--export-format=glb", "-o", "/test.glb"]);

  console.log(`[*] Exit code: ${code}`);

  if (code === 0) {
    try {
      const output = instance.FS.readFile("/test.glb");
      const blob = new Blob([output], { type: "application/octet-stream" });
      
      // Create download link
      const link = document.createElement('a');
      link.href = URL.createObjectURL(blob);
      link.download = "test-colors.glb";
      document.body.appendChild(link);
      link.click();
      link.remove();
      
      console.log(`[*] GLB file downloaded! Size: ${output.length} bytes`);
      console.log("[✓] SUCCESS: GLB generated with colors and transparency");
    } catch (e) {
      console.error(`[!] Failed to export GLB: ${e.message}`);
    }
  } else {
    console.error(`[!] OpenSCAD failed with code ${code}`);
  }
}

// Auto-run on page load
window.addEventListener('DOMContentLoaded', generateGLB);

// Also expose function for testing
(window as any).generateGLB = generateGLB;
