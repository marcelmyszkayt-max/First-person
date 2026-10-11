"""
VOLCANO ISLAND  -  procedural night scene for Blender
=====================================================
Builds a foggy autumn island at night: a stepped volcanic butte with a glowing
lava lake, a towering mushroom-shaped eruption cloud (real volumetrics) lit
from below by the crater and from inside by lightning, a half-timbered
village with lit windows and street lanterns, cobbled roads lined with
flower hedges, a harbour with a pier and moored boats, a lighthouse sweeping
its beam through the fog, autumn forests, a moonlit ocean and a starry sky.

Everything is generated from code: no add-ons, images or downloads.

HOW TO USE
  1. Open Blender 4.2 or newer (tested on 4.2 LTS and 5.0).
  2. Go to the Scripting workspace, click "New", paste this whole file in.
  3. Press "Run Script" (Alt+P). Building takes about 5-10 seconds.
  4. Press F12 to render (Cycles). Or look through the viewport in
     Rendered mode; the volumes make that slow on a CPU, so try Material
     Preview first.

The scene is built in a new scene called "Volcano Island". Running the script
again deletes that scene and builds a fresh one, so your other scenes are
left alone. Change CONFIG below to switch cameras, quality and features.

From a terminal you can build and render in one go:
  blender -b -P VolcanoIsland.py -- render camera=Village samples=256 res=1920x1080
  blender -b -P VolcanoIsland.py -- render animation out=//frames/island_
Other options: engine=EEVEE seed=12 frames=120 gpu=0
"""

import bpy
import bmesh
import math
import random
import time
import warnings
from math import sin, cos, pi, tau, atan2, hypot, sqrt, radians
from mathutils import Vector, Matrix, noise

# ----------------------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------------------
CONFIG = {
    "SEED": 7,                    # change for a different island
    "SCENE_NAME": "Volcano Island",
    "ENGINE": "CYCLES",           # "CYCLES" (best) or "EEVEE" (fast preview)
    "USE_GPU": True,              # use a GPU for Cycles when one is available
    "RESOLUTION": (1920, 1080),
    "SAMPLES": 128,               # Cycles samples (denoised); 256+ for a final still
    "CAMERA": "Hero",             # "Hero", "Village", "Harbour", "Aerial" or "Crater"
    "TERRAIN_STEP": 1.0,          # metres between terrain vertices (bigger = faster)
    "HOUSES": 30,
    "TREES": 120,
    "FOG": True,                  # volumetric ground fog
    "FOG_DENSITY": 0.0045,
    "CLOUD": True,                # volumetric eruption cloud
    "LIGHTNING": True,            # lightning inside the cloud
    "EMBERS": True,               # glowing embers rising from the crater
    "LIGHTHOUSE": True,
    "HARBOUR": True,              # pier and boats
    "ANIMATE": True,              # waves, billowing cloud, lava, embers, beam
    "FRAMES": 240,
    "RENDER_ON_FINISH": False,    # render a still straight after building
    "OUTPUT": "//volcano_island.png",
}

# ----------------------------------------------------------------------------
# Maths and noise helpers
# ----------------------------------------------------------------------------
RNG = random.Random(CONFIG["SEED"])
_NOFF = Vector((RNG.uniform(-300, 300), RNG.uniform(-300, 300), RNG.uniform(-300, 300)))
_noise = noise.noise


def clamp(x, a=0.0, b=1.0):
    return a if x < a else b if x > b else x


def lerp(a, b, t):
    return a + (b - a) * t


def smoothstep(e0, e1, x):
    t = clamp((x - e0) / (e1 - e0))
    return t * t * (3.0 - 2.0 * t)


def n3(x, y, z=0.0):
    """Perlin noise, roughly -1..1, offset by the seed."""
    return _noise(Vector((x + _NOFF.x, y + _NOFF.y, z + _NOFF.z)))


def fbm(x, y, z=0.0, octaves=4, lac=2.03, gain=0.5):
    total, amp, norm = 0.0, 1.0, 0.0
    for i in range(octaves):
        total += amp * n3(x, y, z + i * 31.7)
        norm += amp
        amp *= gain
        x *= lac
        y *= lac
        z *= lac
    return total / norm


def ang_diff(a, b):
    return abs((a - b + pi) % tau - pi)


def blackbody(kelvin):
    """Approximate RGB (linear) of a black body, good enough for lamp colours."""
    t = kelvin / 100.0
    r = 1.0 if t <= 66 else clamp(1.292936 * ((t - 60) ** -0.1332047))
    g = clamp(0.3900816 * math.log(t) - 0.6318414) if t <= 66 else clamp(1.1298909 * ((t - 60) ** -0.0755148))
    b = 1.0 if t >= 66 else (0.0 if t <= 19 else clamp(0.5432068 * math.log(t - 10) - 1.1962541))
    return (r ** 2.2, g ** 2.2, b ** 2.2)


WARM = blackbody(2300)
TORCH = blackbody(1800)
MOON_COL = (0.62, 0.74, 1.0)


class PointIndex:
    """A tiny spatial hash for 2D distance queries."""

    def __init__(self, cell=8.0):
        self.cell = cell
        self.grid = {}

    def add(self, x, y, data=None):
        k = (int(x // self.cell), int(y // self.cell))
        self.grid.setdefault(k, []).append((x, y, data))

    def near(self, x, y, r):
        c = self.cell
        x0, x1 = int((x - r) // c), int((x + r) // c)
        y0, y1 = int((y - r) // c), int((y + r) // c)
        for i in range(x0, x1 + 1):
            for j in range(y0, y1 + 1):
                for item in self.grid.get((i, j), ()):
                    yield item


# ----------------------------------------------------------------------------
# Island shape. Everything else (roads, houses, trees) asks these functions
# for the ground height, so all props sit on the terrain.
# ----------------------------------------------------------------------------
ISLAND_RX, ISLAND_RY = 172.0, 130.0
PLATEAU = 7.0
SEA_FLOOR = -16.0
MOUNT_C = Vector((24.0, 36.0, 0.0))
BEACH_DIR = atan2(-0.74, -0.68)      # harbour beach, front left (ellipse space)
COVE_DIR = atan2(0.82, 0.42)         # a small sandy cove at the back
LIGHTHOUSE_DIR = atan2(-0.50, 0.87)  # rocky point, front right

# (radius, height) profile of the volcano, from below the ground, up the
# stepped cliffs, over the crater rim and down to the lava lake.
MOUNT_PROFILE = [
    (72.0, -8.0), (63.0, 4.0), (60.0, 10.0), (57.0, 14.0), (55.6, 24.0), (52.5, 26.8),
    (47.5, 28.4), (45.2, 31.5), (43.6, 44.0), (41.0, 47.2), (37.2, 48.6), (35.4, 51.5),
    (33.6, 63.5), (31.2, 70.0), (29.0, 73.6), (26.6, 74.6), (24.2, 72.8), (21.8, 66.0),
    (19.6, 60.0), (15.0, 57.0), (8.0, 56.2), (0.0, 56.0),
]
LAVA_Z = 56.5


def shore_warp(a):
    c, s = cos(a), sin(a)
    return (0.075 * n3(c * 1.3, s * 1.3, 2.0)
            + 0.035 * n3(c * 3.7, s * 3.7, 7.0)
            + 0.012 * n3(c * 11.0, s * 11.0, 13.0))


def island_polar(x, y):
    """Normalised distance from the island centre (1 = waterline) and angle."""
    u, v = x / ISLAND_RX, y / ISLAND_RY
    a = atan2(v, u)
    return hypot(u, v) / (1.0 + shore_warp(a)), a


def beach_weight(a):
    return max(1.0 - smoothstep(0.16, 0.40, ang_diff(a, BEACH_DIR)),
               0.85 * (1.0 - smoothstep(0.07, 0.20, ang_diff(a, COVE_DIR))))


def plateau_height(x, y):
    h = PLATEAU + 1.0 * fbm(x * 0.010, y * 0.010, 3.0, 3) + 0.3 * fbm(x * 0.045, y * 0.045, 9.0, 2)
    dm = hypot(x - MOUNT_C.x, y - MOUNT_C.y)
    return h + 3.0 * (1.0 - smoothstep(45.0, 150.0, dm))


def terrain_height(x, y):
    d, a = island_polar(x, y)
    if d > 1.42:
        return SEA_FLOOR
    base = plateau_height(x, y) if d < 0.95 else PLATEAU + 0.5
    j = n3(x * 0.07, y * 0.07, 21.0)
    # rocky coast: cliff, a ledge of fallen blocks, then the drop into the sea
    h = base
    h = lerp(h, 2.6 + 0.9 * j, smoothstep(0.862, 0.878, d))
    h = lerp(h, 1.0 + 0.5 * j, smoothstep(0.935, 0.948, d))
    h = lerp(h, -2.5, smoothstep(0.968, 0.99, d))
    h = lerp(h, SEA_FLOOR, smoothstep(0.99, 1.30, d))
    b = beach_weight(a)
    if b > 0.0:
        hb = base
        hb = lerp(hb, 1.7, smoothstep(0.74, 0.90, d))
        hb = lerp(hb, -1.2, smoothstep(0.90, 1.00, d))
        hb = lerp(hb, SEA_FLOOR, smoothstep(1.00, 1.32, d))
        h = lerp(h, hb, b)
    return h


def point_at_island(a, d):
    """World XY of a point at ellipse angle a and normalised distance d."""
    r = d * (1.0 + shore_warp(a))
    return Vector((cos(a) * r * ISLAND_RX, sin(a) * r * ISLAND_RY, 0.0))


def _profile_r(z):
    """Outer radius of the volcano profile at height z (outer slope only)."""
    for (r0, z0), (r1, z1) in zip(MOUNT_PROFILE, MOUNT_PROFILE[1:]):
        if z1 < z0:
            break
        if z0 <= z <= z1:
            return lerp(r0, r1, (z - z0) / max(z1 - z0, 1e-6))
    return MOUNT_PROFILE[0][0]


def mountain_point(theta, r0, z0):
    """Displaced position of one vertex of the volcano lathe."""
    c, s = cos(theta), sin(theta)
    k = min(1.0, r0 / 14.0)
    # strata tilt: ledges rise and fall around the mountain
    tilt = k * smoothstep(3.0, 14.0, z0) * (1.0 - smoothstep(62.0, 73.0, z0))
    z = z0 + tilt * (5.0 * fbm(c * 1.1, s * 1.1, 3.0, 3) + 2.5 * n3(c * 3.2, s * 3.2, z0 * 0.03 + 9.0))
    # buttresses and bays: a few big lobes plus finer spurs
    # each tier gets its own outline, so ledges widen, narrow and vanish
    rs = 1.0 + k * (0.10 * fbm(c * 1.3, s * 1.3, 40.0, 3)
                    + 0.08 * fbm(c * 2.6, s * 2.6, z0 * 0.05 + 70.0, 3)
                    + 0.03 * n3(c * 8.0, s * 8.0, z0 * 0.1 + 15.0))
    r = r0 * rs
    x, y = c * r, s * r
    r += k * (3.2 * fbm(x * 0.05, y * 0.05, z0 * 0.05 + 90.0, 4)
              - 3.0 * max(0.0, n3(c * 18.0, s * 18.0, z0 * 0.015 + 5.0))   # gullies
              + 0.7 * n3(c * 70.0, s * 70.0, z0 * 0.01 + 33.0))             # basalt columns
    r += k * 1.3 * (0.35 - abs(n3(x * 0.16, y * 0.16, z0 * 0.16 + 61.0)))          # rocky facets
    z += 0.8 * k * n3(x * 0.09, y * 0.09, z0 * 0.09 + 7.0)
    return (MOUNT_C.x + c * r, MOUNT_C.y + s * r, z)


def mountain_radius(theta, z):
    """Approximate distance from the volcano axis to its surface."""
    p = mountain_point(theta, _profile_r(z), z)
    return hypot(p[0] - MOUNT_C.x, p[1] - MOUNT_C.y)


# ----------------------------------------------------------------------------
# Blender data helpers
# ----------------------------------------------------------------------------
PREFIX = "VI_"


def _enable_nodes(idblock):
    with warnings.catch_warnings():
        warnings.simplefilter("ignore")
        idblock.use_nodes = True


def _try_set(obj, attr, value):
    try:
        setattr(obj, attr, value)
        return True
    except (AttributeError, TypeError, ValueError):
        return False


def tag(ob):
    ob["volcano_island"] = True
    return ob


def link(ob, coll):
    coll.objects.link(ob)
    return tag(ob)


def find_socket(sockets, key):
    if isinstance(key, int):
        return sockets[key]
    fallback = None
    for s in sockets:
        if s.name == key or s.identifier == key:
            if getattr(s, "enabled", True):
                return s
            fallback = fallback or s
    if fallback is None:
        raise KeyError(key)
    return fallback


class Nodes:
    """Small helper to build node trees: nodes, inputs, links, common maths."""

    def __init__(self, tree):
        self.tree = tree
        self.nodes = tree.nodes
        self.links = tree.links

    def feed(self, sock, v):
        if v is None:
            return
        if isinstance(v, bpy.types.NodeSocket):
            self.links.new(v, sock)
        elif isinstance(v, bpy.types.Node):
            self.links.new(next(o for o in v.outputs if getattr(o, "enabled", True)), sock)
        else:
            if isinstance(v, (tuple, list)):
                if sock.type == 'RGBA' and len(v) == 3:
                    v = tuple(v) + (1.0,)
            elif sock.type == 'VECTOR':
                v = (v, v, v)
            elif sock.type == 'RGBA':
                v = (v, v, v, 1.0)
            sock.default_value = v

    def node(self, kind, inputs=None, **props):
        n = self.nodes.new(kind)
        for k, v in props.items():
            setattr(n, k, v)
        for k, v in (inputs or {}).items():
            self.feed(find_socket(n.inputs, k), v)
        return n

    def out(self, node, key=0):
        return find_socket(node.outputs, key)

    # --- maths -------------------------------------------------------------
    def math(self, op, a, b=None, c=None, clamp=False):
        n = self.node("ShaderNodeMath", operation=op)
        n.use_clamp = clamp
        self.feed(n.inputs[0], a)
        if b is not None:
            self.feed(n.inputs[1], b)
        if c is not None:
            self.feed(n.inputs[2], c)
        return n.outputs[0]

    def add(self, a, b):
        return self.math('ADD', a, b)

    def mul(self, a, b):
        return self.math('MULTIPLY', a, b)

    def vmath(self, op, a, b=None, scale=None):
        n = self.node("ShaderNodeVectorMath", operation=op)
        self.feed(n.inputs[0], a)
        if b is not None:
            self.feed(n.inputs[1], b)
        if scale is not None:
            self.feed(find_socket(n.inputs, "Scale"), scale)
        return n.outputs["Value"] if op in ('DOT_PRODUCT', 'LENGTH', 'DISTANCE') else n.outputs["Vector"]

    def mix(self, fac, a, b, blend='MIX', clamp=False):
        n = self.node("ShaderNodeMix", data_type='RGBA', blend_type=blend, clamp_result=clamp)
        self.feed(find_socket(n.inputs, "Factor"), fac)
        self.feed(find_socket(n.inputs, "A"), a)
        self.feed(find_socket(n.inputs, "B"), b)
        return find_socket(n.outputs, "Result")

    def mixf(self, fac, a, b):
        n = self.node("ShaderNodeMix", data_type='FLOAT')
        self.feed(find_socket(n.inputs, "Factor"), fac)
        self.feed(find_socket(n.inputs, "A"), a)
        self.feed(find_socket(n.inputs, "B"), b)
        return find_socket(n.outputs, "Result")

    def maprange(self, v, a, b, c=0.0, d=1.0, clamp=True, smooth=False):
        n = self.node("ShaderNodeMapRange", interpolation_type='SMOOTHSTEP' if smooth else 'LINEAR')
        n.clamp = clamp
        self.feed(n.inputs["Value"], v)
        for sock, val in zip(("From Min", "From Max", "To Min", "To Max"), (a, b, c, d)):
            self.feed(find_socket(n.inputs, sock), val)
        return find_socket(n.outputs, "Result")

    def ramp(self, fac, stops, interp='LINEAR'):
        n = self.node("ShaderNodeValToRGB")
        cr = n.color_ramp
        cr.interpolation = interp
        while len(cr.elements) < len(stops):
            cr.elements.new(0.5)
        for el, (pos, col) in zip(cr.elements, stops):
            el.position = pos
            el.color = tuple(col) + (1.0,) if len(col) == 3 else tuple(col)
        self.feed(n.inputs[0], fac)
        return n.outputs["Color"]

    # --- inputs and textures -------------------------------------------------
    def coord(self, kind='Object'):
        n = self.node("ShaderNodeTexCoord")
        return n.outputs[kind]

    def geom(self, kind='Position'):
        return self.node("ShaderNodeNewGeometry").outputs[kind]

    def attr(self, name, kind='Fac'):
        return self.node("ShaderNodeAttribute", attribute_name=name).outputs[kind]

    def obj_info(self, kind='Random'):
        return self.node("ShaderNodeObjectInfo").outputs[kind]

    def sep(self, vec):
        n = self.node("ShaderNodeSeparateXYZ")
        self.feed(n.inputs[0], vec)
        return n.outputs

    def comb(self, x=0.0, y=0.0, z=0.0):
        n = self.node("ShaderNodeCombineXYZ")
        for i, v in enumerate((x, y, z)):
            self.feed(n.inputs[i], v)
        return n.outputs[0]

    def noise(self, vec, scale=5.0, detail=2.0, rough=0.5, dist=0.0, w=None, lac=2.0):
        n = self.node("ShaderNodeTexNoise", noise_dimensions='4D' if w is not None else '3D')
        self.feed(n.inputs["Vector"], vec)
        if w is not None:
            self.feed(n.inputs["W"], w)
        self.feed(n.inputs["Scale"], scale)
        self.feed(n.inputs["Detail"], detail)
        self.feed(n.inputs["Roughness"], rough)
        self.feed(n.inputs["Distortion"], dist)
        self.feed(find_socket(n.inputs, "Lacunarity"), lac)
        return n

    def voronoi(self, vec, scale=5.0, feature='F1', dist='EUCLIDEAN', rand=1.0, dims='3D'):
        n = self.node("ShaderNodeTexVoronoi", feature=feature, distance=dist, voronoi_dimensions=dims)
        self.feed(n.inputs["Vector"], vec)
        self.feed(n.inputs["Scale"], scale)
        self.feed(find_socket(n.inputs, "Randomness"), rand)
        return n

    def bump(self, height, strength=0.3, distance=0.1, normal=None):
        n = self.node("ShaderNodeBump", {"Strength": strength, "Distance": distance, "Height": height})
        if normal is not None:
            self.feed(n.inputs["Normal"], normal)
        return n.outputs["Normal"]

    def principled(self, base, rough=0.5, **extra):
        inputs = {"Base Color": base, "Roughness": rough}
        names = {"metal": "Metallic", "normal": "Normal", "emit": "Emission Color",
                 "emit_strength": "Emission Strength", "trans": "Transmission Weight",
                 "ior": "IOR", "spec": "Specular IOR Level", "alpha": "Alpha",
                 "coat": "Coat Weight", "sheen": "Sheen Weight", "sss": "Subsurface Weight"}
        for k, v in extra.items():
            inputs[names[k]] = v
        return self.node("ShaderNodeBsdfPrincipled", inputs)


def time_driver(sock, rate, offset=0.0):
    """Drive a socket value from the frame number (no Python needed)."""
    if not CONFIG["ANIMATE"]:
        sock.default_value = offset
        return
    fc = sock.driver_add("default_value")
    fc.driver.type = 'SCRIPTED'
    fc.driver.expression = "frame*%g+%g" % (rate, offset)


def new_material(name):
    mat = bpy.data.materials.new(PREFIX + name)
    _enable_nodes(mat)
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    return mat, Nodes(nt), out


def _dithered(mat):
    if not _try_set(mat, "surface_render_method", 'DITHERED'):
        _try_set(mat, "blend_method", 'HASHED')


def _volume_settings(mat):
    cyc = getattr(mat, "cycles", None)
    if cyc is not None:
        _try_set(cyc, "homogeneous_volume", False)
        _try_set(cyc, "volume_interpolation", 'LINEAR')


# --- mesh building ---------------------------------------------------------
CUBE_V = [(-.5, -.5, -.5), (.5, -.5, -.5), (.5, .5, -.5), (-.5, .5, -.5),
          (-.5, -.5, .5), (.5, -.5, .5), (.5, .5, .5), (-.5, .5, .5)]
# faces with their UV axes (two cube axes that span the face)
CUBE_F = [((0, 3, 2, 1), (1, 0)), ((4, 5, 6, 7), (0, 1)), ((0, 1, 5, 4), (0, 2)),
          ((1, 2, 6, 5), (1, 2)), ((2, 3, 7, 6), (0, 2)), ((3, 0, 4, 7), (1, 2))]

_ICO = {}


def unit_ico(sub):
    if sub not in _ICO:
        bm = bmesh.new()
        bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
        verts = [v.co.copy() for v in bm.verts]
        faces = [tuple(v.index for v in f.verts) for f in bm.faces]
        bm.free()
        _ICO[sub] = (verts, faces)
    return _ICO[sub]


def TRS(loc=(0, 0, 0), rz=0.0, scale=(1, 1, 1), rx=0.0, ry=0.0):
    m = Matrix.Translation(Vector(loc))
    if rz:
        m = m @ Matrix.Rotation(rz, 4, 'Z')
    if ry:
        m = m @ Matrix.Rotation(ry, 4, 'Y')
    if rx:
        m = m @ Matrix.Rotation(rx, 4, 'X')
    return m @ Matrix.Diagonal(Vector(scale).to_4d())


class MeshBuilder:
    """Collects verts/faces/UVs/material slots/attributes, then makes one mesh."""

    def __init__(self):
        self.v, self.f, self.fm, self.fs, self.uv = [], [], [], [], []
        self.mats, self.mat_index = [], {}
        self.attrs = {}

    def _mi(self, mat):
        i = self.mat_index.get(mat.name)
        if i is None:
            i = self.mat_index[mat.name] = len(self.mats)
            self.mats.append(mat)
        return i

    def add(self, verts, faces, mat, smooth=False, uvs=None, attrs=None):
        base = len(self.v)
        mi = self._mi(mat)
        self.v.extend(verts)
        for name, val in (attrs or {}).items():
            arr = self.attrs.setdefault(name, [0.0] * base)
            arr.extend([val] * len(verts) if not isinstance(val, list) else val)
        for name, arr in self.attrs.items():
            if len(arr) < len(self.v):
                arr.extend([0.0] * (len(self.v) - len(arr)))
        for k, f in enumerate(faces):
            self.f.append(tuple(base + i for i in f))
            self.fm.append(mi)
            self.fs.append(smooth)
            self.uv.append(uvs[k] if uvs else [(0.0, 0.0)] * len(f))

    def box(self, M, mat, attrs=None):
        sx, sy, sz = (M.col[0].xyz.length, M.col[1].xyz.length, M.col[2].xyz.length)
        size = (sx, sy, sz)
        verts = [M @ Vector(c) for c in CUBE_V]
        faces, uvs = [], []
        for f, (a, b) in CUBE_F:
            faces.append(f)
            uvs.append([(CUBE_V[i][a] * size[a], CUBE_V[i][b] * size[b]) for i in f])
        self.add(verts, faces, mat, uvs=uvs, attrs=attrs)

    def cyl(self, M, mat, seg=12, r0=0.5, r1=0.5, z0=0.0, z1=1.0, caps=(True, True), smooth=True, attrs=None):
        verts, faces, uvs = [], [], []
        for k in range(seg):
            a = tau * k / seg
            verts.append(M @ Vector((cos(a) * r0, sin(a) * r0, z0)))
            verts.append(M @ Vector((cos(a) * r1, sin(a) * r1, z1)))
        h = z1 - z0
        for k in range(seg):
            a, b = 2 * k, 2 * ((k + 1) % seg)
            faces.append((a, b, b + 1, a + 1))
            u0, u1 = k / seg * tau * r0, (k + 1) / seg * tau * r0
            uvs.append([(u0, 0), (u1, 0), (u1, h), (u0, h)])
        n = len(verts)
        if caps[0] and r0 > 0:
            verts.append(M @ Vector((0, 0, z0)))
            for k in range(seg):
                faces.append((n, 2 * ((k + 1) % seg), 2 * k))
                uvs.append([(0, 0)] * 3)
            n += 1
        if caps[1] and r1 > 0:
            verts.append(M @ Vector((0, 0, z1)))
            for k in range(seg):
                faces.append((n, 2 * k + 1, 2 * ((k + 1) % seg) + 1))
                uvs.append([(0, 0)] * 3)
        self.add(verts, faces, mat, smooth=smooth, uvs=uvs, attrs=attrs)

    def blob(self, center, radius, mat, sub=2, squash=(1, 1, 1), rough=0.25, seed=0.0, attrs=None, smooth=True):
        verts, faces = unit_ico(sub)
        out = []
        for v in verts:
            d = 1.0 + rough * n3(v.x * 1.7 + seed, v.y * 1.7, v.z * 1.7 + seed * 0.7) \
                + rough * 0.4 * n3(v.x * 4.1 + seed, v.y * 4.1 - seed, v.z * 4.1)
            out.append(Vector((center[0] + v.x * radius * squash[0] * d,
                               center[1] + v.y * radius * squash[1] * d,
                               center[2] + v.z * radius * squash[2] * d)))
        self.add(out, faces, mat, smooth=smooth, attrs=attrs)

    def tube(self, path, radii, mat, seg=8, smooth=True, attrs=None, cap_end=True):
        """Sweep a circle along a 3D polyline."""
        verts, faces = [], []
        n = len(path)
        for i, p in enumerate(path):
            t = (path[min(i + 1, n - 1)] - path[max(i - 1, 0)]).normalized()
            side = t.cross(Vector((0, 0, 1)))
            if side.length < 1e-4:
                side = t.cross(Vector((1, 0, 0)))
            side.normalize()
            up = side.cross(t).normalized()
            for k in range(seg):
                a = tau * k / seg
                verts.append(p + (side * cos(a) + up * sin(a)) * radii[i])
        for i in range(n - 1):
            for k in range(seg):
                a, b = i * seg + k, i * seg + (k + 1) % seg
                faces.append((a, b, b + seg, a + seg))
        if cap_end:
            verts.append(path[-1] + (path[-1] - path[-2]).normalized() * radii[-1] * 0.5)
            c = len(verts) - 1
            for k in range(seg):
                faces.append(((n - 1) * seg + k, (n - 1) * seg + (k + 1) % seg, c))
        self.add(verts, faces, mat, smooth=smooth, attrs=attrs)

    def prism(self, pts2d, y0, y1, M, mat):
        """Extrude a 2D polygon (x, z) between y0 and y1."""
        n = len(pts2d)
        verts = [M @ Vector((x, y0, z)) for x, z in pts2d] + [M @ Vector((x, y1, z)) for x, z in pts2d]
        faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
        uvs = [[(pts2d[i][0], pts2d[i][1]) for i in reversed(range(n))], [(x, z) for x, z in pts2d]]
        for i in range(n):
            j = (i + 1) % n
            faces.append((i, j, j + n, i + n))
            ln = hypot(pts2d[j][0] - pts2d[i][0], pts2d[j][1] - pts2d[i][1])
            uvs.append([(0, 0), (ln, 0), (ln, y1 - y0), (0, y1 - y0)])
        self.add(verts, faces, mat, uvs=uvs)

    def build(self, name, coll, location=(0, 0, 0), rz=0.0):
        me = bpy.data.meshes.new(PREFIX + name)
        me.from_pydata([tuple(v) for v in self.v], [], self.f)
        for m in self.mats:
            me.materials.append(m)
        me.polygons.foreach_set("material_index", self.fm)
        me.polygons.foreach_set("use_smooth", self.fs)
        uvl = me.uv_layers.new(name="UVMap")
        flat = [c for face in self.uv for uv in face for c in uv]
        if len(flat) == len(me.loops) * 2:
            uvl.data.foreach_set("uv", flat)
        for aname, arr in self.attrs.items():
            at = me.attributes.new(aname, 'FLOAT', 'POINT')
            at.data.foreach_set("value", arr[:len(self.v)])
        me.update()
        ob = bpy.data.objects.new(name, me)
        ob.location = location
        ob.rotation_euler = (0, 0, rz)
        return link(ob, coll)


def point_light(name, loc, power, color, radius=0.1, coll=None):
    ld = bpy.data.lights.new(PREFIX + name, 'POINT')
    ld.energy = power
    ld.color = color
    ld.shadow_soft_size = radius
    ob = bpy.data.objects.new(name, ld)
    ob.location = loc
    return link(ob, coll)


# ----------------------------------------------------------------------------
# Scene reset
# ----------------------------------------------------------------------------
def reset_scene():
    name = CONFIG["SCENE_NAME"]
    old = bpy.data.scenes.get(name)
    scene = bpy.data.scenes.new(name + " (building)")
    if bpy.context.window is not None:
        bpy.context.window.scene = scene
    if old is not None:
        for ob in list(old.objects):
            if ob.get("volcano_island"):
                bpy.data.objects.remove(ob, do_unlink=True)
        for coll in list(old.collection.children_recursive):
            if coll.get("volcano_island"):
                bpy.data.collections.remove(coll)
        bpy.data.scenes.remove(old)
    # free data left behind by a previous build
    for _ in range(3):
        for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.node_groups, bpy.data.lights,
                     bpy.data.cameras, bpy.data.curves, bpy.data.textures, bpy.data.worlds,
                     bpy.data.volumes):
            for idb in list(coll):
                if idb.name.startswith(PREFIX) and idb.users == 0:
                    coll.remove(idb)
    scene.name = name
    scene["volcano_island"] = True
    return scene


def make_collection(scene, name, parent=None):
    c = bpy.data.collections.new(name)
    c["volcano_island"] = True
    (parent or scene.collection).children.link(c)
    return c


# ----------------------------------------------------------------------------
# Materials
# ----------------------------------------------------------------------------
class Mats:
    pass


M = Mats()


def mat_terrain():
    mat, nb, out = new_material("Terrain")
    pos = nb.coord('Object')
    nz = nb.sep(nb.geom('Normal'))[2]
    z = nb.sep(pos)[2]
    big = nb.noise(pos, 0.03, 4, 0.55).outputs["Fac"]
    mid = nb.noise(pos, 0.22, 6, 0.6).outputs["Fac"]
    fine = nb.noise(pos, 2.5, 3, 0.6).outputs["Fac"]
    gmix = nb.add(nb.mul(big, 0.75), nb.mul(mid, 0.25))
    grass = nb.ramp(gmix, [(0.30, (0.028, 0.048, 0.016)), (0.45, (0.050, 0.070, 0.022)),
                           (0.58, (0.095, 0.085, 0.028)), (0.70, (0.125, 0.070, 0.028))])
    grass = nb.mix(nb.mul(fine, 0.5), grass, (0.03, 0.04, 0.015), 'MULTIPLY')
    # rock with horizontal strata
    strata = nb.node("ShaderNodeTexWave", {"Vector": pos, "Scale": 0.12, "Distortion": 6.0, "Detail": 3.0},
                     wave_type='BANDS', bands_direction='Z').outputs["Fac"]
    rnoise = nb.noise(pos, 0.35, 8, 0.6).outputs["Fac"]
    rock = nb.ramp(nb.add(nb.mul(rnoise, 0.7), nb.mul(strata, 0.3)),
                   [(0.3, (0.035, 0.032, 0.030)), (0.55, (0.095, 0.085, 0.072)), (0.8, (0.16, 0.145, 0.12))])
    sand = nb.ramp(mid, [(0.3, (0.32, 0.27, 0.19)), (0.7, (0.42, 0.36, 0.25))])
    slope_g = nb.maprange(nb.add(nz, nb.mul(nb.add(mid, -0.5), 0.25)), 0.66, 0.80, 0.0, 1.0, smooth=True)
    col = nb.mix(slope_g, rock, grass)
    sand_m = nb.mul(nb.maprange(nb.add(z, nb.mul(nb.add(mid, -0.5), 1.5)), 2.6, 1.7), nb.maprange(nz, 0.55, 0.8))
    col = nb.mix(sand_m, col, sand)
    # wet shoreline, then fake water absorption with depth
    wet = nb.maprange(z, 0.5, -0.2)
    col = nb.mix(nb.mul(wet, 0.6), col, (0.0, 0.0, 0.0))
    col = nb.mix(nb.maprange(z, -0.5, -9.0, smooth=True), col, (0.002, 0.018, 0.024))
    rough = nb.mixf(slope_g, 0.75, 0.95)
    rough = nb.mixf(wet, rough, 0.25)
    h = nb.add(nb.mul(rnoise, nb.math('SUBTRACT', 1.0, slope_g)), nb.mul(fine, 0.25))
    bsdf = nb.principled(col, rough, normal=nb.bump(h, 0.6, 0.6))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_mountain():
    mat, nb, out = new_material("VolcanoRock")
    pos = nb.coord('Object')   # the volcano object sits on its own axis
    sx, sy, z = nb.sep(pos)
    nz = nb.sep(nb.geom('Normal'))[2]
    warp = nb.noise(pos, 0.05, 3, 0.5).outputs["Fac"]
    strata = nb.node("ShaderNodeTexWave", {"Vector": nb.vmath('ADD', pos, nb.comb(0, 0, nb.mul(warp, 6.0))),
                                           "Scale": 0.09, "Distortion": 3.0, "Detail": 4.0, "Detail Scale": 2.0},
                     wave_type='BANDS', bands_direction='Z').outputs["Fac"]
    rn = nb.noise(pos, 0.45, 10, 0.62).outputs["Fac"]
    # fractures: warped voronoi edges, only in patches
    cpos = nb.vmath('ADD', pos, nb.vmath('SCALE', nb.noise(pos, 0.25, 3).outputs["Color"], scale=2.5))
    cracks = nb.voronoi(cpos, 0.32, feature='DISTANCE_TO_EDGE').outputs["Distance"]
    crack_m = nb.mul(nb.maprange(cracks, 0.0, 0.025, 1.0, 0.0),
                     nb.maprange(nb.noise(pos, 0.12, 2).outputs["Fac"], 0.42, 0.62))
    streak = nb.noise(nb.vmath('MULTIPLY', pos, (1.0, 1.0, 0.07)), 0.4, 6, 0.6).outputs["Fac"]
    mixv = nb.add(nb.add(nb.mul(strata, 0.22), nb.mul(rn, 0.43)), nb.mul(streak, 0.35))
    base = nb.ramp(mixv, [(0.2, (0.016, 0.015, 0.015)), (0.45, (0.050, 0.043, 0.038)),
                          (0.6, (0.085, 0.068, 0.054)), (0.8, (0.12, 0.10, 0.085))])
    base = nb.mix(nb.mul(crack_m, 0.45), base, (0.005, 0.004, 0.004))
    moss = nb.ramp(nb.noise(pos, 0.3, 4).outputs["Fac"],
                   [(0.35, (0.035, 0.045, 0.016)), (0.6, (0.09, 0.07, 0.025)), (0.75, (0.13, 0.06, 0.025))])
    moss_m = nb.maprange(nb.add(nz, nb.mul(nb.add(rn, -0.5), 0.4)), 0.62, 0.8, smooth=True)
    # no moss in the hot crater
    rxy = nb.vmath('LENGTH', nb.comb(sx, sy, 0.0))
    inside = nb.maprange(rxy, 24.0, 21.0)
    hot = nb.mul(inside, nb.maprange(z, 66.0, LAVA_Z + 0.5))
    moss_m = nb.mul(moss_m, nb.math('SUBTRACT', 1.0, nb.maprange(rxy, 30.0, 24.0)))
    col = nb.mix(moss_m, base, moss)
    col = nb.mix(nb.mul(hot, 0.7), col, (0.01, 0.006, 0.005))
    glow = nb.mul(nb.mul(hot, hot), nb.add(nb.mul(crack_m, 8.0), 0.6))
    h = nb.add(nb.mul(rn, 1.0), nb.mul(crack_m, -0.25))
    bsdf = nb.principled(col, nb.mixf(moss_m, 0.82, 0.95), normal=nb.bump(h, 0.8, 0.8),
                         emit=(1.0, 0.25, 0.04), emit_strength=nb.mul(glow, 3.0))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_rock():
    mat, nb, out = new_material("Rock")
    pos = nb.coord('Object')
    nz = nb.sep(nb.geom('Normal'))[2]
    rnd = nb.obj_info('Random')
    rn = nb.noise(nb.vmath('ADD', pos, nb.comb(rnd, nb.mul(rnd, 3.0), 0.0)), 1.1, 8, 0.6).outputs["Fac"]
    base = nb.ramp(rn, [(0.3, (0.035, 0.032, 0.03)), (0.55, (0.10, 0.09, 0.08)), (0.8, (0.17, 0.155, 0.135))])
    base = nb.mix(nb.mul(rnd, 0.6), base, (0.12, 0.07, 0.045), 'MULTIPLY')
    moss_m = nb.maprange(nb.add(nz, nb.mul(nb.add(rn, -0.5), 0.6)), 0.55, 0.78, smooth=True)
    col = nb.mix(moss_m, base, (0.035, 0.05, 0.018))
    bsdf = nb.principled(col, 0.85, normal=nb.bump(rn, 0.7, 0.3))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_lava():
    mat, nb, out = new_material("Lava")
    pos = nb.coord('Object')
    t = nb.node("ShaderNodeValue")
    time_driver(t.outputs[0], 0.01, 0.0)
    flow = nb.noise(pos, 0.08, 3, 0.5, w=t.outputs[0]).outputs["Color"]
    p2 = nb.vmath('ADD', pos, nb.vmath('SCALE', flow, scale=6.0))
    vor = nb.voronoi(p2, 0.22, feature='DISTANCE_TO_EDGE').outputs["Distance"]
    crust = nb.maprange(vor, 0.02, 0.14, 0.0, 1.0, smooth=True)
    heat = nb.noise(p2, 0.06, 4, 0.55, w=nb.mul(t.outputs[0], 1.7)).outputs["Fac"]
    hot = nb.math('SUBTRACT', 1.0, nb.mul(crust, nb.maprange(heat, 0.35, 0.65, 0.4, 1.0)))
    col = nb.ramp(hot, [(0.0, (0.0, 0.0, 0.0)), (0.35, (0.35, 0.02, 0.0)),
                        (0.7, (1.0, 0.22, 0.02)), (1.0, (1.0, 0.75, 0.25))])
    bsdf = nb.principled((0.02, 0.015, 0.012), 0.6, emit=col, emit_strength=nb.mul(hot, 26.0),
                         normal=nb.bump(crust, 0.6, 0.5))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_water():
    mat, nb, out = new_material("Ocean")
    pos = nb.coord('Object')
    t = nb.node("ShaderNodeValue")
    time_driver(t.outputs[0], 0.012, 0.0)
    w = t.outputs[0]
    swell = nb.noise(nb.vmath('MULTIPLY', pos, (1.0, 2.2, 1.0)), 0.035, 3, 0.5, w=w).outputs["Fac"]
    chop = nb.noise(pos, 0.22, 4, 0.55, w=nb.mul(w, 2.3)).outputs["Fac"]
    ripple = nb.noise(pos, 1.4, 3, 0.55, w=nb.mul(w, 4.0)).outputs["Fac"]
    h = nb.add(nb.add(swell, nb.mul(chop, 0.45)), nb.mul(ripple, 0.12))
    bsdf = nb.principled((0.004, 0.03, 0.045), 0.035, ior=1.333, trans=0.92, spec=0.6,
                         normal=nb.bump(h, 0.35, 0.8))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_foam():
    mat, nb, out = new_material("Foam")
    pos = nb.coord('Object')
    t = nb.node("ShaderNodeValue")
    time_driver(t.outputs[0], 0.015, 0.0)
    edge = nb.attr("edge")
    n1 = nb.noise(pos, 0.25, 6, 0.65, w=t.outputs[0]).outputs["Fac"]
    vor = nb.voronoi(nb.vmath('ADD', pos, nb.comb(nb.mul(t.outputs[0], 3.0), 0, 0)), 0.9,
                     feature='DISTANCE_TO_EDGE').outputs["Distance"]
    lace = nb.maprange(vor, 0.0, 0.09, 1.0, 0.0)
    band = nb.math('POWER', nb.math('SUBTRACT', 1.0, edge), 1.6)
    a = nb.mul(band, nb.add(nb.maprange(n1, 0.5, 0.68), nb.mul(lace, nb.maprange(n1, 0.35, 0.6, 0.0, 0.5))))
    a = nb.math('MINIMUM', nb.mul(a, 0.8), 0.85)
    bsdf = nb.principled((0.75, 0.80, 0.85), 0.5)
    tr = nb.node("ShaderNodeBsdfTransparent")
    mx = nb.node("ShaderNodeMixShader")
    nb.feed(mx.inputs[0], a)
    nb.links.new(tr.outputs[0], mx.inputs[1])
    nb.links.new(bsdf.outputs[0], mx.inputs[2])
    nb.links.new(mx.outputs[0], out.inputs["Surface"])
    _dithered(mat)
    return mat


def simple_material(name, color, rough=0.6, var=0.25, scale=3.0, bump=0.15, metal=0.0,
                    coords='Object', stretch=(1, 1, 1), emit=None, emit_strength=0.0, use_obj_color=False):
    """A noise-varied Principled material, used for most small props."""
    mat, nb, out = new_material(name)
    pos = nb.vmath('MULTIPLY', nb.coord(coords), stretch)
    n = nb.noise(pos, scale, 6, 0.6).outputs["Fac"]
    base = nb.obj_info('Color') if use_obj_color else color
    col = nb.mix(nb.maprange(n, 0.3, 0.7, 0.0, 1.0), nb.mix(1.0, base, (1 - var,) * 3, 'MULTIPLY'),
                 nb.mix(1.0, base, (1 + var,) * 3, 'MULTIPLY'))
    extra = {}
    if emit is not None:
        extra = {"emit": emit, "emit_strength": emit_strength}
    bsdf = nb.principled(col, rough, metal=metal, normal=nb.bump(n, bump, 0.1), **extra)
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_plaster():
    mat, nb, out = new_material("Plaster")
    pos = nb.coord('Object')
    z = nb.sep(pos)[2]
    n = nb.noise(pos, 1.6, 6, 0.6).outputs["Fac"]
    blotch = nb.noise(pos, 0.4, 3, 0.5).outputs["Fac"]
    col = nb.ramp(nb.add(nb.mul(n, 0.4), nb.mul(blotch, 0.6)),
                  [(0.3, (0.38, 0.34, 0.27)), (0.6, (0.56, 0.51, 0.42)), (0.8, (0.62, 0.58, 0.49))])
    grime = nb.mul(nb.maprange(z, 1.2, -0.2), 0.6)
    col = nb.mix(grime, col, (0.12, 0.10, 0.07))
    bsdf = nb.principled(col, 0.9, normal=nb.bump(n, 0.12, 0.05))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_timber():
    mat, nb, out = new_material("Timber")
    uv = nb.coord('UV')
    grain = nb.noise(nb.vmath('MULTIPLY', uv, (2.0, 40.0, 1.0)), 2.0, 6, 0.6).outputs["Fac"]
    rnd = nb.obj_info('Random')
    col = nb.ramp(nb.add(grain, nb.mul(rnd, 0.2)),
                  [(0.3, (0.022, 0.012, 0.007)), (0.65, (0.055, 0.032, 0.018)), (0.9, (0.075, 0.045, 0.026))])
    bsdf = nb.principled(col, 0.75, normal=nb.bump(grain, 0.3, 0.02))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_stonewall():
    mat, nb, out = new_material("StoneWall")
    uv = nb.coord('UV')
    pos = nb.coord('Object')
    warp = nb.noise(pos, 1.5, 2, 0.5).outputs["Color"]
    vec = nb.vmath('ADD', uv, nb.vmath('SCALE', nb.vmath('SUBTRACT', warp, (0.5, 0.5, 0.5)), scale=0.06))
    br = nb.node("ShaderNodeTexBrick", {"Vector": vec, "Scale": 1.0, "Mortar Size": 0.025,
                                        "Mortar Smooth": 0.3, "Bias": 0.0, "Brick Width": 0.55,
                                        "Row Height": 0.28, "Color1": (0.20, 0.18, 0.15),
                                        "Color2": (0.11, 0.10, 0.09), "Mortar": (0.04, 0.035, 0.03)},
                     offset=0.5, squash=1.0)
    n = nb.noise(pos, 4.0, 6, 0.6).outputs["Fac"]
    col = nb.mix(nb.mul(n, 0.5), br.outputs["Color"], (0.05, 0.05, 0.045), 'MULTIPLY')
    h = nb.add(nb.math('SUBTRACT', 1.0, br.outputs["Fac"]), nb.mul(n, 0.3))
    bsdf = nb.principled(col, 0.9, normal=nb.bump(h, 0.6, 0.05))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_roof():
    """Clay/slate tiles. The tint comes from each house's Object Colour."""
    mat, nb, out = new_material("RoofTiles")
    uv = nb.coord('UV')
    pos = nb.coord('Object')
    br = nb.node("ShaderNodeTexBrick", {"Vector": uv, "Scale": 1.0, "Mortar Size": 0.012,
                                        "Mortar Smooth": 0.2, "Brick Width": 0.30, "Row Height": 0.22,
                                        "Color1": (1.0, 1.0, 1.0), "Color2": (0.72, 0.72, 0.72),
                                        "Mortar": (0.05, 0.05, 0.05)}, offset=0.5, squash=1.0)
    v = nb.sep(uv)[1]
    row = nb.math('FRACT', nb.math('DIVIDE', v, 0.22))
    lip = nb.maprange(row, 0.0, 0.35, 0.55, 1.0)  # shadow under each tile's lower edge
    n = nb.noise(pos, 3.0, 5, 0.6).outputs["Fac"]
    moss = nb.maprange(nb.noise(pos, 0.7, 4).outputs["Fac"], 0.55, 0.75)
    tint = nb.obj_info('Color')
    col = nb.mix(1.0, br.outputs["Color"], tint, 'MULTIPLY')
    col = nb.mix(1.0, col, nb.comb(lip, lip, lip), 'MULTIPLY')
    col = nb.mix(nb.mul(moss, 0.45), col, (0.04, 0.05, 0.02))
    col = nb.mix(nb.mul(n, 0.3), col, (0.0, 0.0, 0.0))
    h = nb.add(nb.mul(row, 0.6), nb.mul(br.outputs["Fac"], -0.6))
    bsdf = nb.principled(col, 0.6, normal=nb.bump(h, 0.5, 0.03))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_window(lit):
    mat, nb, out = new_material("WindowLit" if lit else "WindowDark")
    if lit:
        uv = nb.coord('Object')
        n = nb.noise(uv, 2.0, 2, 0.5).outputs["Fac"]
        rnd = nb.obj_info('Random')
        warm = nb.mix(rnd, WARM, blackbody(2900))
        strength = nb.mul(nb.maprange(n, 0.3, 0.7, 0.5, 1.0), 7.0)
        bsdf = nb.principled((0.02, 0.02, 0.02), 0.08, emit=warm, emit_strength=strength, spec=0.8)
    else:
        bsdf = nb.principled((0.006, 0.008, 0.012), 0.06, spec=0.9, emit=(0.15, 0.2, 0.35), emit_strength=0.05)
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def shadow_clear(nb, shader_out, out):
    """Glowing glass and flames: visible, but they let the light inside out."""
    lp = nb.node("ShaderNodeLightPath")
    tr = nb.node("ShaderNodeBsdfTransparent")
    mx = nb.node("ShaderNodeMixShader")
    nb.links.new(lp.outputs["Is Shadow Ray"], mx.inputs[0])
    nb.links.new(shader_out, mx.inputs[1])
    nb.links.new(tr.outputs[0], mx.inputs[2])
    nb.links.new(mx.outputs[0], out.inputs["Surface"])


def mat_emissive(name, color, strength):
    mat, nb, out = new_material(name)
    em = nb.node("ShaderNodeEmission", {"Color": color, "Strength": strength})
    shadow_clear(nb, em.outputs[0], out)
    return mat


def mat_leaves():
    """Autumn foliage. Hue comes from the tree's Object Colour (red channel)."""
    mat, nb, out = new_material("AutumnLeaves")
    pos = nb.coord('Object')
    hue = nb.sep(nb.obj_info('Color'))[0]
    var = nb.attr("var")
    ao = nb.attr("ao")
    n = nb.noise(pos, 1.6, 4, 0.6).outputs["Fac"]
    f = nb.add(nb.add(hue, nb.mul(nb.add(var, -0.5), 0.22)), nb.mul(nb.add(n, -0.5), 0.25))
    col = nb.ramp(f, AUTUMN_STOPS)
    col = nb.mix(nb.mul(ao, 0.6), col, (0.0, 0.0, 0.0))
    leafy = nb.voronoi(pos, 6.0).outputs["Distance"]
    bsdf = nb.principled(col, 0.65, sheen=0.4, normal=nb.bump(leafy, 0.45, 0.1))
    tl = nb.node("ShaderNodeBsdfTranslucent", {"Color": nb.mix(1.0, col, (1.4, 1.2, 0.9), 'MULTIPLY')})
    mx = nb.node("ShaderNodeMixShader", {"Fac": 0.35})
    nb.links.new(bsdf.outputs[0], mx.inputs[1])
    nb.links.new(tl.outputs[0], mx.inputs[2])
    nb.links.new(mx.outputs[0], out.inputs["Surface"])
    return mat


AUTUMN_STOPS = [(0.00, (0.20, 0.012, 0.008)), (0.22, (0.42, 0.030, 0.012)), (0.42, (0.66, 0.12, 0.015)),
                (0.62, (0.78, 0.30, 0.020)), (0.80, (0.78, 0.52, 0.05)), (0.92, (0.40, 0.42, 0.05)),
                (1.00, (0.12, 0.22, 0.04))]


def mat_foliage_attr(name, stops, sheen=0.3):
    """Foliage whose colour comes from a per-vertex 'var' attribute (bushes, fallen leaves, flowers)."""
    mat, nb, out = new_material(name)
    pos = nb.coord('Object')
    var = nb.attr("var")
    ao = nb.attr("ao")
    n = nb.noise(pos, 2.0, 4, 0.6).outputs["Fac"]
    col = nb.ramp(nb.add(var, nb.mul(nb.add(n, -0.5), 0.12)), stops)
    col = nb.mix(nb.mul(ao, 0.8), col, (0.0, 0.0, 0.0))
    bsdf = nb.principled(col, 0.7, sheen=sheen, normal=nb.bump(nb.voronoi(pos, 8.0).outputs["Distance"], 0.4, 0.1))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_cobble(name, dirt=False):
    mat, nb, out = new_material(name)
    pos = nb.coord('Object')
    edge = nb.attr("edge")
    n = nb.noise(pos, 0.6, 4, 0.55).outputs["Fac"]
    fine = nb.noise(pos, 6.0, 4, 0.6).outputs["Fac"]
    if dirt:
        col = nb.ramp(nb.add(nb.mul(n, 0.7), nb.mul(fine, 0.3)),
                      [(0.3, (0.07, 0.05, 0.035)), (0.7, (0.16, 0.12, 0.08))])
        h = fine
        rough = 0.95
    else:
        warp = nb.vmath('ADD', pos, nb.vmath('SCALE', nb.noise(pos, 1.2, 2).outputs["Color"], scale=0.25))
        vor = nb.voronoi(warp, 1.7)
        dte = nb.voronoi(warp, 1.7, feature='DISTANCE_TO_EDGE').outputs["Distance"]
        stone = nb.maprange(dte, 0.02, 0.12, 0.0, 1.0, smooth=True)
        scol = nb.ramp(nb.sep(vor.outputs["Color"])[0],
                       [(0.0, (0.07, 0.066, 0.06)), (0.5, (0.13, 0.12, 0.11)), (1.0, (0.19, 0.175, 0.155))])
        scol = nb.mix(nb.mul(n, 0.5), scol, (0.08, 0.07, 0.05), 'MULTIPLY')
        col = nb.mix(stone, (0.035, 0.03, 0.025), scol)
        h = nb.add(stone, nb.mul(fine, 0.15))
        rough = 0.8
    # the edges blend into dirt and then fade out so roads sink into the grass
    dirt_col = (0.07, 0.06, 0.035)
    col = nb.mix(nb.maprange(nb.add(edge, nb.mul(nb.add(n, -0.5), 0.5)), 0.55, 0.85), col, dirt_col)
    alpha = nb.maprange(nb.add(edge, nb.mul(nb.add(fine, -0.5), 0.4)), 0.8, 1.0, 1.0, 0.0)
    bsdf = nb.principled(col, rough, normal=nb.bump(h, 0.6, 0.06))
    tr = nb.node("ShaderNodeBsdfTransparent")
    mx = nb.node("ShaderNodeMixShader")
    nb.feed(mx.inputs[0], alpha)
    nb.links.new(tr.outputs[0], mx.inputs[1])
    nb.links.new(bsdf.outputs[0], mx.inputs[2])
    nb.links.new(mx.outputs[0], out.inputs["Surface"])
    _dithered(mat)
    return mat


def mat_bands(name, c1, c2, period, axis=2, rough=0.5, coords='Object'):
    """Two-colour stripes (lighthouse bands, market awnings)."""
    mat, nb, out = new_material(name)
    p = nb.sep(nb.coord(coords))[axis]
    f = nb.math('GREATER_THAN', nb.math('FRACT', nb.math('DIVIDE', p, period)), 0.5)
    n = nb.noise(nb.coord('Object'), 3.0, 5).outputs["Fac"]
    col = nb.mix(f, c1, c2)
    col = nb.mix(nb.mul(n, 0.3), col, (0.0, 0.0, 0.0))
    bsdf = nb.principled(col, rough, normal=nb.bump(n, 0.1, 0.05))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_cave():
    """Deep tunnel: almost black, with a faint warm glow further in."""
    mat, nb, out = new_material("CaveDepth")
    z = nb.sep(nb.coord('Generated'))[2]
    bsdf = nb.principled((0.004, 0.003, 0.003), 0.9, emit=TORCH, emit_strength=nb.maprange(z, 0.0, 1.0, 0.25, 0.0))
    nb.links.new(bsdf.outputs[0], out.inputs["Surface"])
    return mat


def mat_glass():
    mat, nb, out = new_material("LanternGlass")
    em = nb.principled((0.9, 0.8, 0.6), 0.2, emit=WARM, emit_strength=22.0)
    shadow_clear(nb, em.outputs[0], out)
    return mat


def build_materials():
    M.terrain = mat_terrain()
    M.mountain = mat_mountain()
    M.rock = mat_rock()
    M.lava = mat_lava()
    M.water = mat_water()
    M.foam = mat_foam()
    M.seafloor = simple_material("SeaFloor", (0.004, 0.02, 0.026), 0.9, scale=0.05)
    M.plaster = mat_plaster()
    M.timber = mat_timber()
    M.stonewall = mat_stonewall()
    M.roof = mat_roof()
    M.win_lit = mat_window(True)
    M.win_dark = mat_window(False)
    M.door = simple_material("DoorWood", (0.05, 0.022, 0.01), 0.6, stretch=(1, 1, 12), scale=4)
    M.shutter = simple_material("Shutters", (1, 1, 1), 0.55, use_obj_color=True, stretch=(1, 1, 10), scale=3)
    M.stone = simple_material("Stone", (0.12, 0.11, 0.10), 0.85, var=0.35, scale=2.5, bump=0.4)
    M.iron = simple_material("BlackIron", (0.015, 0.015, 0.016), 0.45, metal=0.8, var=0.1)
    M.glass = mat_glass()
    M.wood = simple_material("Planks", (0.09, 0.06, 0.04), 0.8, var=0.4, stretch=(1, 1, 8), scale=2)
    M.bark = simple_material("Bark", (0.035, 0.026, 0.02), 0.9, var=0.4, stretch=(1, 1, 0.15), scale=6, bump=0.6)
    M.leaves = mat_leaves()
    M.conifer = mat_foliage_attr("Conifer", [(0.0, (0.008, 0.025, 0.012)), (1.0, (0.03, 0.06, 0.025))], 0.2)
    M.bush = mat_foliage_attr("Bushes", [(0.0, (0.02, 0.04, 0.012)), (0.45, (0.06, 0.07, 0.02)),
                                         (0.7, (0.30, 0.10, 0.012)), (1.0, (0.45, 0.18, 0.015))])
    M.fallen = mat_foliage_attr("FallenLeaves", AUTUMN_STOPS, 0.2)
    M.hedge = mat_foliage_attr("Hedge", [(0.0, (0.012, 0.03, 0.01)), (1.0, (0.035, 0.06, 0.02))], 0.3)
    M.flowers = mat_foliage_attr("Flowers", [(0.0, (0.55, 0.01, 0.02)), (0.5, (0.65, 0.04, 0.06)),
                                             (0.7, (0.7, 0.18, 0.30)), (0.85, (0.75, 0.55, 0.06)),
                                             (1.0, (0.8, 0.78, 0.72))], 0.5)
    M.cobble = mat_cobble("Cobblestones")
    M.dirt = mat_cobble("DirtPath", dirt=True)
    M.paint = simple_material("BoatPaint", (1, 1, 1), 0.45, use_obj_color=True, stretch=(1, 1, 6))
    M.canvas = simple_material("Canvas", (0.55, 0.5, 0.4), 0.85, var=0.15, scale=8)
    M.awning = mat_bands("Awning", (0.42, 0.04, 0.03), (0.6, 0.55, 0.45), 0.5, axis=0, coords='UV')
    M.tower = mat_bands("LighthouseBands", (0.62, 0.6, 0.56), (0.35, 0.02, 0.015), 6.0, axis=2)
    M.redmetal = simple_material("RedMetal", (0.30, 0.02, 0.015), 0.4, metal=0.6, var=0.1)
    M.cave = mat_cave()
    M.flame = mat_emissive("Flame", TORCH, 40.0)
    M.beacon = mat_emissive("Beacon", blackbody(4200), 120.0)
    M.ember = mat_emissive("Ember", (1.0, 0.28, 0.03), 30.0)
    M.bolt = mat_emissive("Lightning", (0.70, 0.80, 1.0), 60.0)
    M.water_small = simple_material("PoolWater", (0.01, 0.025, 0.03), 0.05, var=0.05, scale=1.0)


# ----------------------------------------------------------------------------
# Terrain, sea, foam
# ----------------------------------------------------------------------------
def build_terrain(coll):
    import numpy as np
    step = CONFIG["TERRAIN_STEP"]
    x0, x1 = -ISLAND_RX * 1.42, ISLAND_RX * 1.42
    y0, y1 = -ISLAND_RY * 1.48, ISLAND_RY * 1.48
    nx, ny = int((x1 - x0) / step) + 1, int((y1 - y0) / step) + 1
    xs = [x0 + i * step for i in range(nx)]
    ys = [y0 + j * step for j in range(ny)]
    H = np.empty((ny, nx))
    for j, y in enumerate(ys):
        row = H[j]
        for i, x in enumerate(xs):
            row[i] = terrain_height(x, y)
    gy, gx = np.gradient(H, step)
    slope = np.sqrt(gx * gx + gy * gy)
    verts = []
    for j, y in enumerate(ys):
        for i, x in enumerate(xs):
            z = H[j, i]
            s = slope[j, i]
            if s > 0.45 and z > -6.0:
                # roughen cliffs sideways so they read as rock, not a smooth ramp
                k = min(1.0, (s - 0.45) * 1.2)
                z += k * 0.9 * n3(x * 0.25, y * 0.25, z * 0.3 + 50.0)
                x += k * 1.4 * n3(x * 0.12, y * 0.12, z * 0.25 + 11.0)
                y += k * 1.4 * n3(x * 0.12 + 40.0, y * 0.12, z * 0.25 + 3.0)
            verts.append((x, y, z))
    faces = []
    for j in range(ny - 1):
        for i in range(nx - 1):
            a = j * nx + i
            faces.append((a, a + 1, a + nx + 1, a + nx))
    me = bpy.data.meshes.new(PREFIX + "Terrain")
    me.from_pydata(verts, [], faces)
    me.materials.append(M.terrain)
    me.polygons.foreach_set("use_smooth", [True] * len(faces))
    me.update()
    ob = link(bpy.data.objects.new("Island Terrain", me), coll)

    # deep sea floor beyond the terrain grid
    sf = MeshBuilder()
    sf.add([(-5000, -5000, SEA_FLOOR - 0.3), (5000, -5000, SEA_FLOOR - 0.3),
            (5000, 5000, SEA_FLOOR - 0.3), (-5000, 5000, SEA_FLOOR - 0.3)], [(0, 1, 2, 3)], M.seafloor)
    sf.build("Sea Floor", coll)
    return ob


def build_ocean(coll):
    mb = MeshBuilder()
    R = 6000.0
    mb.add([(-R, -R, 0), (R, -R, 0), (R, R, 0), (-R, R, 0)], [(0, 1, 2, 3)], M.water)
    ob = mb.build("Ocean", coll)
    return ob


def shoreline(samples=900):
    """Points where the terrain crosses sea level, walking around the island."""
    pts = []
    for k in range(samples):
        a = tau * k / samples
        prev = None
        r = 0.80
        while r < 1.25:
            p = point_at_island(a, r)
            h = terrain_height(p.x, p.y)
            if h < 0.0:
                if prev is not None:
                    hp, pp = prev
                    t = hp / (hp - h)
                    p = pp.lerp(p, t)
                pts.append(Vector((p.x, p.y, 0.0)))
                break
            prev = (h, p)
            r += 0.004
        else:
            pts.append(point_at_island(a, 1.0))
    return pts


def build_foam(coll):
    pts = shoreline()
    n = len(pts)
    verts, faces, edge = [], [], []
    rows = [(-1.0, 0.0), (0.0, 0.05), (3.0, 0.35), (7.0, 0.7), (13.0, 1.0)]
    for i, p in enumerate(pts):
        outward = (p - pts[i - 1]).cross(Vector((0, 0, 1)))
        outward += (pts[(i + 1) % n] - p).cross(Vector((0, 0, 1)))
        outward.normalize()
        d, a = island_polar(p.x, p.y)
        wide = 1.0 + 0.8 * beach_weight(a)  # foam spreads further on beaches
        for off, e in rows:
            q = p + outward * off * wide
            verts.append((q.x, q.y, 0.03))
            edge.append(e)
    m = len(rows)
    for i in range(n):
        j = (i + 1) % n
        for r in range(m - 1):
            faces.append((i * m + r, j * m + r, j * m + r + 1, i * m + r + 1))
    mb = MeshBuilder()
    mb.add(verts, faces, M.foam, attrs={"edge": edge})
    return mb.build("Shore Foam", coll)


# ----------------------------------------------------------------------------
# The volcano
# ----------------------------------------------------------------------------
def build_mountain(coll):
    segs = 288
    # resample the profile by arc length
    pts = [Vector((r, z)) for r, z in MOUNT_PROFILE]
    rings = [pts[0]]
    for a, b in zip(pts, pts[1:]):
        n = max(1, int((b - a).length / 0.62))
        for k in range(1, n + 1):
            rings.append(a.lerp(b, k / n))
    verts, faces = [], []
    last = len(rings) - 1
    for i, rz in enumerate(rings[:-1]):
        for k in range(segs):
            th = tau * k / segs
            x, y, z = mountain_point(th, rz.x, rz.y)
            verts.append((x - MOUNT_C.x, y - MOUNT_C.y, z))
    centre = len(verts)
    verts.append((0.0, 0.0, rings[-1].y))
    for i in range(last - 1):
        for k in range(segs):
            a, b = i * segs + k, i * segs + (k + 1) % segs
            faces.append((a, b, b + segs, a + segs))
    top = (last - 1) * segs
    for k in range(segs):
        faces.append((top + k, top + (k + 1) % segs, centre))
    mb = MeshBuilder()
    mb.add(verts, faces, M.mountain, smooth=True)
    ob = mb.build("Volcano", coll, location=(MOUNT_C.x, MOUNT_C.y, 0.0))

    # lava lake
    lm = MeshBuilder()
    ring_n, ring_r = 96, 21.0
    lv = [(0.0, 0.0, LAVA_Z)]
    lf = []
    for rr in range(1, 9):
        for k in range(ring_n):
            a = tau * k / ring_n
            r = ring_r * rr / 8
            lv.append((cos(a) * r, sin(a) * r, LAVA_Z + 0.15 * n3(cos(a) * r * 0.2, sin(a) * r * 0.2, 4.0)))
    for k in range(ring_n):
        lf.append((0, 1 + k, 1 + (k + 1) % ring_n))
    for rr in range(7):
        for k in range(ring_n):
            a = 1 + rr * ring_n + k
            b = 1 + rr * ring_n + (k + 1) % ring_n
            lf.append((a, a + ring_n, b + ring_n, b))
    lf = [tuple(reversed(f)) for f in lf]
    lm.add(lv, lf, M.lava, smooth=True)
    lava = lm.build("Lava Lake", coll, location=(MOUNT_C.x, MOUNT_C.y, 0.0))
    return ob, lava


# ----------------------------------------------------------------------------
# Volumes: eruption cloud and ground fog
# ----------------------------------------------------------------------------
def gn_points_to_volume(name, mat, voxel):
    ng = bpy.data.node_groups.new(PREFIX + name, 'GeometryNodeTree')
    ng.interface.new_socket(name="Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    ng.interface.new_socket(name="Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')
    nb = Nodes(ng)
    gi = nb.node("NodeGroupInput")
    go = nb.node("NodeGroupOutput")
    rad = nb.node("GeometryNodeInputNamedAttribute", {"Name": "pr"}, data_type='FLOAT')
    m2p = nb.node("GeometryNodeMeshToPoints")
    nb.links.new(gi.outputs[0], m2p.inputs["Mesh"])
    nb.links.new(nb.out(rad, "Attribute"), m2p.inputs["Radius"])
    p2v = nb.node("GeometryNodePointsToVolume")
    sock = find_socket(p2v.inputs, "Resolution Mode") if any(s.name == "Resolution Mode" for s in p2v.inputs) else None
    if sock is not None:
        for v in ("Size", "Voxel Size"):
            try:
                sock.default_value = v
                break
            except (TypeError, ValueError):
                pass
    else:
        _try_set(p2v, "resolution_mode", 'VOXEL_SIZE')
    p2v.inputs["Voxel Size"].default_value = voxel
    p2v.inputs["Density"].default_value = 1.0
    rad2 = nb.node("GeometryNodeInputRadius")
    nb.links.new(m2p.outputs[0], p2v.inputs["Points"])
    nb.links.new(rad2.outputs[0], p2v.inputs["Radius"])
    sm = nb.node("GeometryNodeSetMaterial")
    sm.inputs["Material"].default_value = mat
    nb.links.new(p2v.outputs[0], sm.inputs["Geometry"])
    nb.links.new(sm.outputs[0], go.inputs[0])
    return ng


def mat_cloud():
    mat, nb, out = new_material("EruptionCloud")
    pos = nb.coord('Object')
    z = nb.sep(pos)[2]
    t = nb.node("ShaderNodeValue")
    time_driver(t.outputs[0], 0.004, 0.0)
    dens = nb.attr("density")
    warp = nb.noise(pos, 0.012, 2, 0.5, w=t.outputs[0]).outputs["Color"]
    p2 = nb.vmath('ADD', pos, nb.vmath('SCALE', warp, scale=22.0))
    billow = nb.noise(p2, 0.05, 6, 0.6, w=t.outputs[0]).outputs["Fac"]
    detail = nb.noise(p2, 0.22, 4, 0.6).outputs["Fac"]
    shape = nb.math('SUBTRACT', nb.mul(dens, 1.3), nb.add(nb.mul(nb.math('SUBTRACT', 1.0, billow), 0.95),
                                                          nb.mul(nb.math('SUBTRACT', 1.0, detail), 0.35)))
    shape = nb.math('MAXIMUM', shape, 0.0)
    d = nb.mul(nb.math('MINIMUM', nb.mul(shape, 2.5), 1.0), nb.maprange(z, 62.0, 82.0, 0.025, 0.11))
    # ash is darker and denser low in the column, lit orange from the crater
    low = nb.maprange(z, 120.0, 62.0, smooth=True)
    ash = nb.noise(pos, 0.018, 3, 0.5, w=nb.mul(t.outputs[0], 0.7)).outputs["Fac"]
    top = nb.mix(nb.maprange(ash, 0.38, 0.62, smooth=True), (0.40, 0.38, 0.38), (0.80, 0.82, 0.88))
    col = nb.mix(low, top, (0.30, 0.26, 0.24))
    glow = nb.mul(nb.mul(nb.maprange(z, 105.0, 58.0, smooth=True), nb.maprange(billow, 0.3, 0.7, 1.0, 0.3)), d)
    pv = nb.node("ShaderNodeVolumePrincipled", {"Color": col, "Density": d, "Anisotropy": 0.35,
                                                "Absorption Color": (0.05, 0.05, 0.06),
                                                "Emission Color": (1.0, 0.28, 0.05),
                                                "Emission Strength": nb.mul(glow, 4.5)})
    nb.links.new(pv.outputs[0], out.inputs["Volume"])
    _volume_settings(mat)
    return mat


def add_puff(pts, x, y, z, r, rng, levels, up=0.35):
    """A puff plus smaller puffs on its surface: the cauliflower look."""
    pts.append((x, y, z, r))
    if levels <= 0 or r < 2.5:
        return
    for _ in range(3 if levels > 1 else 2):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1) + up)).normalized()
        cr = r * rng.uniform(0.34, 0.5)
        p = Vector((x, y, z)) + d * r * rng.uniform(0.72, 0.92)
        add_puff(pts, p.x, p.y, p.z, cr, rng, levels - 1, up)


def build_cloud(coll):
    rng = random.Random(CONFIG["SEED"] * 3 + 1)
    pts = []
    cx, cy = MOUNT_C.x, MOUNT_C.y
    drift = Vector((10.0, 14.0))

    def lean(z):
        t = clamp((z - 60.0) / 120.0)
        return Vector((cx, cy)) + drift * (t * t) + Vector((4.0 * sin(t * 5.0), 3.0 * sin(t * 3.0 + 1.0)))

    # rising column out of the crater
    z = 62.0
    while z < 160.0:
        t = (z - 62.0) / 98.0
        R = lerp(10.0, 27.0, t ** 0.7)
        c = lean(z)
        pts.append((c.x, c.y, z, R * 0.7))
        for _ in range(6):
            a = rng.uniform(0, tau)
            rr = R * rng.uniform(0.45, 0.8)
            add_puff(pts, c.x + cos(a) * rr, c.y + sin(a) * rr, z + rng.uniform(-2, 2),
                     R * rng.uniform(0.3, 0.45), rng, 1, up=0.0)
        z += 3.5
    # condensation collar halfway up
    zc = 118.0
    c = lean(zc)
    for k in range(70):
        a = tau * k / 70 + rng.uniform(-0.04, 0.04)
        if n3(cos(a) * 2.6, sin(a) * 2.6, 55.0) > 0.32:   # tears in the ring
            continue
        Rr = 50.0 * (1.0 + 0.14 * n3(cos(a) * 2.0, sin(a) * 2.0, 31.0))
        zc_k = zc + 5.0 * n3(cos(a) * 1.7, sin(a) * 1.7, 12.0)
        for fr, rad in ((1.0, (5.0, 7.5)), (0.78, (6.0, 8.5)), (0.56, (6.0, 8.5))):
            add_puff(pts, c.x + cos(a) * Rr * fr, c.y + sin(a) * Rr * fr, zc_k + rng.uniform(-2.0, 2.0),
                     rng.uniform(*rad), rng, 1 if fr == 1.0 else 0, up=0.0)
    # mushroom cap: a rolling torus with a domed top
    zt = 178.0
    c = lean(zt)
    Rmaj, Rmin = 62.0, 24.0
    for i in range(56):
        u = tau * i / 56 + rng.uniform(-0.03, 0.03)
        wob = 1.0 + 0.08 * n3(cos(u) * 2.5, sin(u) * 2.5, 77.0)
        for j in range(9):
            v = tau * j / 9 + rng.uniform(-0.15, 0.15)
            rr = (Rmaj + Rmin * 0.62 * cos(v)) * wob
            zz = zt + Rmin * 0.62 * 0.8 * sin(v)
            # puffs facing outwards and upwards carry the finest billows
            outer = max(cos(v), sin(v))
            add_puff(pts, c.x + cos(u) * rr, c.y + sin(u) * rr, zz, Rmin * rng.uniform(0.4, 0.55), rng,
                     2 if outer > 0.0 else 1, up=0.2)
    for _ in range(70):
        a = rng.uniform(0, tau)
        r = Rmaj * sqrt(rng.uniform(0, 1))
        dome = 1.0 - (r / Rmaj) ** 2
        add_puff(pts, c.x + cos(a) * r, c.y + sin(a) * r, zt + 6.0 + 18.0 * dome + rng.uniform(-4, 4),
                 rng.uniform(11, 16), rng, 2, up=0.8)
    # ash curtain hanging under the cap
    for _ in range(70):
        a = rng.uniform(0, tau)
        r = rng.uniform(25.0, 55.0)
        add_puff(pts, c.x + cos(a) * r, c.y + sin(a) * r, zt - rng.uniform(14.0, 22.0), rng.uniform(6.0, 9.0),
                 rng, 1, up=-0.6)

    me = bpy.data.meshes.new(PREFIX + "CloudPoints")
    me.from_pydata([p[:3] for p in pts], [], [])
    at = me.attributes.new("pr", 'FLOAT', 'POINT')
    at.data.foreach_set("value", [p[3] for p in pts])
    cmat = mat_cloud()
    me.materials.append(cmat)
    ob = link(bpy.data.objects.new("Eruption Cloud", me), coll)
    md = ob.modifiers.new("Points to Volume", 'NODES')
    md.node_group = gn_points_to_volume("CloudVolume", cmat, 1.4)
    return ob


def build_fog(coll):
    mat, nb, out = new_material("GroundFog")
    pos = nb.coord('Object')
    z = nb.sep(nb.geom('Position'))[2]
    t = nb.node("ShaderNodeValue")
    time_driver(t.outputs[0], 0.003, 0.0)
    n = nb.noise(pos, 0.9, 3, 0.55, w=t.outputs[0]).outputs["Fac"]
    falloff = nb.math('EXPONENT', nb.mul(nb.math('MAXIMUM', nb.add(z, -1.0), 0.0), -1.0 / 16.0))
    dens = nb.mul(nb.mul(falloff, nb.maprange(n, 0.3, 0.7, 0.35, 1.5)), CONFIG["FOG_DENSITY"])
    pv = nb.node("ShaderNodeVolumePrincipled", {"Color": (0.55, 0.62, 0.78), "Density": dens, "Anisotropy": 0.55})
    nb.links.new(pv.outputs[0], out.inputs["Volume"])
    _volume_settings(mat)
    mb = MeshBuilder()
    mb.box(TRS((0, 0, 29.0), scale=(1400.0, 1400.0, 62.0)), mat)
    ob = mb.build("Ground Fog", coll)
    ob.display_type = 'BOUNDS'
    _try_set(ob, "visible_shadow", False)
    return ob


def build_embers(coll):
    rng = random.Random(5)
    verts, phase = [], []
    for _ in range(380):
        a = rng.uniform(0, tau)
        r = 17.0 * sqrt(rng.uniform(0, 1))
        verts.append((MOUNT_C.x + cos(a) * r, MOUNT_C.y + sin(a) * r, LAVA_Z + 1.0))
        phase.append(rng.random())
    me = bpy.data.meshes.new(PREFIX + "EmberSeeds")
    me.from_pydata(verts, [], [])
    at = me.attributes.new("phase", 'FLOAT', 'POINT')
    at.data.foreach_set("value", phase)
    me.materials.append(M.ember)
    ob = link(bpy.data.objects.new("Embers", me), coll)

    ng = bpy.data.node_groups.new(PREFIX + "Embers", 'GeometryNodeTree')
    ng.interface.new_socket(name="Geometry", in_out='INPUT', socket_type='NodeSocketGeometry')
    ng.interface.new_socket(name="Geometry", in_out='OUTPUT', socket_type='NodeSocketGeometry')
    nb = Nodes(ng)
    gi, go = nb.node("NodeGroupInput"), nb.node("NodeGroupOutput")
    ph = nb.out(nb.node("GeometryNodeInputNamedAttribute", {"Name": "phase"}, data_type='FLOAT'), "Attribute")
    frame = nb.node("GeometryNodeInputSceneTime").outputs["Frame"]
    life = nb.math('FRACT', nb.add(ph, nb.mul(frame, 0.004)))
    pos = nb.node("GeometryNodeInputPosition").outputs[0]
    rel = nb.vmath('SUBTRACT', pos, (MOUNT_C.x, MOUNT_C.y, 0.0))
    rx, ry, _ = nb.sep(rel)
    sway = nb.noise(pos, 0.05, 1, 0.5, w=nb.mul(ph, 10.0)).outputs["Color"]
    up = nb.mul(life, 55.0)
    off = nb.comb(nb.mul(rx, nb.mul(life, 1.1)), nb.mul(ry, nb.mul(life, 1.1)), up)
    off = nb.vmath('ADD', off, nb.vmath('SCALE', nb.vmath('SUBTRACT', sway, (0.5, 0.5, 0.5)), scale=nb.mul(life, 30.0)))
    sp = nb.node("GeometryNodeSetPosition")
    nb.links.new(gi.outputs[0], sp.inputs["Geometry"])
    nb.links.new(off, sp.inputs["Offset"])
    m2p = nb.node("GeometryNodeMeshToPoints")
    nb.links.new(sp.outputs[0], m2p.inputs["Mesh"])
    nb.links.new(nb.mul(nb.math('SUBTRACT', 1.0, life), 0.28), m2p.inputs["Radius"])
    sm = nb.node("GeometryNodeSetMaterial")
    sm.inputs["Material"].default_value = M.ember
    nb.links.new(m2p.outputs[0], sm.inputs["Geometry"])
    nb.links.new(sm.outputs[0], go.inputs[0])
    md = ob.modifiers.new("Rising Embers", 'NODES')
    md.node_group = ng
    return ob


def build_lightning(coll):
    rng = random.Random(CONFIG["SEED"] + 99)
    cu = bpy.data.curves.new(PREFIX + "Lightning", 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = 0.22
    cu.bevel_resolution = 1

    def bolt(start, end, steps, jag):
        pts = []
        for i in range(steps + 1):
            t = i / steps
            p = start.lerp(end, t)
            if 0 < i < steps:
                p += Vector((rng.uniform(-jag, jag), rng.uniform(-jag, jag), rng.uniform(-jag, jag) * 0.4))
            pts.append(p)
        sp = cu.splines.new('POLY')
        sp.points.add(len(pts) - 1)
        for k, p in enumerate(pts):
            sp.points[k].co = (p.x, p.y, p.z, 1.0)
        return pts

    c = Vector((MOUNT_C.x + 6.0, MOUNT_C.y - 4.0, 0.0))
    main = bolt(c + Vector((-34.0, -30.0, 165.0)), c + Vector((-8.0, -12.0, 118.0)), 18, 3.2)
    for k in (5, 9, 13):
        s = main[k]
        bolt(s, s + Vector((rng.uniform(-14, 4), rng.uniform(-14, 0), -rng.uniform(8, 16))), 7, 1.8)
    bolt(c + Vector((30.0, -24.0, 172.0)), c + Vector((48.0, -36.0, 150.0)), 10, 2.0)
    cu.materials.append(M.bolt)
    ob = link(bpy.data.objects.new("Lightning", cu), coll)
    point_light("Lightning Flash", c + Vector((-22.0, -20.0, 150.0)), 1.2e5, (0.70, 0.80, 1.0), 6.0, coll)
    return ob


# ----------------------------------------------------------------------------
# Roads
# ----------------------------------------------------------------------------
def catmull_rom(pts, step=1.0):
    P = [Vector((p[0], p[1], 0.0)) for p in pts]
    P = [P[0] + (P[0] - P[1])] + P + [P[-1] + (P[-1] - P[-2])]
    out = []
    for i in range(1, len(P) - 2):
        p0, p1, p2, p3 = P[i - 1], P[i], P[i + 1], P[i + 2]
        n = max(2, int((p2 - p1).length / step))
        for k in range(n):
            t = k / n
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
                              + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(P[-2])
    return out


class Road:
    def __init__(self, name, width, ctrl, kind='cobble', lift=0.10, lamps=True, hedges=False):
        self.name, self.hw, self.kind, self.lift = name, width * 0.5, kind, lift
        self.lamps, self.hedges = lamps, hedges
        self.pts = catmull_rom(ctrl, 1.0)

    def frame(self, i):
        p = self.pts
        t = (p[min(i + 1, len(p) - 1)] - p[max(i - 1, 0)])
        t.z = 0.0
        t.normalize()
        return t, Vector((-t.y, t.x, 0.0))


ROAD_INDEX = PointIndex(10.0)


def road_gap(x, y, r=14.0):
    """Distance from (x, y) to the edge of the nearest road (negative = on it)."""
    best = r
    for px, py, hw in ROAD_INDEX.near(x, y, r):
        d = hypot(x - px, y - py) - hw
        if d < best:
            best = d
    return best


def build_road_mesh(road, mb):
    cols = 6
    verts, faces, edge = [], [], []
    for i, p in enumerate(road.pts):
        t, nrm = road.frame(i)
        for c in range(cols + 1):
            s = -1.0 + 2.0 * c / cols
            q = p + nrm * (s * road.hw * 1.15)
            verts.append((q.x, q.y, terrain_height(q.x, q.y) + road.lift))
            edge.append(abs(s))
    C = cols + 1
    for i in range(len(road.pts) - 1):
        for c in range(cols):
            a = i * C + c
            faces.append((a, a + C, a + C + 1, a + 1))
    mb.add(verts, faces, M.cobble if road.kind == 'cobble' else M.dirt, smooth=True, attrs={"edge": edge})


def build_plaza(mb, centre, radius):
    rings, seg = 8, 64
    verts, faces, edge = [], [], []
    verts.append((centre.x, centre.y, terrain_height(centre.x, centre.y) + 0.16))
    edge.append(0.0)
    for r in range(1, rings + 1):
        rr = radius * 1.12 * r / rings
        for k in range(seg):
            a = tau * k / seg
            x, y = centre.x + cos(a) * rr, centre.y + sin(a) * rr
            verts.append((x, y, terrain_height(x, y) + 0.16))
            edge.append(rr / (radius * 1.12))
    for k in range(seg):
        faces.append((0, 1 + k, 1 + (k + 1) % seg))
    for r in range(rings - 1):
        for k in range(seg):
            a, b = 1 + r * seg + k, 1 + r * seg + (k + 1) % seg
            faces.append((a, a + seg, b + seg, b))
    mb.add(verts, faces, M.cobble, smooth=True, attrs={"edge": edge})


# ----------------------------------------------------------------------------
# Houses
# ----------------------------------------------------------------------------
ROOF_COLOURS = [(0.36, 0.035, 0.025), (0.05, 0.10, 0.28), (0.035, 0.20, 0.20), (0.24, 0.03, 0.05),
                (0.42, 0.13, 0.04), (0.08, 0.08, 0.10), (0.30, 0.05, 0.03), (0.04, 0.15, 0.30)]


def _wall_frames(W, D):
    """(name, length, matrix) for the 4 walls. Wall space: X along, -Y out, Z up."""
    return [
        ("front", W, Matrix.Translation((0, -D / 2, 0))),
        ("right", D, Matrix.Translation((W / 2, 0, 0)) @ Matrix.Rotation(pi / 2, 4, 'Z')),
        ("back", W, Matrix.Translation((0, D / 2, 0)) @ Matrix.Rotation(pi, 4, 'Z')),
        ("left", D, Matrix.Translation((-W / 2, 0, 0)) @ Matrix.Rotation(-pi / 2, 4, 'Z')),
    ]


def wbox(mb, Mw, u, v, out, su, sv, so, mat, rot=0.0):
    """Box in wall space: centre (u along wall, v height, out from the wall)."""
    m = Mw @ Matrix.Translation((u, -out, v))
    if rot:
        m = m @ Matrix.Rotation(rot, 4, 'Y')
    mb.box(m @ Matrix.Diagonal((su, so, sv, 1.0)), mat)


def add_window(mb, Mw, u, v, ww, wh, lit, rng, shutters):
    glass = M.win_lit if lit else M.win_dark
    wbox(mb, Mw, u, v, 0.0, ww, wh, 0.04, glass)
    f = 0.09
    wbox(mb, Mw, u, v + wh / 2 + f / 2, 0.05, ww + 2 * f, f, 0.1, M.timber)
    wbox(mb, Mw, u, v - wh / 2 - f / 2, 0.08, ww + 2 * f + 0.1, f, 0.16, M.timber)
    wbox(mb, Mw, u - ww / 2 - f / 2, v, 0.05, f, wh, 0.1, M.timber)
    wbox(mb, Mw, u + ww / 2 + f / 2, v, 0.05, f, wh, 0.1, M.timber)
    wbox(mb, Mw, u, v, 0.04, 0.05, wh, 0.06, M.timber)
    wbox(mb, Mw, u, v + wh * 0.12, 0.04, ww, 0.05, 0.06, M.timber)
    if shutters:
        sw = ww * 0.5
        for side in (-1, 1):
            ang = rng.uniform(0.0, 0.25)
            wbox(mb, Mw, u + side * (ww / 2 + f + sw / 2 + 0.02), v, 0.06 + ang, sw, wh + 0.05, 0.05, M.shutter)
    if rng.random() < 0.35:  # flower box
        wbox(mb, Mw, u, v - wh / 2 - 0.22, 0.22, ww + 0.1, 0.22, 0.25, M.wood)
        for k in range(5):
            mb.blob(Mw @ Vector((u - ww / 2 + 0.1 + k * (ww - 0.2) / 4, -0.25, v - wh / 2 - 0.05)), 0.13,
                    M.flowers, sub=1, rough=0.3, attrs={"var": rng.uniform(0.0, 1.0), "ao": 0.0})


def frame_wall(mb, Mw, L, H, openings, braces=True):
    """Half-timbering: plates, posts, studs, a rail and diagonal braces."""
    t = 0.2
    wbox(mb, Mw, 0, 0.1, 0.03, L + 0.1, 0.2, 0.08, M.timber)          # sole plate
    wbox(mb, Mw, 0, H - 0.1, 0.03, L + 0.1, 0.2, 0.08, M.timber)      # top plate
    for s in (-1, 1):
        wbox(mb, Mw, s * (L / 2 - t / 2), H / 2, 0.035, t, H, 0.09, M.timber)  # corner posts

    def blocked(u0, u1, v0, v1):
        for (ou, ow, ov0, ov1) in openings:
            if u1 > ou - ow / 2 - 0.12 and u0 < ou + ow / 2 + 0.12 and v1 > ov0 - 0.1 and v0 < ov1 + 0.1:
                return True
        return False

    n = max(2, int(L / 1.05))
    xs = [-L / 2 + L * k / n for k in range(1, n)]
    for x in xs:
        if not blocked(x - 0.08, x + 0.08, 0.2, H - 0.2):
            wbox(mb, Mw, x, H / 2, 0.03, 0.16, H - 0.3, 0.07, M.timber)
    rail = H * 0.52
    segs = [-L / 2 + t] + xs + [L / 2 - t]
    for a, b in zip(segs, segs[1:]):
        if not blocked(a, b, rail - 0.08, rail + 0.08):
            wbox(mb, Mw, (a + b) / 2, rail, 0.03, b - a, 0.14, 0.07, M.timber)
    if braces:
        for s in (-1, 1):
            u0 = s * (L / 2 - t)
            u1 = s * (L / 2 - t - min(1.3, L * 0.22))
            if not blocked(min(u0, u1), max(u0, u1), 0.2, rail):
                du, dv = u1 - u0, rail - 0.2
                ln = hypot(du, dv)
                ang = atan2(dv, du)
                wbox(mb, Mw, (u0 + u1) / 2, 0.2 + dv / 2, 0.028, ln, 0.14, 0.06, M.timber, rot=-ang)


def build_house(name, x, y, rot, rng, coll, lights_coll, small=False, white=False):
    W = rng.uniform(5.2, 6.4) if small else rng.uniform(6.0, 9.2)
    D = rng.uniform(4.8, 5.6) if small else rng.uniform(5.5, 7.6)
    floors = 1 if small or rng.random() < 0.35 else 2
    stone_ground = (not small) and floors == 2 and rng.random() < 0.45
    jetty = 0.3 if floors == 2 and rng.random() < 0.7 else 0.0
    h1, h2 = 3.0, 2.7
    pitch = radians(rng.uniform(40, 52))
    oh = 0.55
    gable_front = rng.random() < 0.35

    # sit the house on the terrain: floor 0.45 m above the highest corner
    R = Matrix.Rotation(rot, 3, 'Z')
    hs = []
    for cx in (-W / 2 - 0.5, W / 2 + 0.5):
        for cy in (-D / 2 - 0.5, D / 2 + 0.5):
            p = R @ Vector((cx, cy, 0)) + Vector((x, y, 0))
            hs.append(terrain_height(p.x, p.y))
    g_hi, g_lo = max(hs), min(hs)
    base_z = g_hi + 0.45
    mb = MeshBuilder()

    # foundation
    fdepth = base_z - g_lo + 0.8
    mb.box(TRS((0, 0, -fdepth / 2), scale=(W + 0.35, D + 0.35, fdepth)), M.stonewall)

    walls_mat_1 = M.stonewall if stone_ground else M.plaster
    mb.box(TRS((0, 0, h1 / 2), scale=(W, D, h1)), walls_mat_1)
    door_u = rng.uniform(-W / 4, W / 4)
    door_w, door_h = 1.05, 2.15
    lit_p = rng.uniform(0.35, 0.85)
    shutters = rng.random() < 0.6

    def windows_for(L, H, v_mid, wall, floor_i):
        opens, wins = [], []
        n = max(1, int((L - 1.0) / 2.3))
        for k in range(n):
            u = -L / 2 + L * (k + 0.5) / n
            if wall == "front" and floor_i == 0 and abs(u - door_u) < 1.6:
                continue
            ww, wh = (0.85, 1.15) if floor_i == 0 else (0.8, 1.0)
            wins.append((u, v_mid, ww, wh))
            opens.append((u, ww + 0.2, v_mid - wh / 2 - 0.1, v_mid + wh / 2 + 0.1))
        return opens, wins

    def dress_floor(Wf, Df, z0, H, floor_i, timbered):
        for wname, L, Mw in _wall_frames(Wf, Df):
            Mw = Matrix.Translation((0, 0, z0)) @ Mw
            opens, wins = windows_for(L, H, H * 0.55, wname, floor_i)
            if wname == "front" and floor_i == 0:
                opens.append((door_u, door_w + 0.3, 0.0, door_h + 0.1))
            for (u, v, ww, wh) in wins:
                add_window(mb, Mw, u, v, ww, wh, rng.random() < lit_p, rng, shutters)
            if timbered:
                frame_wall(mb, Mw, L, H, opens, braces=floor_i > 0 or floors == 1)

    dress_floor(W, D, 0.0, h1, 0, not stone_ground)
    top_z = h1
    Wt, Dt = W, D
    if floors == 2:
        Wt, Dt = W + 2 * jetty, D + 2 * jetty
        mb.box(TRS((0, 0, h1 + 0.12), scale=(Wt + 0.12, Dt + 0.12, 0.26)), M.timber)
        mb.box(TRS((0, 0, h1 + 0.25 + h2 / 2), scale=(Wt, Dt, h2)), M.plaster)
        dress_floor(Wt, Dt, h1 + 0.25, h2, 1, True)
        top_z = h1 + 0.25 + h2

    # door, step, lamp
    Mf = _wall_frames(W, D)[0][2]
    wbox(mb, Mf, door_u, door_h / 2, 0.03, door_w, door_h, 0.08, M.door)
    for s in (-1, 1):
        wbox(mb, Mf, door_u + s * (door_w / 2 + 0.08), door_h / 2 + 0.05, 0.06, 0.16, door_h + 0.1, 0.14, M.timber)
    wbox(mb, Mf, door_u, door_h + 0.15, 0.08, door_w + 0.5, 0.16, 0.2, M.timber)
    wbox(mb, Mf, door_u, -0.25, 0.45, door_w + 0.6, 0.5, 0.9, M.stone)
    lamp_u = door_u + (door_w / 2 + 0.55) * (1 if rng.random() < 0.5 else -1)
    wbox(mb, Mf, lamp_u, 2.35, 0.12, 0.05, 0.05, 0.25, M.iron)
    wbox(mb, Mf, lamp_u, 2.2, 0.28, 0.2, 0.3, 0.2, M.glass)
    wbox(mb, Mf, lamp_u, 2.4, 0.28, 0.26, 0.06, 0.26, M.iron)
    lamp_local = Mf @ Vector((lamp_u, -0.45, 2.2))

    # roof (built with the ridge along X, then turned for gable-front houses)
    if gable_front:
        L, S, Rr = Dt, Wt, Matrix.Rotation(pi / 2, 4, 'Z')
    else:
        L, S, Rr = Wt, Dt, Matrix.Identity(4)
    tanp = math.tan(pitch)
    ridge_z = top_z + (S / 2) * tanp
    span = S / 2 + oh
    slab_len = span / cos(pitch)
    th = 0.22
    for side in (-1, 1):
        nrm = Vector((0, side * sin(pitch), cos(pitch)))
        ctr = Vector((0, side * span / 2, ridge_z - (span / 2) * tanp)) - nrm * (th / 2) + Vector((0, 0, 0.05))
        m = Rr @ Matrix.Translation(ctr) @ Matrix.Rotation(-side * pitch, 4, 'X')
        mb.box(m @ Matrix.Diagonal((L + 2 * oh * 0.8, slab_len, th, 1.0)), M.roof)
        # fascia board along the eave
        e = Vector((0, side * span, ridge_z - span * tanp - 0.05))
        mb.box(Rr @ Matrix.Translation(e) @ Matrix.Diagonal((L + 2 * oh * 0.8, 0.08, 0.3, 1.0)), M.timber)
    mb.box(Rr @ Matrix.Translation((0, 0, ridge_z + 0.1)) @ Matrix.Rotation(pi / 4, 4, 'X')
           @ Matrix.Diagonal((L + 2 * oh * 0.8 + 0.05, 0.28, 0.28, 1.0)), M.roof)
    # gable ends
    for side in (-1, 1):
        gx = side * L / 2
        tri = [(-S / 2, top_z), (S / 2, top_z), (0, ridge_z)]
        pm = Rr @ Matrix.Translation((gx, 0, 0)) @ Matrix.Rotation(pi / 2, 4, 'Z')
        mb.prism(tri, -0.25 if side > 0 else 0.0, 0.0 if side > 0 else 0.25, pm, M.plaster)
        # king post and collar
        out = side * 0.04
        mb.box(Rr @ TRS((gx + out, 0, (top_z + ridge_z) / 2), scale=(0.1, 0.16, ridge_z - top_z)), M.timber)
        cz = top_z + (ridge_z - top_z) * 0.38
        cw = S * (1 - 0.38) - 0.1
        mb.box(Rr @ TRS((gx + out, 0, cz), scale=(0.1, cw, 0.15)), M.timber)
        if rng.random() < 0.6:
            add_window(mb, Rr @ Matrix.Translation((gx, 0, top_z)) @ Matrix.Rotation(-side * pi / 2, 4, 'Z'),
                       0.0, (ridge_z - top_z) * 0.33, 0.55, 0.6, rng.random() < lit_p, rng, False)

    # chimney
    if rng.random() < 0.85:
        cu = rng.choice((-1, 1)) * (L / 2 - 0.9)
        cv = rng.choice((-1, 1)) * S * 0.18
        cz0 = top_z - 0.6
        cz1 = ridge_z + 1.1
        mb.box(Rr @ TRS((cu, cv, (cz0 + cz1) / 2), scale=(0.8, 0.8, cz1 - cz0)), M.stonewall)
        mb.box(Rr @ TRS((cu, cv, cz1 + 0.06), scale=(0.95, 0.95, 0.12)), M.stone)
        mb.cyl(Rr @ Matrix.Translation((cu, cv, cz1 + 0.12)), M.redmetal, seg=8, r0=0.14, r1=0.12, z0=0, z1=0.45)

    ob = mb.build(name, coll, location=(x, y, base_z), rz=rot)
    col = (0.62, 0.58, 0.52) if white else rng.choice(ROOF_COLOURS)
    ob.color = (*col, 1.0)
    bev = ob.modifiers.new("Bevel", 'BEVEL')
    bev.width = 0.02
    bev.segments = 1
    bev.limit_method = 'ANGLE'
    # porch lamp
    wl = Matrix.Translation((x, y, base_z)) @ Matrix.Rotation(rot, 4, 'Z') @ lamp_local
    point_light(name + " Lamp", wl, rng.uniform(25.0, 45.0), WARM, 0.08, lights_coll)
    return ob, max(Wt, Dt) * 0.5 + oh


# ----------------------------------------------------------------------------
# Trees, bushes, rocks
# ----------------------------------------------------------------------------
def make_deciduous(seed, coll):
    rng = random.Random(seed)
    mb = MeshBuilder()
    H = rng.uniform(4.0, 6.2)
    bend = Vector((rng.uniform(-0.7, 0.7), rng.uniform(-0.7, 0.7), 0.0))
    path = [Vector((bend.x * (i / 5) ** 2, bend.y * (i / 5) ** 2, H * i / 5)) for i in range(6)]
    mb.tube(path, [0.36 * (1 - 0.7 * i / 5) for i in range(6)], M.bark, seg=9)
    blobs = []
    nb_ = rng.randint(3, 5)
    for b in range(nb_):
        t = rng.uniform(0.45, 0.85)
        s = path[int(t * 5)].lerp(path[min(5, int(t * 5) + 1)], (t * 5) % 1.0)
        a = tau * b / nb_ + rng.uniform(-0.4, 0.4)
        dirv = Vector((cos(a) * 0.85, sin(a) * 0.85, 0.75)).normalized()
        ln = rng.uniform(1.8, 2.8) * H / 5
        e = s + dirv * ln
        mb.tube([s, s.lerp(e, 0.5) + Vector((0, 0, 0.2)), e], [0.14, 0.09, 0.04], M.bark, seg=6)
        blobs.append((e + Vector((0, 0, 0.4)), rng.uniform(1.5, 2.2)))
    blobs.append((path[-1] + Vector((0, 0, 0.9)), rng.uniform(2.0, 2.6)))
    for _ in range(3):
        a = rng.uniform(0, tau)
        blobs.append((path[4] + Vector((cos(a) * 1.4, sin(a) * 1.4, rng.uniform(0.6, 1.6))), rng.uniform(1.4, 2.0)))
    crown_c = sum((b[0] for b in blobs), Vector()) / len(blobs)
    for k, (c, r) in enumerate(blobs):
        var = rng.uniform(0, 1)
        mb.blob(c, r, M.leaves, sub=2, squash=(1, 1, 0.82), rough=0.28, seed=seed * 7.0 + k * 3.1,
                attrs={"var": var, "ao": clamp(0.55 - 0.25 * (c.z - crown_c.z))})
        # leaf cards around the surface to break up the silhouette
        verts, faces, vv = [], [], []
        for _ in range(70):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
            p = c + Vector((d.x * r * 1.02, d.y * r * 1.02, d.z * r * 0.86))
            tq = d.cross(Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))).normalized()
            bq = d.cross(tq).normalized()
            s = rng.uniform(0.18, 0.32)
            i0 = len(verts)
            verts += [p + tq * s, p + bq * s * 0.6, p - tq * s, p - bq * s * 0.6]
            faces.append((i0, i0 + 1, i0 + 2, i0 + 3))
            vv += [var + rng.uniform(-0.2, 0.2)] * 4
        mb.add(verts, faces, M.leaves, attrs={"var": vv, "ao": 0.0})
    me_ob = mb.build("tree_proto_%d" % seed, coll)
    return me_ob.data, max(b[1] for b in blobs) + 1.5


def make_conifer(seed, coll):
    rng = random.Random(seed)
    mb = MeshBuilder()
    H = rng.uniform(8.0, 12.0)
    mb.cyl(Matrix.Identity(4), M.bark, seg=8, r0=0.3, r1=0.08, z0=0, z1=H)
    tiers = rng.randint(6, 8)
    for k in range(tiers):
        t = k / tiers
        z0 = 1.2 + t * (H - 1.8)
        r = lerp(2.6, 0.5, t) * rng.uniform(0.9, 1.1)
        verts, faces = [], []
        seg = 14
        verts.append(Vector((0, 0, z0 + 2.3 - t * 0.6)))
        for i in range(seg):
            a = tau * i / seg + rng.uniform(-0.1, 0.1)
            rr = r * rng.uniform(0.85, 1.12)
            verts.append(Vector((cos(a) * rr, sin(a) * rr, z0 - rng.uniform(0.0, 0.4))))
        for i in range(seg):
            faces.append((0, 1 + i, 1 + (i + 1) % seg))
        under = len(verts)
        verts.append(Vector((0, 0, z0 + 0.2)))
        for i in range(seg):
            faces.append((under, 1 + (i + 1) % seg, 1 + i))
        mb.add(verts, faces, M.conifer, smooth=True, attrs={"var": rng.uniform(0, 1), "ao": 0.4 * (1 - t)})
    ob = mb.build("conifer_proto_%d" % seed, coll)
    return ob.data, 3.0


def make_boulder(seed, coll):
    rng = random.Random(seed)
    mb = MeshBuilder()
    verts, faces = unit_ico(3)
    sx, sy, sz = rng.uniform(0.8, 1.3), rng.uniform(0.7, 1.1), rng.uniform(0.45, 0.8)
    out = []
    for v in verts:
        d = 1.0 + 0.3 * n3(v.x * 1.2 + seed, v.y * 1.2, v.z * 1.2) + 0.08 * n3(v.x * 4 + seed, v.y * 4, v.z * 4)
        p = Vector((v.x * sx * d, v.y * sy * d, v.z * sz * d))
        if p.z < -0.15:
            p.z = -0.15 + (p.z + 0.15) * 0.25
        out.append(p)
    mb.add(out, faces, M.rock, smooth=True)
    ob = mb.build("rock_proto_%d" % seed, coll)
    return ob.data


# ----------------------------------------------------------------------------
# Props: lamps, harbour, lighthouse, cave gate, plaza
# ----------------------------------------------------------------------------
def add_lamp_post(mb, p, lights_coll, name, height=3.4, z=None):
    if z is None:
        z = terrain_height(p.x, p.y)
    mb.box(TRS((p.x, p.y, z + 0.2), scale=(0.4, 0.4, 0.5)), M.stone)
    mb.cyl(Matrix.Translation((p.x, p.y, z + 0.4)), M.iron, seg=8, r0=0.08, r1=0.06, z0=0, z1=height - 0.4)
    top = z + height
    mb.box(TRS((p.x, p.y, top - 0.02), scale=(0.34, 0.34, 0.06)), M.iron)
    mb.box(TRS((p.x, p.y, top + 0.22), scale=(0.26, 0.26, 0.42)), M.glass)
    for sx in (-1, 1):
        for sy in (-1, 1):
            mb.box(TRS((p.x + sx * 0.14, p.y + sy * 0.14, top + 0.22), scale=(0.04, 0.04, 0.46)), M.iron)
    mb.cyl(Matrix.Translation((p.x, p.y, top + 0.43)), M.iron, seg=4, r0=0.27, r1=0.0, z0=0, z1=0.25)
    point_light(name, (p.x, p.y, top + 0.22), 85.0, WARM, 0.1, lights_coll)


def boat_hull(mb, L, W, D, paint, inner):
    nL, nS = 18, 8
    verts, faces = [], []
    for i in range(nL + 1):
        s = -1.0 + 2.0 * i / nL
        if s >= 0:
            hw = W / 2 * max(0.015, (1 - s ** 2.2)) ** 0.55
        else:
            hw = W / 2 * max(0.25, (1 - abs(s) ** 3.0)) ** 0.4
        top = D * 0.5 + 0.2 * s * s
        keel = -D * 0.5 * (1 - 0.35 * s * s)
        for k in range(nS + 1):
            ph = -pi / 2 + pi * k / nS
            y = hw * sin(ph)
            z = top - (top - keel) * (abs(cos(ph)) ** 0.7)
            verts.append(Vector((s * L / 2, y, z)))
    for i in range(nL):
        for k in range(nS):
            a = i * (nS + 1) + k
            faces.append((a, a + 1, a + nS + 2, a + nS + 1))
    mb.add(verts, faces, paint, smooth=True)


def build_boat(name, pos, rot, rng, coll, kind='row'):
    mb = MeshBuilder()
    if kind == 'row':
        L, W, D = rng.uniform(4.2, 5.2), rng.uniform(1.5, 1.8), 0.75
    else:
        L, W, D = 8.0, 2.6, 1.3
    boat_hull(mb, L, W, D, M.paint, M.wood)
    if kind == 'row':
        for s in (-0.25, 0.2):
            mb.box(TRS((s * L / 2, 0, 0.05), scale=(0.28, W * 0.85, 0.06)), M.wood)
        mb.box(TRS((0.0, 0.25, 0.12), rz=0.08, scale=(3.0, 0.08, 0.04)), M.wood)
        mb.box(TRS((0.0, -0.25, 0.12), rz=-0.06, scale=(3.0, 0.08, 0.04)), M.wood)
    else:
        mb.box(TRS((-0.3, 0, D * 0.42), scale=(L * 0.82, W * 0.82, 0.08)), M.wood)
        mb.box(TRS((-1.2, 0, D * 0.42 + 0.45), scale=(2.6, 1.7, 0.9)), M.plaster)
        mb.box(TRS((-1.2, 0, D * 0.42 + 0.95), scale=(2.8, 1.9, 0.1)), M.wood)
        mb.cyl(Matrix.Translation((0.9, 0, D * 0.42)), M.wood, seg=8, r0=0.09, r1=0.06, z0=0, z1=10.0)
        mb.box(TRS((-0.9, 0, D * 0.42 + 1.6), scale=(3.6, 0.12, 0.12)), M.wood)
        mb.cyl(Matrix.Translation((-0.9, 0, D * 0.42 + 1.75)) @ Matrix.Rotation(pi / 2, 4, 'Y'), M.canvas,
               seg=10, r0=0.22, r1=0.16, z0=-1.7, z1=1.9)
        mb.box(TRS((0.9, 0, D * 0.42 + 10.05), scale=(0.14, 0.14, 0.2)), M.glass)
    ob = mb.build(name, coll, location=pos, rz=rot)
    ob.color = (*rng.choice([(0.55, 0.53, 0.48), (0.25, 0.03, 0.02), (0.04, 0.12, 0.25), (0.05, 0.18, 0.12)]), 1.0)
    so = ob.modifiers.new("Planking", 'SOLIDIFY')
    so.thickness = 0.06
    so.material_offset = 1
    ob.data.materials.append(M.wood)
    return ob


def build_harbour(coll, props_coll, lights_coll, start, direction):
    rng = random.Random(CONFIG["SEED"] + 17)
    side = Vector((-direction.y, direction.x, 0.0))
    L, hw, deck = 44.0, 1.7, 1.55
    mb = MeshBuilder()
    rot = atan2(direction.y, direction.x)
    s = 0.0
    while s < L:
        p = start + direction * s
        width = hw * 2 + (8.0 if s > L - 8 else 0.0)
        mb.box(TRS((p.x, p.y, deck + rng.uniform(-0.01, 0.01)), rz=rot + rng.uniform(-0.01, 0.01),
                   scale=(0.30, width - rng.uniform(0, 0.2), 0.08)), M.wood)
        s += 0.34
    for k in range(int(L / 3.4) + 1):
        s = k * 3.4
        for sd in (-1, 1):
            off = hw + 0.05 + (4.0 if s > L - 8 else 0.0)
            p = start + direction * s + side * sd * off
            top = deck + (0.9 if k % 2 == 0 else 0.0)
            mb.cyl(Matrix.Translation((p.x, p.y, -5.0)), M.wood, seg=8, r0=0.17, r1=0.15, z0=0, z1=top + 5.0)
    for sd in (-1, 1):
        a = start + side * sd * (hw - 0.3)
        b = start + direction * L + side * sd * (hw - 0.3)
        m = (a + b) / 2
        mb.box(TRS((m.x, m.y, deck - 0.2), rz=rot, scale=(L, 0.2, 0.3)), M.wood)
    # crates and barrels
    for k in range(6):
        p = start + direction * rng.uniform(6, L - 2) + side * rng.choice((-1, 1)) * (hw - 0.5)
        if rng.random() < 0.5:
            mb.box(TRS((p.x, p.y, deck + 0.34), rz=rng.uniform(0, 1), scale=(0.6, 0.6, 0.6)), M.wood)
        else:
            mb.cyl(Matrix.Translation((p.x, p.y, deck + 0.04)), M.wood, seg=10, r0=0.3, r1=0.3, z0=0, z1=0.8)
    mb.build("Pier", props_coll)
    lamps = MeshBuilder()
    end = start + direction * L
    for sd in (-1, 1):
        add_lamp_post(lamps, end + side * sd * 5.0 - direction * 2.0, lights_coll, "Pier Lantern", z=deck + 0.04)
    lamps.build("Pier Lanterns", props_coll)
    # moored boats
    for k, (s, sd) in enumerate([(12, 1), (19, -1), (27, 1), (33, -1)]):
        p = start + direction * s + side * sd * (hw + 1.6)
        build_boat("Rowboat %d" % (k + 1), (p.x, p.y, 0.05), rot + rng.uniform(-0.12, 0.12), rng, coll)
    p = start + direction * (L + 7.0) + side * 9.0
    build_boat("Sailboat", (p.x, p.y, 0.25), rot + 0.6, rng, coll, kind='sail')


def build_lighthouse(coll, lights_coll, pos):
    z0 = terrain_height(pos.x, pos.y)
    mb = MeshBuilder()
    T = Matrix.Translation((pos.x, pos.y, z0))
    mb.cyl(T, M.stonewall, seg=24, r0=5.0, r1=4.6, z0=-3.0, z1=1.2, smooth=False)
    mb.cyl(T, M.tower, seg=32, r0=3.2, r1=2.2, z0=1.2, z1=22.0)
    mb.cyl(T, M.stone, seg=32, r0=3.1, r1=3.1, z0=22.0, z1=22.5)
    for k in range(28):
        a = tau * k / 28
        mb.cyl(T @ Matrix.Translation((cos(a) * 2.9, sin(a) * 2.9, 22.5)), M.iron, seg=4, r0=0.04, r1=0.04, z0=0, z1=1.0)
    mb.cyl(T, M.iron, seg=32, r0=2.95, r1=2.95, z0=23.45, z1=23.55, caps=(False, False))
    mb.cyl(T, M.iron, seg=12, r0=1.7, r1=1.7, z0=22.5, z1=22.8)
    mb.cyl(T, M.glass, seg=12, r0=1.55, r1=1.55, z0=22.8, z1=25.2)
    mb.cyl(T, M.beacon, seg=10, r0=0.5, r1=0.5, z0=23.4, z1=24.6)
    for k in range(8):
        a = tau * k / 8
        mb.box(T @ TRS((cos(a) * 1.6, sin(a) * 1.6, 24.0), rz=a, scale=(0.08, 0.12, 2.4)), M.iron)
    mb.cyl(T, M.redmetal, seg=16, r0=1.95, r1=0.15, z0=25.2, z1=26.9)
    mb.cyl(T, M.redmetal, seg=8, r0=0.15, r1=0.0, z0=26.9, z1=27.8)
    face = atan2(-pos.y, -pos.x)
    for k in range(4):
        a = face + 0.6 * k
        h = 4.0 + 4.2 * k
        r = lerp(3.2, 2.2, (h - 1.2) / 20.8)
        mb.box(T @ TRS((cos(a) * r, sin(a) * r, h), rz=a, scale=(0.3, 0.6, 0.9)), M.win_lit)
    mb.box(T @ TRS((cos(face) * 3.1, sin(face) * 3.1, 2.3), rz=face, scale=(0.4, 1.0, 2.0)), M.door)
    ob = mb.build("Lighthouse", coll)
    point_light("Lighthouse Lamp", (pos.x, pos.y, z0 + 24.0), 2500.0, blackbody(4200), 0.4, lights_coll)
    sd = bpy.data.lights.new(PREFIX + "LighthouseBeam", 'SPOT')
    sd.energy = 3.0e6
    sd.color = blackbody(4600)
    sd.spot_size = radians(7.0)
    sd.spot_blend = 0.35
    sd.shadow_soft_size = 0.3
    beam = link(bpy.data.objects.new("Lighthouse Beam", sd), lights_coll)
    beam.location = (pos.x, pos.y, z0 + 24.0)
    base_a = atan2(pos.y, pos.x) - 0.5
    beam.rotation_euler = (radians(87.0), 0.0, base_a - pi / 2)
    if CONFIG["ANIMATE"]:
        fc = beam.driver_add("rotation_euler", 2)
        fc.driver.expression = "frame*%g+%g" % (tau / 160.0, base_a - pi / 2)
    return ob, face


def build_cave_gate(coll, lights_coll, theta):
    g = max(terrain_height(*(MOUNT_C.xy + Vector((cos(theta), sin(theta))) * 61.0)), PLATEAU)
    R = max(mountain_radius(theta + d, z) for d in (-0.09, -0.045, 0.0, 0.045, 0.09)
            for z in (g, g + 3.0, g + 6.0, g + 9.0))
    face_c = MOUNT_C.xy + Vector((cos(theta), sin(theta))) * (R + 0.4)
    rot = theta + pi / 2      # local -Y points out of the mountain
    gz = terrain_height(face_c.x, face_c.y)
    mb = MeshBuilder()
    ow, ph, ar = 2.7, 4.2, 2.7    # half opening width, pillar height, arch radius
    depth = 7.0
    top = ph + ar + 1.6
    # facade blocks around the opening, deep enough to bite into the rock
    mb.box(TRS((-(ow + 3.2), depth / 2 - 0.6, top / 2 - 1.0), scale=(6.4, depth, top + 2.0)), M.stonewall)
    mb.box(TRS((ow + 3.2, depth / 2 - 0.6, top / 2 - 1.0), scale=(6.4, depth, top + 2.0)), M.stonewall)
    mb.box(TRS((0, depth / 2 - 0.6, top + 0.4), scale=(2 * ow + 12.8, depth, 2.4)), M.stonewall)
    for k in range(14):
        u0 = -ow + 2 * ow * k / 14
        u1 = u0 + 2 * ow / 14
        um = (u0 + u1) / 2
        arc = ph + sqrt(max(0.0, ar * ar - um * um))
        mb.box(TRS((um, depth / 2 - 0.6, (arc + top - 0.8) / 2), scale=(u1 - u0 + 0.02, depth, top - 0.8 - arc)), M.stonewall)
    # tunnel lining and its dark depths
    mb.box(TRS((0, depth + 0.2, ph), scale=(2 * ow + 0.4, 0.2, 2 * ph + 1.0)), M.cave)
    for s in (-1, 1):
        mb.box(TRS((s * (ow + 0.05), depth / 2, ph), scale=(0.1, depth, 2 * ph)), M.cave)
    mb.box(TRS((0, depth / 2, ph + ar + 0.05), scale=(2 * ow, depth, 0.1)), M.cave)
    # pillars and voussoirs
    for s in (-1, 1):
        mb.box(TRS((s * (ow + 0.45), -0.35, ph / 2), scale=(0.9, 1.0, ph)), M.stone)
        mb.box(TRS((s * (ow + 0.45), -0.35, ph + 0.12), scale=(1.1, 1.15, 0.24)), M.stone)
    n = 11
    for k in range(n):
        a0 = pi * k / n
        a1 = pi * (k + 1) / n
        pts = [(cos(a0) * ar, ph + sin(a0) * ar), (cos(a0) * (ar + 0.9), ph + sin(a0) * (ar + 0.9)),
               (cos(a1) * (ar + 0.9), ph + sin(a1) * (ar + 0.9)), (cos(a1) * ar, ph + sin(a1) * ar)]
        mb.prism(pts, -0.85, 0.2, Matrix.Identity(4), M.stone)
    # rails running into the mine
    for s in (-0.55, 0.55):
        mb.box(TRS((s, -3.0, 0.08), scale=(0.08, depth + 6.0, 0.1)), M.iron)
    for k in range(10):
        mb.box(TRS((0, -5.5 + k * 1.2, 0.03), scale=(1.6, 0.22, 0.08)), M.wood)
    # torches
    for s in (-1, 1):
        p = Vector((s * (ow + 0.45), -0.95, 3.0))
        mb.box(TRS(p, scale=(0.12, 0.3, 0.12)), M.iron)
        mb.cyl(Matrix.Translation(p + Vector((0, -0.15, 0))), M.wood, seg=6, r0=0.05, r1=0.07, z0=0, z1=0.55)
        mb.blob(p + Vector((0, -0.15, 0.8)), 0.17, M.flame, sub=1, squash=(1, 1, 1.9), rough=0.25)
    mb.build("Mine Gate", coll, location=(face_c.x, face_c.y, gz), rz=rot)
    W = Matrix.Translation((face_c.x, face_c.y, gz)) @ Matrix.Rotation(rot, 4, 'Z')
    for s in (-1, 1):
        point_light("Torch", W @ Vector((s * (ow + 0.45), -1.3, 3.9)), 260.0, TORCH, 0.15, lights_coll)
    point_light("Mine Glow", W @ Vector((0, 4.0, 2.5)), 180.0, TORCH, 0.5, lights_coll)
    return face_c, W @ Vector((0, -3.5, 0)), gz


def build_plaza_props(mb, lights_coll, c):
    z = terrain_height(c.x, c.y) + 0.16
    T = Matrix.Translation((c.x, c.y, z))
    mb.cyl(T, M.stonewall, seg=8, r0=2.8, r1=2.8, z0=0, z1=0.7, smooth=False)
    mb.cyl(T, M.water_small, seg=8, r0=2.45, r1=2.45, z0=0.0, z1=0.55, smooth=False)
    mb.cyl(T, M.stone, seg=8, r0=0.4, r1=0.32, z0=0, z1=2.0, smooth=False)
    mb.cyl(T, M.stone, seg=8, r0=0.2, r1=1.0, z0=1.9, z1=2.3, smooth=False)
    mb.cyl(T, M.stone, seg=8, r0=0.25, r1=0.15, z0=2.3, z1=3.0, smooth=False)
    for k in range(4):
        a = tau * k / 4 + pi / 4
        add_lamp_post(mb, c + Vector((cos(a) * 9.5, sin(a) * 9.5, 0)), lights_coll, "Plaza Lamp")
    rng = random.Random(4)
    for k, a in enumerate((pi * 0.95, pi * 1.35)):
        p = c + Vector((cos(a) * 7.0, sin(a) * 7.0, 0))
        zz = terrain_height(p.x, p.y) + 0.16
        St = Matrix.Translation((p.x, p.y, zz)) @ Matrix.Rotation(a + pi / 2, 4, 'Z')
        for sx in (-1, 1):
            for sy in (-1, 1):
                mb.box(St @ TRS((sx * 1.3, sy * 0.8, 1.2), scale=(0.1, 0.1, 2.4)), M.wood)
        mb.box(St @ TRS((0, -0.5, 0.5), scale=(2.6, 0.7, 1.0)), M.wood)
        mb.box(St @ TRS((0, 0, 2.55), rx=0.25, scale=(3.0, 2.1, 0.05)), M.awning)
        for i in range(6):
            mb.blob(St @ Vector((-1.0 + i * 0.4, -0.5, 1.12)), 0.16, M.bush, sub=1, rough=0.2,
                    attrs={"var": rng.uniform(0.6, 1.0), "ao": 0.0})


# ----------------------------------------------------------------------------
# World, lights, cameras, render settings
# ----------------------------------------------------------------------------
def build_world(scene, moon_dir):
    world = bpy.data.worlds.new(PREFIX + "NightSky")
    _enable_nodes(world)
    nt = world.node_tree
    nt.nodes.clear()
    nb = Nodes(nt)
    out = nb.node("ShaderNodeOutputWorld")
    d = nb.vmath('NORMALIZE', nb.coord('Generated'))
    zc = nb.sep(d)[2]
    sky = nb.ramp(nb.maprange(zc, -0.2, 1.0), [
        (0.0, (0.006, 0.010, 0.018)), (0.165, (0.030, 0.048, 0.080)), (0.20, (0.020, 0.034, 0.062)),
        (0.32, (0.008, 0.015, 0.034)), (1.0, (0.0015, 0.003, 0.009))])
    md = nb.vmath('DOT_PRODUCT', d, tuple(moon_dir))
    halo = nb.add(nb.mul(nb.math('POWER', nb.math('MAXIMUM', md, 0.0), 900.0), 0.5),
                  nb.mul(nb.math('POWER', nb.math('MAXIMUM', md, 0.0), 40.0), 0.03))
    disc = nb.maprange(md, math.cos(radians(0.62)), math.cos(radians(0.55)))
    maria = nb.maprange(nb.noise(d, 900.0, 4, 0.6).outputs["Fac"], 0.35, 0.7, 0.55, 1.0)
    moon = nb.mul(disc, nb.mul(maria, 40.0))
    # stars: two layers of voronoi cells, most cells left dark
    above = nb.maprange(zc, -0.02, 0.12)
    stars = None
    for scale, keep, size, gain in ((260.0, 0.93, 0.07, 18.0), (620.0, 0.86, 0.09, 6.0)):
        v = nb.voronoi(d, scale)
        rnd = nb.sep(v.outputs["Color"])
        pt = nb.maprange(v.outputs["Distance"], size, 0.0)
        on = nb.math('GREATER_THAN', rnd[0], keep)
        bright = nb.mul(nb.math('POWER', rnd[1], 3.0), gain)
        s = nb.mul(nb.mul(pt, on), bright)
        stars = s if stars is None else nb.add(stars, s)
    band = nb.math('POWER', nb.math('SUBTRACT', 1.0, nb.math('ABSOLUTE',
                   nb.vmath('DOT_PRODUCT', d, tuple(Vector((0.35, 0.55, 0.76)).normalized())))), 14.0)
    mw = nb.mul(band, nb.mul(nb.noise(d, 6.0, 8, 0.65).outputs["Fac"], 0.025))
    starlight = nb.mul(nb.add(stars, mw), above)
    col = nb.mix(1.0, sky, nb.comb(halo, halo, halo), 'ADD')
    col = nb.mix(1.0, col, nb.mix(1.0, nb.comb(moon, moon, moon), (0.95, 0.97, 1.0), 'MULTIPLY'), 'ADD')
    col = nb.mix(1.0, col, nb.mix(1.0, nb.comb(starlight, starlight, starlight), (0.85, 0.9, 1.0), 'MULTIPLY'), 'ADD')
    bg = nb.node("ShaderNodeBackground", {"Color": col, "Strength": 1.0})
    nb.links.new(bg.outputs[0], out.inputs["Surface"])
    scene.world = world
    return world


def add_camera(name, loc, target, lens, coll, fstop=None, focus=None):
    cd = bpy.data.cameras.new(PREFIX + name)
    cd.lens = lens
    cd.clip_start = 0.5
    cd.clip_end = 12000.0
    cd.sensor_width = 36.0
    if fstop:
        cd.dof.use_dof = True
        cd.dof.aperture_fstop = fstop
        cd.dof.focus_distance = focus or (Vector(target) - Vector(loc)).length
    ob = bpy.data.objects.new("Camera " + name, cd)
    ob.location = loc
    ob.rotation_euler = (Vector(target) - Vector(loc)).to_track_quat('-Z', 'Y').to_euler()
    return link(ob, coll)


def add_camera_aim(name, loc, look_xy, pitch_deg, lens, coll, **kw):
    """Camera at loc, heading towards look_xy, tilted by pitch_deg."""
    h = (Vector(look_xy) - Vector(loc[:2])).normalized()
    p = radians(pitch_deg)
    d = Vector((h.x * cos(p), h.y * cos(p), sin(p)))
    return add_camera(name, loc, Vector(loc) + d * 100.0, lens, coll, **kw)


def screen_direction(cam_ob, scene, sx, sy):
    """World direction through normalised screen point (sx, sy) of a camera."""
    frame = cam_ob.data.view_frame(scene=scene)
    tr, br, bl, tl = frame
    p = bl + (br - bl) * sx + (tl - bl) * sy
    rot = cam_ob.rotation_euler.to_matrix()
    return (rot @ p).normalized()


def enable_gpu(scene):
    try:
        prefs = bpy.context.preferences.addons["cycles"].preferences
    except (KeyError, AttributeError):
        return None
    for kind in ('OPTIX', 'CUDA', 'HIP', 'METAL', 'ONEAPI'):
        try:
            prefs.compute_device_type = kind
        except (TypeError, ValueError):
            continue
        for fn in ("refresh_devices", "get_devices"):
            if hasattr(prefs, fn):
                getattr(prefs, fn)()
                break
        devs = [d for d in prefs.devices if d.type == kind]
        if devs:
            for d in prefs.devices:
                d.use = d.type == kind
            scene.cycles.device = 'GPU'
            return kind
    return None


def setup_render(scene):
    r = scene.render
    r.resolution_x, r.resolution_y = CONFIG["RESOLUTION"]
    r.resolution_percentage = 100
    r.filepath = CONFIG["OUTPUT"]
    scene.frame_start, scene.frame_end = 1, CONFIG["FRAMES"]
    _try_set(r, "use_persistent_data", True)
    scene.frame_set(1)
    if CONFIG["ENGINE"].upper() == "EEVEE":
        for eng in ('BLENDER_EEVEE_NEXT', 'BLENDER_EEVEE'):
            if _try_set(r, "engine", eng):
                break
        ee = scene.eevee
        _try_set(ee, "taa_render_samples", 64)
        _try_set(ee, "use_volumetric_shadows", True)
        _try_set(ee, "volumetric_tile_size", '4')
        _try_set(ee, "volumetric_end", 1500.0)
        _try_set(ee, "volumetric_samples", 96)
        _try_set(ee, "use_raytracing", True)
        _try_set(ee, "use_shadows", True)
        _try_set(ee, "use_bloom", True)
    else:
        r.engine = 'CYCLES'
        c = scene.cycles
        gpu = enable_gpu(scene) if CONFIG["USE_GPU"] else None
        print("  Cycles device:", gpu or "CPU")
        c.samples = CONFIG["SAMPLES"]
        _try_set(c, "use_adaptive_sampling", True)
        _try_set(c, "adaptive_threshold", 0.015)
        _try_set(c, "use_denoising", True)
        _try_set(c, "denoiser", 'OPENIMAGEDENOISE')
        c.max_bounces = 8
        c.diffuse_bounces = 3
        c.glossy_bounces = 3
        c.transmission_bounces = 6
        c.volume_bounces = 1
        c.transparent_max_bounces = 16
        c.sample_clamp_indirect = 8.0
        c.caustics_reflective = False
        c.caustics_refractive = False
        _try_set(c, "volume_step_rate", 1.0)
        _try_set(c, "volume_max_steps", 512)
        _try_set(c, "use_light_tree", True)
        _try_set(c, "light_sampling_threshold", 0.01)
    vs = scene.view_settings
    _try_set(vs, "view_transform", 'AgX')
    for look in ("AgX - Medium High Contrast", "Medium High Contrast", "AgX - Base Contrast"):
        if _try_set(vs, "look", look):
            break
    vs.exposure = 0.6
    vs.gamma = 1.0


def setup_compositor(scene):
    try:
        if hasattr(scene, "compositing_node_group"):          # Blender 5.0+
            ng = bpy.data.node_groups.new(PREFIX + "Compositor", 'CompositorNodeTree')
            ng.interface.new_socket(name="Image", in_out='OUTPUT', socket_type='NodeSocketColor')
            scene.compositing_node_group = ng
            out = ng.nodes.new("NodeGroupOutput")
        else:                                                 # Blender 4.x
            scene.use_nodes = True
            ng = scene.node_tree
            ng.nodes.clear()
            out = ng.nodes.new("CompositorNodeComposite")
        nb = Nodes(ng)
        rl = nb.node("CompositorNodeRLayers")
        rl.scene = scene
        glare = nb.node("CompositorNodeGlare")
        if "Type" in glare.inputs:
            glare.inputs["Type"].default_value = 'Bloom'
            _try_set(glare.inputs["Quality"], "default_value", 'High')
            glare.inputs["Threshold"].default_value = 1.2
            glare.inputs["Strength"].default_value = 0.35
            glare.inputs["Size"].default_value = 0.7
        else:
            if not _try_set(glare, "glare_type", 'BLOOM'):
                glare.glare_type = 'FOG_GLOW'
            glare.quality = 'HIGH'
            glare.threshold = 1.2
            glare.mix = -0.65
            _try_set(glare, "size", 8)
        nb.links.new(rl.outputs["Image"], glare.inputs["Image"])
        lens = nb.node("CompositorNodeLensdist")
        lens.inputs["Dispersion"].default_value = 0.012
        _try_set(lens, "use_fit", False)
        nb.links.new(glare.outputs["Image"], lens.inputs["Image"])
        nb.links.new(lens.outputs["Image"], out.inputs[0])
        viewer = nb.node("CompositorNodeViewer")
        nb.links.new(lens.outputs["Image"], viewer.inputs[0])
    except Exception as exc:  # the compositor is a nice-to-have
        print("  Compositor skipped:", exc)


# ----------------------------------------------------------------------------
# Main build
# ----------------------------------------------------------------------------
def build():
    t0 = time.time()
    RNG.seed(CONFIG["SEED"])
    _NOFF[:] = (RNG.uniform(-300, 300), RNG.uniform(-300, 300), RNG.uniform(-300, 300))
    ROAD_INDEX.grid.clear()
    scene = reset_scene()
    print("Building Volcano Island ...")
    C = {k: make_collection(scene, k) for k in
         ("Island", "Volcano", "Sky", "Ocean", "Village", "Trees", "Props", "Lights", "Cameras")}
    protos = make_collection(scene, "Prototypes")
    protos.hide_render = True
    protos.hide_viewport = True
    build_materials()
    rng = random.Random(CONFIG["SEED"])

    build_terrain(C["Island"])
    print("  terrain  %.1fs" % (time.time() - t0))
    build_ocean(C["Ocean"])
    build_foam(C["Ocean"])
    build_mountain(C["Volcano"])
    print("  volcano  %.1fs" % (time.time() - t0))
    for k in range(3):
        a = tau * k / 3
        point_light("Lava Glow", (MOUNT_C.x + cos(a) * 7, MOUNT_C.y + sin(a) * 7, LAVA_Z + 2.0),
                    2.5e4, (1.0, 0.32, 0.06), 6.0, C["Lights"])
    if CONFIG["CLOUD"]:
        build_cloud(C["Sky"])
    if CONFIG["LIGHTNING"]:
        build_lightning(C["Sky"])
    if CONFIG["EMBERS"]:
        build_embers(C["Volcano"])
    if CONFIG["FOG"]:
        build_fog(C["Sky"])

    # --- roads ---------------------------------------------------------------
    plaza = Vector((-92.0, -6.0, 0.0))
    cave_theta = atan2(-0.42, -0.91)
    _, gate_front, _ = build_cave_gate(C["Props"], C["Lights"], cave_theta)
    beach = None
    for r in [x * 0.002 for x in range(350, 520)]:
        p = point_at_island(BEACH_DIR, r)
        if terrain_height(p.x, p.y) < 1.25:
            beach = p
            break
    beach = beach or point_at_island(BEACH_DIR, 0.95)
    pier_dir = Vector((beach.x, beach.y, 0.0)).normalized()
    lh_pos = point_at_island(LIGHTHOUSE_DIR, 0.80)
    harbour_end = beach - pier_dir * 3.0
    roads = [
        Road("Main Street", 5.2, [plaza, (-74, -9), (-56, -8), (-42, -2), gate_front.xy], hedges=True),
        Road("Harbour Road", 4.4, [plaza, (-95, -28), (-102, -50), harbour_end.lerp(plaza, 0.25).xy,
                                   harbour_end.xy], hedges=True),
        Road("North Lane", 3.8, [plaza, (-98, 18), (-94, 42), (-80, 62), (-60, 74)]),
        Road("West Lane", 3.6, [plaza, (-112, -2), (-128, 4)]),
        Road("Orchard Lane", 3.4, [(-56, -8), (-63, 18), (-58, 42)]),
        Road("Lighthouse Path", 2.6, [(-40, -4), (-24, -36), (8, -60), (52, -72), (95, -66),
                                      (lh_pos - lh_pos.normalized() * 9.0).xy],
             kind='dirt', lift=0.08, lamps=False),
    ]
    for i, rd in enumerate(roads):
        rd.lift += 0.004 * (len(roads) - i)
        for p in rd.pts:
            ROAD_INDEX.add(p.x, p.y, rd.hw)
    rmb = MeshBuilder()
    for rd in roads:
        build_road_mesh(rd, rmb)
    build_plaza(rmb, plaza, 13.0)
    rmb.build("Roads", C["Village"])
    for k in range(32):
        a = tau * k / 32
        ROAD_INDEX.add(plaza.x + cos(a) * 11.0, plaza.y + sin(a) * 11.0, 2.5)
    ROAD_INDEX.add(plaza.x, plaza.y, 13.0)
    print("  roads    %.1fs" % (time.time() - t0))

    # --- houses --------------------------------------------------------------
    houses = []   # (x, y, radius)

    def free_spot(x, y, rad, margin=1.0):
        d, _ = island_polar(x, y)
        if d > 0.80:
            return False
        th = atan2(y - MOUNT_C.y, x - MOUNT_C.x)
        if hypot(x - MOUNT_C.x, y - MOUNT_C.y) < mountain_radius(th, PLATEAU + 3.0) + rad + 6.0:
            return False
        for hx, hy, hr in houses:
            if hypot(x - hx, y - hy) < rad + hr + margin:
                return False
        return True

    candidates = []
    for rd in roads[:5]:
        for i in range(4, len(rd.pts) - 3, 2):
            for sd in (-1, 1):
                candidates.append((rd, i, sd))
    rng.shuffle(candidates)
    count = 0
    for rd, i, sd in candidates:
        if count >= CONFIG["HOUSES"]:
            break
        p = rd.pts[i]
        t, nrm = rd.frame(i)
        setback = rd.hw + rng.uniform(2.6, 4.0)
        depth = 3.8
        c = p + nrm * sd * (setback + depth)
        rad = 5.6
        if not free_spot(c.x, c.y, rad):
            continue
        face = -nrm * sd                       # house front looks at the road
        rot = atan2(face.y, face.x) + pi / 2
        # the footprint must stay off every road
        ok = True
        Rm = Matrix.Rotation(rot, 3, 'Z')
        for lx in (-5.0, 0.0, 5.0):
            for ly in (-4.2, 0.0, 4.2):
                q = Rm @ Vector((lx, ly, 0.0)) + c
                if road_gap(q.x, q.y) < 0.6:
                    ok = False
        if not ok:
            continue
        count += 1
        _, hr = build_house("House %02d" % count, c.x, c.y, rot + rng.uniform(-0.04, 0.04), rng,
                             C["Village"], C["Lights"])
        houses.append((c.x, c.y, hr))
    print("  houses   %d  %.1fs" % (count, time.time() - t0))

    # --- lamps, hedges, plaza ------------------------------------------------
    pm = MeshBuilder()
    for rd in roads:
        if not rd.lamps:
            continue
        sd = 1
        for i in range(10, len(rd.pts) - 4, 17):
            t, nrm = rd.frame(i)
            p = rd.pts[i] + nrm * sd * (rd.hw + 0.8)
            if hypot(p.x - plaza.x, p.y - plaza.y) > 14.0 and all(hypot(p.x - hx, p.y - hy) > hr + 0.5 for hx, hy, hr in houses):
                add_lamp_post(pm, p, C["Lights"], "Street Lamp")
            sd = -sd
    build_plaza_props(pm, C["Lights"], plaza)
    pm.build("Lamps and Plaza", C["Props"])

    hm = MeshBuilder()
    for rd in roads:
        if not rd.hedges:
            continue
        for sd in (-1, 1):
            i = 14
            while i < len(rd.pts) - 6:
                seg_len = rng.randint(5, 10)
                seg = []
                for k in range(i, min(i + seg_len, len(rd.pts) - 6)):
                    t, nrm = rd.frame(k)
                    q = rd.pts[k] + nrm * sd * (rd.hw + 1.0)
                    if any(hypot(q.x - hx, q.y - hy) < hr + 0.3 for hx, hy, hr in houses):
                        break
                    seg.append((q, nrm))
                for (q, nrm) in seg:
                    z = terrain_height(q.x, q.y)
                    hm.blob((q.x, q.y, z + 0.32), 0.55, M.hedge, sub=2, squash=(1.0, 1.0, 0.75), rough=0.25,
                            seed=q.x, attrs={"var": rng.random(), "ao": 0.0})
                    for _ in range(9):
                        f = q + nrm * rng.uniform(-0.35, 0.35) + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0))
                        hm.blob((f.x, f.y, z + rng.uniform(0.62, 0.78)), rng.uniform(0.07, 0.11), M.flowers, sub=1,
                                rough=0.2, attrs={"var": rng.choice((0.1, 0.3, 0.45, 0.6, 0.75, 0.95)), "ao": 0.0})
                i += seg_len + rng.randint(2, 5)
    hm.build("Flower Hedges", C["Village"])

    # --- harbour and lighthouse ---------------------------------------------
    if CONFIG["HARBOUR"]:
        build_harbour(C["Ocean"], C["Props"], C["Lights"], beach - pier_dir * 1.0, pier_dir)
    if CONFIG["LIGHTHOUSE"]:
        lh, face = build_lighthouse(C["Props"], C["Lights"], lh_pos)
        cottage_pos = lh_pos + Vector((cos(face + 1.2), sin(face + 1.2), 0)) * 11.0
        build_house("Keeper's Cottage", cottage_pos.x, cottage_pos.y, face + pi / 2 + 1.2,
                    random.Random(3), C["Props"], C["Lights"], small=True, white=True)
        houses.append((lh_pos.x, lh_pos.y, 6.0))
        houses.append((cottage_pos.x, cottage_pos.y, 4.5))

    # --- trees ---------------------------------------------------------------
    tree_meshes = [make_deciduous(CONFIG["SEED"] * 100 + k, protos) for k in range(8)]
    conifers = [make_conifer(CONFIG["SEED"] * 50 + k, protos) for k in range(3)]
    trees = []
    fallen = MeshBuilder()
    tries = 0
    while len(trees) < CONFIG["TREES"] and tries < 20000:
        tries += 1
        x = rng.uniform(-ISLAND_RX * 0.9, ISLAND_RX * 0.9)
        y = rng.uniform(-ISLAND_RY * 0.9, ISLAND_RY * 0.9)
        d, a = island_polar(x, y)
        if d > 0.84:
            continue
        zone = 0.35 if x < -45 else (1.0 if y < -20 else 0.8)
        if rng.random() > zone:
            continue
        th = atan2(y - MOUNT_C.y, x - MOUNT_C.x)
        if hypot(x - MOUNT_C.x, y - MOUNT_C.y) < mountain_radius(th, PLATEAU + 3) + 4.0:
            continue
        if road_gap(x, y) < 2.8:
            continue
        if any(hypot(x - hx, y - hy) < hr + 2.5 for hx, hy, hr in houses):
            continue
        if any(hypot(x - tx, y - ty) < 5.5 for tx, ty in trees):
            continue
        z = terrain_height(x, y)
        use_conifer = d > 0.74 and rng.random() < 0.45
        if use_conifer:
            me, rad = rng.choice(conifers)
        else:
            me, rad = rng.choice(tree_meshes)
        ob = bpy.data.objects.new("Tree %03d" % (len(trees) + 1), me)
        ob.location = (x, y, z - 0.15)
        ob.rotation_euler = (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), rng.uniform(0, tau))
        s = rng.uniform(0.8, 1.3)
        ob.scale = (s, s, s * rng.uniform(0.9, 1.1))
        hue = rng.betavariate(2.0, 2.2) * 0.9
        ob.color = (hue, 0.0, 0.0, 1.0)
        link(ob, C["Trees"])
        trees.append((x, y))
        if not use_conifer:
            verts, faces, vv = [], [], []
            for _ in range(70):
                rr = 3.2 * s * sqrt(rng.uniform(0, 1))
                aa = rng.uniform(0, tau)
                lx, ly = x + cos(aa) * rr, y + sin(aa) * rr
                lz = terrain_height(lx, ly) + 0.04
                rot = rng.uniform(0, tau)
                sz = rng.uniform(0.12, 0.2)
                i0 = len(verts)
                c, s_ = cos(rot) * sz, sin(rot) * sz
                verts += [(lx + c, ly + s_, lz), (lx - s_ * 0.6, ly + c * 0.6, lz + 0.01),
                          (lx - c, ly - s_, lz), (lx + s_ * 0.6, ly - c * 0.6, lz + 0.01)]
                faces.append((i0, i0 + 1, i0 + 2, i0 + 3))
                vv += [clamp(hue + rng.uniform(-0.12, 0.12))] * 4
            fallen.add(verts, faces, M.fallen, attrs={"var": vv, "ao": 0.0})
    fallen.build("Fallen Leaves", C["Trees"])
    print("  trees    %d  %.1fs" % (len(trees), time.time() - t0))

    # --- bushes and rocks -----------------------------------------------------
    bm_ = MeshBuilder()
    for _ in range(260):
        x = rng.uniform(-ISLAND_RX * 0.9, ISLAND_RX * 0.9)
        y = rng.uniform(-ISLAND_RY * 0.9, ISLAND_RY * 0.9)
        d, _a = island_polar(x, y)
        if d > 0.85 or road_gap(x, y) < 1.2:
            continue
        th = atan2(y - MOUNT_C.y, x - MOUNT_C.x)
        if hypot(x - MOUNT_C.x, y - MOUNT_C.y) < mountain_radius(th, PLATEAU + 3) + 1.0:
            continue
        if any(hypot(x - hx, y - hy) < hr + 0.8 for hx, hy, hr in houses):
            continue
        z = terrain_height(x, y)
        v = rng.random()
        for _k in range(rng.randint(2, 4)):
            r = rng.uniform(0.5, 1.0)
            bm_.blob((x + rng.uniform(-0.8, 0.8), y + rng.uniform(-0.8, 0.8), z + r * 0.5), r, M.bush, sub=2,
                     squash=(1, 1, 0.8), rough=0.3, seed=x + _k, attrs={"var": clamp(v + rng.uniform(-0.1, 0.1)), "ao": 0.25})
    bm_.build("Bushes", C["Trees"])

    rocks = [make_boulder(CONFIG["SEED"] * 10 + k, protos) for k in range(7)]
    placed = 0
    for k in range(700):
        a = rng.uniform(0, tau)
        d = rng.uniform(0.86, 1.03)
        p = point_at_island(a, d)
        if beach_weight(a) > 0.4:
            continue
        z = terrain_height(p.x, p.y)
        if z < -2.0:
            continue
        ob = bpy.data.objects.new("Rock %03d" % (placed + 1), rng.choice(rocks))
        ob.location = (p.x, p.y, z - 0.3)
        s = rng.uniform(0.8, 3.2)
        ob.scale = (s, s * rng.uniform(0.8, 1.2), s * rng.uniform(0.7, 1.1))
        ob.rotation_euler = (rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(0, tau))
        link(ob, C["Island"])
        placed += 1
    for k in range(60):   # boulders around the volcano's foot and on the lawns
        th = rng.uniform(0, tau)
        if ang_diff(th, cave_theta) < 0.12:
            continue
        r = mountain_radius(th, PLATEAU + 3) + rng.uniform(-1.0, 4.0)
        x, y = MOUNT_C.x + cos(th) * r, MOUNT_C.y + sin(th) * r
        if road_gap(x, y) < 1.0:
            continue
        ob = bpy.data.objects.new("Scree %03d" % k, rng.choice(rocks))
        ob.location = (x, y, terrain_height(x, y) - 0.4)
        s = rng.uniform(1.0, 3.6)
        ob.scale = (s, s, s * 0.8)
        ob.rotation_euler = (0, 0, rng.uniform(0, tau))
        link(ob, C["Island"])
    print("  details  %.1fs" % (time.time() - t0))

    # --- moonlight, cameras, sky --------------------------------------------
    setup_render(scene)
    cams = {
        "Hero": add_camera_aim("Hero", (48.0, -306.0, 94.0), (2.0, 40.0), -5.0, 24.0, C["Cameras"]),
        "Village": add_camera("Village", (-148.0, -128.0, 24.0), (-70.0, -2.0, 40.0), 26.0, C["Cameras"]),
        "Harbour": add_camera("Harbour", (-166.0, -150.0, 3.6), (-104.0, -72.0, 20.0), 30.0, C["Cameras"]),
        "Aerial": add_camera("Aerial", (330.0, -330.0, 260.0), (10.0, 10.0, 60.0), 30.0, C["Cameras"]),
        "Crater": add_camera("Crater", (MOUNT_C.x + 70.0, MOUNT_C.y - 60.0, 96.0),
                             (MOUNT_C.x, MOUNT_C.y, 64.0), 24.0, C["Cameras"]),
    }
    hero = cams["Hero"]
    scene.camera = cams.get(CONFIG["CAMERA"], hero)
    moon_dir = screen_direction(hero, scene, 0.84, 0.88)
    sun = bpy.data.lights.new(PREFIX + "Moon", 'SUN')
    sun.energy = 1.3
    sun.color = MOON_COL
    sun.angle = radians(0.6)
    moon = link(bpy.data.objects.new("Moonlight", sun), C["Lights"])
    # the key light is cheated round to the side of the visible moon so the
    # volcano and the cloud get some shape instead of pure silhouette
    fwd = hero.rotation_euler.to_matrix() @ Vector((0.0, 0.0, -1.0))
    fwd = Vector((fwd.x, fwd.y, 0.0)).normalized()
    right = Vector((fwd.y, -fwd.x, 0.0))
    key = (Vector((moon_dir.x, moon_dir.y, 0.0)).normalized() * 0.5 + right * 0.8 - fwd * 0.25).normalized()
    el = radians(30.0)
    key = Vector((key.x * cos(el), key.y * cos(el), sin(el)))
    moon.rotation_euler = key.to_track_quat('Z', 'Y').to_euler()
    fill = bpy.data.lights.new(PREFIX + "SkyFill", 'SUN')
    fill.energy = 0.12
    fill.color = (0.45, 0.55, 0.85)
    fill.angle = radians(40.0)
    fl = link(bpy.data.objects.new("Sky Fill", fill), C["Lights"])
    fl.rotation_euler = (radians(25), 0, radians(200))
    build_world(scene, moon_dir)
    setup_compositor(scene)
    print("Done in %.1fs. Press F12 to render." % (time.time() - t0))
    return scene


def apply_command_line():
    """Read `key=value` options given after `--` on the Blender command line."""
    import sys
    if "--" not in sys.argv:
        return False, False
    animation = False
    for arg in sys.argv[sys.argv.index("--") + 1:]:
        key, _, val = arg.partition("=")
        key = key.lower()
        if key == "render":
            CONFIG["RENDER_ON_FINISH"] = True
        elif key == "animation":
            CONFIG["RENDER_ON_FINISH"] = animation = True
        elif key == "camera":
            CONFIG["CAMERA"] = val.capitalize()
        elif key == "samples":
            CONFIG["SAMPLES"] = int(val)
        elif key == "res":
            w, h = val.lower().split("x")
            CONFIG["RESOLUTION"] = (int(w), int(h))
        elif key == "engine":
            CONFIG["ENGINE"] = val.upper()
        elif key == "seed":
            CONFIG["SEED"] = int(val)
        elif key == "frames":
            CONFIG["FRAMES"] = int(val)
        elif key == "gpu":
            CONFIG["USE_GPU"] = val not in ("0", "false", "no")
        elif key == "out":
            CONFIG["OUTPUT"] = val
        else:
            print("Unknown option:", arg)
    return True, animation


if __name__ == "__main__":
    _cli, _animation = apply_command_line()
    _scene = build()
    if CONFIG["RENDER_ON_FINISH"]:
        bpy.ops.render.render(animation=_animation, write_still=not _animation, scene=_scene.name)
