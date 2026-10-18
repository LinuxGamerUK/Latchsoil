# Art direction

Stylized 3D, mid-poly, readable at two distances: a colonist at about 4 m of camera distance, and a holding from about 40 m up. Big shapes. Few tiny surface details. Stylized PBR.

The camera is isometric. Q and E snap it in 90 degree steps. Design buildings so each snap still explains the door, the roof, and the work spot.

## Light and sky

Cinderwell is a warm orange key. Shadows are cool. Dusks are long, and the clock in the sim drives the sun, because night changes temperature and who is awake.

The Stitch is always faintly in the skybox. A screenshot should tell you the ring fell without a caption.

## Shared material rules

- One accent color per people, used on cloth, trim, or a light. The race doc names it.
- Injury is a decal, a limp, and a UI clock. Gore is not the style.
- Placeholder art is how a milestone finishes. A tinted blockout with the right silhouette is better than a stall for a finished mesh.
- Generated concept images, when they exist, live in `docs/art-ref/` and are reference only. Do not import them as runtime textures by accident.

## Animation

The first set is idle, walk, work, hit, and down. The Harth get it first. Every other people reuses that skeleton. Crests, membranes, coats, grafts, veils, and bark are props on the silhouette until a people is promoted to a unique set.

## What to draw first, per people

When a people is promoted out of blockout, the set is:

1. A turnaround of one default body, using the measurements in the race doc
2. One holding exterior in their material language
3. One prop from their starting kit

The race doc is the authority for palette, architecture, and default body. This file is the authority for camera readability, light, and production order.

## Biomes, as color

So the eye can sort the map before the UI does:

| Biome | Ground | Sky influence | Landmark |
| --- | --- | --- | --- |
| Temperate valley | Ochre soil, green crop, dark timber | Warm haze | The peg and a ditch |
| Glass basin | Charcoal glass, copper glints | Heat shimmer | A kiln arch |
| Coast | Teal water, brass, pale sand | Bright, wet | A bridge or a coracle |
| Karst | Bone stone, ink shadow, amber lamp | Dim | A ribbed entrance |
| Mesa | Sand and sky-bleach | Hard clear light | A sail frame |
| Marsh | Wet brown, violet fog, spore gold | Low contrast | A gauze banner |
| Hull crater | Cobalt, rust, warning yellow | Dust | A bulkhead in the dirt |

## Readability checklist

- Selected people carry a ground ring and a job icon.
- A drafted person reads differently from a working person at holding zoom.
- An order shows a path and a destination marker until the job ends or fails.
- A failed job says why, in one line: hungry, no path, no skill, no material, afraid, night.
- Two peoples standing together are distinguishable with the color and the silhouette alone, even before faces exist.
