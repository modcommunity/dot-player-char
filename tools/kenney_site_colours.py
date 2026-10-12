"""Measures the site avatar's colours: per Kenney Blocky Characters skin (a..r), the colour under
the most area of the head (skin, hair), the torso and the legs. DotHumanoidLook.SITE_SKINS is its
output, read by hand (the head's two colours are skin and hair; which is which is a look at the
kit's Preview.png).

    python3 -I tools/kenney_site_colours.py "<kenney bundle>/3D assets/Blocky Characters/Models/GLB format"

Kenney's kit is CC0 1.0 (kenney.nl).
"""
import sys, trimesh, numpy as np
from PIL import Image
from collections import Counter
d=sys.argv[1]
scene=trimesh.load(d+"/character-a.glb", force="scene")
parts={}
for node in scene.graph.nodes_geometry:
    tf,g=scene.graph[node]
    geom=scene.geometry[g]
    uv=geom.visual.uv; f=geom.faces; a=geom.area_faces
    parts[node]=(uv[f].mean(1), a)
for L in "abcdefghijklmnopqr":
    img=Image.open(f"{d}/Textures/texture-{L}.png").convert("RGB"); W,H=img.size; px=img.load()
    out=[]
    for key,names in (("head",["head"]),("top",["torso"]),("legs",["leg-left","leg-right"])):
        c=Counter()
        for n in names:
            cen,area=parts[n]
            for (u,v),ar in zip(cen,area):
                x=int((u%1.0)*W)%W; y=int(((1-v)%1.0)*H)%H
                c["%02x%02x%02x"%px[x,y]]+=ar
        tot=sum(c.values())
        out.append(key+"="+",".join(f"{k}:{int(100*w/tot)}" for k,w in c.most_common(3)))
    print(L," ".join(out))
