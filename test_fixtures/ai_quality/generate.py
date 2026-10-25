#!/usr/bin/env python3
"""Deterministic public synthetic notes, not samples of actual handwriting.

Requires Pillow. Font files remain local and are never embedded in the SVGs.
"""
import argparse
import hashlib
import html
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
WIDTH, HEIGHT, SCALE = 1000, 1400, 2
DEFAULT_FONT = "/System/Library/Fonts/Supplemental/Comic Sans MS.ttf"
INK, BLUE, RED = "#243653", "#2458a5", "#b34e57"


class Sheet:
    def __init__(self, title, font):
        self.font_path = font
        self.image = Image.new("RGB", (WIDTH * SCALE, HEIGHT * SCALE), "#fffefa")
        self.draw = ImageDraw.Draw(self.image)
        self.svg = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{WIDTH}" height="{HEIGHT}" viewBox="0 0 {WIDTH} {HEIGHT}">',
                    '<rect width="100%" height="100%" fill="#fffefa"/>']
        for y in range(145, HEIGHT, 52):
            self.line([(35, y), (970, y)], "#e0e7f0", 1)
        self.line([(86, 75), (86, 1370)], "#e4bac0", 1)
        self.text(108, 25, "PUBLIC SYNTHETIC • hand-style typesetting, not actual pen input", 18, "#6d737c")
        self.text(108, 76, title, 37, BLUE)

    def text(self, x, y, value, size=30, color=INK):
        font = ImageFont.truetype(self.font_path, size * SCALE)
        self.draw.text((x * SCALE, y * SCALE), value, font=font, fill=color)
        self.svg.append(f'<text x="{x}" y="{y + size}" font-family="Comic Sans MS, Chalkboard SE, cursive" font-size="{size}" fill="{color}">{html.escape(value)}</text>')

    def line(self, points, color=INK, width=3):
        self.draw.line([(round(x * SCALE), round(y * SCALE)) for x, y in points], fill=color, width=width * SCALE)
        self.svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in points)}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linejoin="round" stroke-linecap="round"/>')

    def rect(self, x, y, w, h, color=INK, width=3):
        self.line([(x,y),(x+w,y),(x+w,y+h),(x,y+h),(x,y)], color, width)

    def circle(self, x, y, radius=30, fill=None):
        box = [(x-radius)*SCALE,(y-radius)*SCALE,(x+radius)*SCALE,(y+radius)*SCALE]
        self.draw.ellipse(box, outline=INK, fill=fill, width=3*SCALE)
        self.svg.append(f'<circle cx="{x}" cy="{y}" r="{radius}" fill="{fill or "none"}" stroke="{INK}" stroke-width="3"/>')

    def arrow(self, x1, y1, x2, y2, color=INK, width=3):
        self.line([(x1,y1),(x2,y2)], color, width)
        a = math.atan2(y2-y1, x2-x1)
        self.line([(x2-16*math.cos(a-.45),y2-16*math.sin(a-.45)),(x2,y2),
                   (x2-16*math.cos(a+.45),y2-16*math.sin(a+.45))], color, width)

    def save(self, name):
        self.image.resize((WIDTH, HEIGHT), Image.Resampling.LANCZOS).save(ROOT / f"{name}.png", optimize=True)
        (ROOT / f"{name}.svg").write_text("\n".join(self.svg + ["</svg>"]) + "\n")


def make_mechanics(s):
    s.text(110,160,"m = 2 kg       a_x = 3 m/s²")
    s.text(110,215,"Choose +x right, +y up")
    s.rect(380,460,160,110)
    s.text(415,490,"block",26)
    s.arrow(460,460,460,335,BLUE); s.text(480,330,"N")
    s.arrow(460,570,460,710,BLUE); s.text(480,675,"mg")
    s.arrow(540,515,770,515,BLUE); s.text(615,460,"push 12 N",27)
    s.arrow(380,515,180,515,BLUE); s.text(145,460,"friction 6 N",26)
    s.text(110,800,"ΣF_x = F_push − f = 12 − 6 = 6 N")
    s.text(110,860,"ma_x = (2 kg)(3 m/s²) = 6 N")
    s.text(110,920,"a_y = 0  =>  N = mg")
    s.text(110,1020,"Friction points left; acceleration points right.",27)


def make_rc(s):
    s.text(110,160,"12 V source; R = 2 kΩ; C = 100 μF")
    s.text(110,215,"Switch closes at t = 0; capacitor uncharged.",27)
    s.line([(225,400),(370,400)])
    s.line([(370,400),(385,375),(410,425),(435,375),(460,425),(485,375),(500,400)])
    s.line([(500,400),(740,400),(740,530)])
    s.line([(690,530),(790,530)]); s.line([(690,550),(790,550)])
    s.line([(740,550),(740,700),(225,700),(225,565)])
    s.line([(205,565),(245,565)]); s.line([(190,540),(260,540)])
    s.line([(225,540),(225,400)])
    s.text(375,330,"R = 2 kΩ",26); s.text(790,515,"C",28)
    s.text(115,520,"12 V",26); s.text(265,525,"+",26); s.text(265,560,"−",26)
    s.arrow(560,355,680,355,BLUE); s.text(570,305,"i(t)",26)
    s.line([(510,700),(510,735)]); s.line([(480,735),(540,735)]); s.line([(490,748),(530,748)]); s.line([(500,761),(520,761)])
    s.text(110,835,"τ = RC = (2000)(100 x 10^(-6)) = 0.20 s",28)
    s.text(110,900,"v_C(t) = 12(1 − e^(−t / 0.20)) V")
    s.text(110,965,"i(0+) = 12 / 2000 = 6 mA")
    s.text(110,1060,"Loop: source + -> R -> C -> source −",27)


def make_calculus(s):
    s.text(110,160,"f(x) = x²       f′(x) = 2x")
    s.text(110,215,"At x = 1: f(1) = 1; slope = 2")
    ox, oy, unit = 250, 760, 210
    s.arrow(170,oy,820,oy); s.arrow(ox,830,ox,310)
    s.text(825,740,"x",25); s.text(215,290,"y",25)
    # Sparse hatching describes the integral region without obscuring the curve.
    for i in range(1,16):
        x = i / 16
        s.line([(ox+x*unit,oy),(ox+x*unit,oy-x*x*unit)],"#a8c3df",2)
    curve=[(ox+x*unit,oy-x*x*unit) for x in [i/50 for i in range(76)]]
    s.line(curve,BLUE,4)
    s.line([(ox+.45*unit,oy-(2*.45-1)*unit),(ox+1.5*unit,oy-(2*1.5-1)*unit)],RED,3)
    s.circle(ox+unit,oy-unit,5,INK)
    s.text(478,540,"(1,1)",24); s.text(605,330,"y = x²",27)
    s.text(555,650,"tangent",25,RED)
    s.text(230,785,"0",25); s.text(450,785,"1",25)
    s.text(110,930,"∫ from 0 to 1 of x² dx = 1/3")
    s.text(110,975,"Antiderivative: x³/3",26)
    s.text(110,1040,"Shaded area: under the curve, x in [0,1]",26)


def make_bayes(s):
    s.text(110,160,"D = defect (synthetic example)",28)
    s.text(110,215,"P(D)=0.01; P(+|D)=0.90; P(+|¬D)=0.05",27)
    s.text(120,500,"start",26)
    s.arrow(210,520,455,360); s.text(285,365,"0.01",25); s.text(470,340,"D",28)
    s.arrow(210,520,455,690); s.text(280,630,"0.99",25); s.text(470,675,"¬D",28)
    for x1,y1,x2,y2,label,node in [(520,360,775,290,"0.90","+"),(520,360,775,445,"0.10","−"),(540,690,775,615,"0.05","+"),(540,690,775,795,"0.95","−")]:
        s.arrow(x1,y1,x2,y2); s.text(640,(y1+y2)/2-35,label,25); s.text(x2+20,y2-20,node,30)
    s.text(110,935,"P(D|+) = 0.009 / (0.009 + 0.0495)",28)
    s.text(110,1000,"         ≈ 0.154 = 15.4%",30)
    s.text(110,1090,"A positive result does NOT imply 90% defect.",26,RED)


def make_graph(s):
    s.text(110,160,"Directed graph; BFS from A",29)
    pts={"A":(200,410),"B":(450,300),"C":(450,570),"D":(730,300),"E":(730,570)}
    edges=[("A","B"),("A","C"),("B","D"),("C","D"),("C","E"),("D","E")]
    for a,b in edges:
        x1,y1=pts[a];x2,y2=pts[b]; d=math.hypot(x2-x1,y2-y1)
        s.arrow(x1+(x2-x1)*37/d,y1+(y2-y1)*37/d,x2-(x2-x1)*39/d,y2-(y2-y1)*39/d)
    for name,(x,y) in pts.items():
        s.circle(x,y,35);s.text(x-12,y-23,name,30)
    s.text(110,735,"Visit neighbors alphabetically.",27)
    s.text(110,795,"BFS order: A, B, C, D, E")
    s.text(110,855,"Levels: A=0; B=1; C=1; D=2")
    s.text(110,920,"E level 3",29,RED); s.line([(105,940),(270,930)],RED,4)
    s.text(325,920,"E level 2 (correct)",29,BLUE)
    s.text(110,1000,"Shortest A -> C -> E, length 2",29)
    s.text(110,1070,"BFS cost O(V + E)",28)


def make_uncertainty(s):
    s.text(110,160,"Keep unclear source details unclear.",28)
    s.text(110,225,"R = 4.? kΩ   (last digit unclear)",29)
    s.text(110,290,"z = 1 / [illegible]     v = iR",29)
    s.text(110,390,"Crossing wires — NO junction dot:",28)
    s.arrow(220,620,660,430,BLUE); s.arrow(220,430,660,620,RED)
    for x,y,t in [(170,620,"A"),(680,410,"B"),(170,410,"C"),(680,620,"D")]: s.text(x,y,t,28)
    s.text(110,700,"A -> B and C -> D only. No shared node.",27)
    s.text(110,805,"Separate junction example — dot at J:",28)
    s.arrow(245,1040,430,1040);s.arrow(450,1040,675,1040)
    s.arrow(440,890,440,1030);s.arrow(440,1050,440,1200)
    s.circle(440,1040,7,INK)
    for x,y,t in [(195,1020,"P"),(690,1020,"Q"),(425,850,"R"),(425,1210,"S"),(465,1045,"J")]: s.text(x,y,t,28)
    s.text(110,1290,"Do not guess the missing digit or denominator.",26,RED)


CASES = [
    dict(id="01_mechanics",title="Forces & signs", draw=make_mechanics,
         equations=["m = 2 kg", "a_x = 3 m/s^2", "F_push - f = 12 N - 6 N = 6 N = m a_x", "a_y = 0", "N = mg"],
         diagram=dict(nodes=["block","normal","gravity","push","friction"], directed_edges=[["block","normal","up"],["block","gravity","down"],["block","push","right; 12 N"],["block","friction","left; 6 N"]]),
         required=["Consistent right/up positive axes", "Force and acceleration units retained"], forbidden=["Friction points right", "Net horizontal force is 18 N"]),
    dict(id="02_rc_circuit",title="RC charging",draw=make_rc,
         equations=["R = 2 kohm", "C = 100 microfarad", "tau = RC = 0.20 s", "v_C(t) = 12 (1 - exp(-t / (0.20 s))) V", "i(0+) = 6 mA"],
         diagram=dict(nodes=["source positive","resistor","capacitor","source negative","ground"], directed_edges=[["source positive","resistor","initial conventional current"],["resistor","capacitor","initial conventional current"],["capacitor","source negative","return path"]], invariants=["Series circuit", "Ground at common lower return", "Positive source terminal is the upper terminal; source is 12 V"]),
         required=["Capacitor initially uncharged", "Switch closes at t = 0"], forbidden=["2 ohm instead of 2 kohm", "100 mF instead of 100 microfarad", "Discharging exponential substituted for charging curve"]),
    dict(id="03_calculus",title="Derivative & area",draw=make_calculus,
         equations=["f(x) = x^2", "f'(x) = 2x", "f(1) = 1", "f'(1) = 2", "integral_0^1 x^2 dx = 1/3"],
         diagram=dict(nodes=["x axis","y axis","parabola","tangent","shaded area"],directed_edges=[],invariants=["Parabola opens up", "Tangent meets curve at (1,1) with slope 2", "Shaded area below curve from x = 0 to 1"]),
         required=["Integral bounds retained", "Slope distinguished from function value"],forbidden=["Tangent slope is 1", "Integral equals 1", "Shading above curve"]),
    dict(id="04_bayes",title="Bayes tree",draw=make_bayes,
         equations=["P(D) = 0.01", "P(+|D) = 0.90", "P(+|not D) = 0.05", "P(D|+) = 0.009 / (0.009 + 0.0495) approximately 0.154 = 15.4%"],
         diagram=dict(nodes=["start","D","not D","D positive","D negative","not D positive","not D negative"],directed_edges=[["start","D","0.01"],["start","not D","0.99"],["D","D positive","0.90"],["D","D negative","0.10"],["not D","not D positive","0.05"],["not D","not D negative","0.95"]]),
         required=["Synthetic defect example", "Posterior differentiated from sensitivity"],forbidden=["P(D|+) = 90%", "False-positive probability substituted with 0.95"]),
    dict(id="05_directed_graph",title="BFS & a correction",draw=make_graph,
         equations=["distance(A)=0", "distance(B)=1", "distance(C)=1", "distance(D)=2", "distance(E)=2", "time = O(V + E)"],
         diagram=dict(nodes=["A","B","C","D","E"],directed_edges=[["A","B",""],["A","C",""],["B","D",""],["C","D",""],["C","E",""],["D","E",""]]),
         required=["BFS alphabetical order A, B, C, D, E", "Shortest A to C to E has length 2", "Crossed-out E level 3 is superseded by E level 2"],forbidden=["An edge between B and C", "Undirected graph", "E final level is 3"]),
    dict(id="06_uncertainty",title="Ambiguity & crossings",draw=make_uncertainty,
         equations=["R = 4.? kohm (last digit unclear)", "z = 1 / [illegible]", "v = i R"],
         diagram=dict(nodes=["A","B","C","D","P","Q","R","S","J"],directed_edges=[["A","B","crossing without connection"],["C","D","crossing without connection"],["P","J",""],["J","Q",""],["R","J",""],["J","S",""]],invariants=["No node at A-B / C-D crossing", "J is the shared node of the separate second diagram"]),
         required=["Explicit uncertainty on resistor last digit", "Explicit unreadable denominator", "Source ambiguity remains visible in the result"],forbidden=["Any invented resistor digit", "Any invented denominator", "Connecting A-B to C-D at their crossing"]),
]


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--font",default=DEFAULT_FONT)
    args=parser.parse_args()
    if not Path(args.font).is_file():
        parser.error("Provide a local handwriting-style font using --font; font files are not distributed.")
    manifest=dict(schema_version=1, provenance="Public synthetic study notes, drawn by deterministic code. Typeset handwriting-style font; not genuine handwriting and not a pen-recognition benchmark.",
                  image_dimensions=dict(width=WIDTH,height=HEIGHT), cases=[])
    for case in CASES:
        sheet=Sheet(case["title"],args.font)
        case["draw"](sheet)
        sheet.save(case["id"])
        record={k:v for k,v in case.items() if k!="draw"}
        record["assets"]={}
        for extension in ("png","svg"):
            file=ROOT/f'{case["id"]}.{extension}'
            record["assets"][extension]=dict(path=file.name,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),bytes=file.stat().st_size)
        manifest["cases"].append(record)
    (ROOT/"manifest.json").write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+"\n")


if __name__ == "__main__":
    main()
