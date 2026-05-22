// Test file for GLB export with colors and transparency

// Solid red cube
color([1, 0, 0])
cube([10, 10, 10]);

// Semi-transparent green sphere
translate([15, 0, 0])
color([0, 1, 0], alpha=0.5)
sphere(r=8);

// Blue cylinder with low alpha
translate([30, 0, 0])
color([0, 0, 1], alpha=0.3)
cylinder(h=20, r=5, center=true);

// Multi-color - yellow to demonstrate color transition
translate([0, 15, 0])
color([1, 1, 0])
cube([8, 8, 8]);

// Transparent cone
translate([15, 15, 0])
color([1, 0, 1], alpha=0.7)
cone(h=15, r=6);

// Mix of colors with difference operation
translate([30, 15, 0])
difference() {
  color([1, 0, 0])
  cube([12, 12, 12], center=true);
  
  color([0, 1, 1], alpha=0.5)
  sphere(r=7);
}

module cone(h, r) {
  linear_extrude(height=h)
  circle(r=r);
}
