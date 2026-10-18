"""Low-poly storage barrel for a holding: dark timber staves, two soot hoops.

The art rules this is built to: big shapes, few tiny surface details, stylized
PBR, readable as a barrel at about 4 m. Timber and soot are the temperate-valley
material language. The people's accent color is not used here — one accent, and
it stays on cloth, trim, or a light.

1 unit is 1 meter. The barrel is 0.72 m tall and 0.56 m across the belly.
Blender is Z-up; the glTF exporter's default Y-up conversion is what Godot loads.

Run only via scripts/asset-spike.sh. The output path is the argument after --.
"""
import math
import os
import sys

import bpy

SIDES = 12
# (height, radius) from the ground up. The belly is the read at 4 m.
PROFILE = (
    (0.00, 0.22),
    (0.08, 0.235),
    (0.20, 0.255),
    (0.36, 0.28),
    (0.52, 0.255),
    (0.64, 0.235),
    (0.72, 0.22),
)
# (z0, z1, radius). Proud of the staves so the hoop reads as its own shape.
HOOPS = (
    (0.16, 0.22, 0.278),
    (0.50, 0.56, 0.278),
)
TIMBER = (0.42, 0.26, 0.13)
SOOT = (0.09, 0.08, 0.07)


def output_path():
    if "--" not in sys.argv:
        sys.exit("gen_barrel: output path required after --")
    extra = sys.argv[sys.argv.index("--") + 1 :]
    if len(extra) != 1 or not extra[0]:
        sys.exit("gen_barrel: expected exactly one output path after --")
    return extra[0]


def principled(name, color, roughness, metallic):
    mat = bpy.data.materials.new(name)
    # Blender 5 materials are node-based already. use_nodes is deprecated and
    # warns on 5.2; touching it is not required to get a Principled BSDF.
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is None:
        sys.exit("gen_barrel: Principled BSDF missing on " + name)
    bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic
    return mat


def ring(sides, z, radius):
    verts = []
    for i in range(sides):
        angle = 2.0 * math.pi * i / sides
        verts.append((radius * math.cos(angle), radius * math.sin(angle), z))
    return verts


def add_band(verts, faces, materials, z0, z1, radius, slot):
    base = len(verts)
    verts.extend(ring(SIDES, z0, radius))
    verts.extend(ring(SIDES, z1, radius))
    for i in range(SIDES):
        nxt = (i + 1) % SIDES
        faces.append((base + i, base + nxt, base + SIDES + nxt, base + SIDES + i))
        materials.append(slot)


def add_cap(verts, faces, materials, z, radius, slot, flip):
    center = len(verts)
    verts.append((0.0, 0.0, z))
    base = len(verts)
    verts.extend(ring(SIDES, z, radius))
    for i in range(SIDES):
        nxt = (i + 1) % SIDES
        if flip:
            faces.append((center, base + nxt, base + i))
        else:
            faces.append((center, base + i, base + nxt))
        materials.append(slot)


def build():
    verts = []
    faces = []
    materials = []
    rings = [ring(SIDES, z, radius) for z, radius in PROFILE]
    for band in rings:
        verts.extend(band)
    for r in range(len(PROFILE) - 1):
        for i in range(SIDES):
            nxt = (i + 1) % SIDES
            a = r * SIDES + i
            b = r * SIDES + nxt
            c = (r + 1) * SIDES + nxt
            d = (r + 1) * SIDES + i
            faces.append((a, b, c, d))
            materials.append(0)
    add_cap(verts, faces, materials, PROFILE[0][0], PROFILE[0][1], 0, flip=True)
    add_cap(verts, faces, materials, PROFILE[-1][0], PROFILE[-1][1], 0, flip=False)
    for z0, z1, radius in HOOPS:
        add_band(verts, faces, materials, z0, z1, radius, 1)

    mesh = bpy.data.meshes.new("Barrel")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    mesh.materials.append(principled("Timber", TIMBER, 0.72, 0.0))
    mesh.materials.append(principled("Soot", SOOT, 0.42, 0.85))
    for poly, slot in zip(mesh.polygons, materials):
        poly.material_index = slot
    if hasattr(mesh, "shade_flat"):
        mesh.shade_flat()
    else:
        for poly in mesh.polygons:
            poly.use_smooth = False
    obj = bpy.data.objects.new("Barrel", mesh)
    bpy.context.collection.objects.link(obj)
    print(
        "gen_barrel: blender_verts",
        len(mesh.vertices),
        "faces",
        len(mesh.polygons),
        "materials",
        len(mesh.materials),
    )
    return mesh


def export(path):
    import addon_utils

    addon_utils.enable("io_scene_gltf2")
    result = bpy.ops.export_scene.gltf(filepath=path, export_format="GLB")
    if result != {"FINISHED"}:
        sys.exit("gen_barrel: export returned " + str(result))
    if not os.path.isfile(path) or os.path.getsize(path) == 0:
        sys.exit("gen_barrel: export wrote no file")
    print("gen_barrel: wrote", os.path.basename(path), os.path.getsize(path), "bytes")


def main():
    print("BLENDER_VERSION", bpy.app.version_string)
    path = output_path()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    build()
    export(path)


if __name__ == "__main__":
    main()
