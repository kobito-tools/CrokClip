# CorkClip の絵を描き直す。Xcode Command Line Tools が必要。使い方: python3 scripts/make-images.py
#   kobito/icon.svg・icon-1024.png        アイコン（コルクボードと画びょう、kobito-tools シリーズの小人）
#   assets/kobito-cling.svg → Resources/kobito-cling.png   パネルの縁にしがみつく小人
#   assets/dmg/background.svg → background.png・@2x       dmg を開いたときの背景
# .app のアイコン（AppIcon.icns）は build.sh が kobito/icon-1024.png から作る。
# 小人の描き方はシリーズ共通（元の座標系 viewBox 0 0 49 44 を translate + scale で置く）。
import random
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

INK = "#3B4441"
BODY = "#E6E3D9"
SCREEN = "#F6F7F2"


def kobito(tx, ty, s=11, arms="", legs="stand", extra_back="", extra_front="", face="smile"):
    leg = {
        "stand": '<path d="M20 35.5 L19 45"/><path d="M28 35.5 L29 45"/>',
        "walk": '<path d="M19 33 l-2 5 l-3 5"/><path d="M29 33 l2 5 l3 5"/>',
    }[legs]
    mouth = {
        "smile": '<path d="M22 22c2 2 4 2 6 0" fill="none" stroke="%s" stroke-width="1.2" stroke-linecap="round"/>' % INK,
        "open": '<path d="M22.4 21.6c1.6 2.6 3.6 2.6 5.2 0Z" fill="%s" stroke="%s" stroke-width="1" stroke-linejoin="round"/>' % (INK, INK),
    }[face]
    return f'''<g transform="translate({tx} {ty}) scale({s})" stroke-linecap="round" stroke-linejoin="round">
    {extra_back}
    <g fill="none" stroke="{INK}" stroke-width="1.8">{leg}</g>
    <path d="M10 23C10 11 16 5 25 5c8 0 13 6 13 16 0 11-6 16-15 16-8 0-13-5-13-14Z" fill="{BODY}" stroke="{INK}" stroke-width="1.7"/>
    <path d="M15 13c5-4 13-4 18 0v12c-5 4-13 4-18 0Z" fill="{SCREEN}" stroke="{INK}" stroke-width="1.4"/>
    <circle cx="21" cy="18" r="1.4" fill="{INK}"/><circle cx="28" cy="18" r="1.4" fill="{INK}"/>
    {mouth}
    <g fill="none" stroke="{INK}" stroke-width="1.8">{arms}</g>
    {extra_front}
  </g>'''


def squircle(top, bottom, content, uid):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg-{uid}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>
    <clipPath id="clip-{uid}"><rect x="100" y="100" width="824" height="824" rx="185"/></clipPath>
    <filter id="drop-{uid}" x="-10%" y="-10%" width="120%" height="130%"><feDropShadow dx="0" dy="12" stdDeviation="16" flood-color="#000" flood-opacity=".22"/></filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="url(#bg-{uid})" filter="url(#drop-{uid})"/>
  <g clip-path="url(#clip-{uid})">
{content}
  </g>
</svg>
'''


# --- CorkClip：木の枠のコルクボードに、コピーした物（文字のメモ・写真）を画びょうで留める。手前で小人が赤い画びょうを押す ---
CORK = "#C9A06F"
GRAINS = ["#9E7243", "#B58653", "#DDB887", "#E8C899", "#87603A"]
PAPER = "#FFFDF7"
LINE = "#D3C6AC"


def grains(x0, y0, x1, y1, count, seed=7):
    rng = random.Random(seed)
    dots = []
    for _ in range(count):
        x, y = rng.uniform(x0, x1), rng.uniform(y0, y1)
        r = 2 + rng.random() ** 2.2 * 9
        dots.append(f'<ellipse cx="{x:.0f}" cy="{y:.0f}" rx="{r:.1f}" ry="{r * 0.8:.1f}" fill="{rng.choice(GRAINS)}" opacity="{0.35 + rng.random() * 0.5:.2f}"/>')
    return "".join(dots)


def pushpin(cx, cy, r, color, uid):
    # 上から見た画びょう：小さな影、丸い頭、光。
    return f'''<defs><radialGradient id="pin-{uid}" cx=".35" cy=".3" r=".75"><stop offset="0" stop-color="#fff" stop-opacity=".55"/><stop offset=".35" stop-color="{color}" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".3"/></radialGradient></defs>
    <circle cx="{cx + r * 0.16}" cy="{cy + r * 0.22}" r="{r}" fill="#000" opacity=".28"/>
    <circle cx="{cx}" cy="{cy}" r="{r}" fill="{color}" stroke="{INK}" stroke-width="{r * 0.16:.1f}"/>
    <circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#pin-{uid})"/>
    <circle cx="{cx - r * 0.34}" cy="{cy - r * 0.36}" r="{r * 0.24}" fill="#fff" opacity=".8"/>'''


def note(x, y, w, h, angle, body):
    # 少し傾けたメモ用紙と、その影。
    return f'''<g transform="rotate({angle} {x + w / 2} {y + h / 2})">
    <rect x="{x + 6}" y="{y + 12}" width="{w}" height="{h}" rx="10" fill="#5B3E22" opacity=".3"/>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="10" fill="{PAPER}" stroke="{INK}" stroke-width="9"/>
    {body}
  </g>'''


def corkclip():
    board = f'''<rect x="100" y="100" width="824" height="824" fill="url(#wood)"/>
    <rect x="160" y="160" width="704" height="704" rx="120" fill="{CORK}" stroke="#5E3D22" stroke-width="10"/>
    <clipPath id="cork"><rect x="165" y="165" width="694" height="694" rx="115"/></clipPath>
    <g clip-path="url(#cork)">{grains(165, 165, 859, 859, 900)}</g>'''
    lines = lambda x, y, widths: "".join(f'<path d="M{x} {y + i * 44} h{w}" stroke="{LINE}" stroke-width="16" stroke-linecap="round"/>' for i, w in enumerate(widths))
    memo = note(214, 236, 330, 290, -7, lines(254, 312, [250, 210, 238, 150]))
    photo = note(556, 214, 252, 222, 6, '''<rect x="580" y="238" width="204" height="150" rx="6" fill="#A9C3D6" stroke="#3B4441" stroke-width="7"/>
    <path d="M580 350 Q640 300 700 336 T784 322 V388 H580 Z" fill="#7FA36E" stroke="#3B4441" stroke-width="7" stroke-linejoin="round"/>
    <circle cx="742" cy="282" r="20" fill="#F2D49B" stroke="#3B4441" stroke-width="6"/>''')
    front = note(214, 556, 320, 236, 3, lines(254, 632, [240, 200, 160]))
    pins = pushpin(379, 262, 26, "#C9A24D", "a") + pushpin(682, 232, 24, "#3F8A6E", "b") + pushpin(374, 580, 34, "#D2443A", "c")
    # 手前の小人。右手を上げて、赤い画びょうを押しているところ。
    s = 6.2
    arms = '<path d="M37 24 Q42 18 41.5 10.5"/><path d="M11 27 Q7 29.5 6.6 34"/>'
    helper = kobito(588, 600, s=s, arms=arms, face="open", extra_front=pushpin(41.5, 7.6, 3.2, "#D2443A", "d").replace('stroke-width="0.5"', 'stroke-width="0.9"'))
    content = f'''<defs><linearGradient id="wood" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#B07E52"/><stop offset="1" stop-color="#7E522C"/></linearGradient></defs>
  {board}{memo}{photo}{front}{pins}{helper}'''
    return squircle("#B07E52", "#7E522C", content, "corkclip")


# --- パネルの縁にしがみつく小人（Resources/kobito-cling.png）。右側の x=54 がパネルの縁で、両手でつかむ（手は KobitoWindow.grip）---
def cling():
    body = f'''<g transform="translate(5 16) rotate(-8 30 22)" stroke-linecap="round" stroke-linejoin="round">
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M19 35 l-2 5 l-1 4.5"/><path d="M28 35.5 l2.5 4 l4 2.5"/></g>
    <path d="M10 23C10 11 16 5 25 5c8 0 13 6 13 16 0 11-6 16-15 16-8 0-13-5-13-14Z" fill="{BODY}" stroke="{INK}" stroke-width="1.7"/>
    <path d="M15 13c5-4 13-4 18 0v12c-5 4-13 4-18 0Z" fill="{SCREEN}" stroke="{INK}" stroke-width="1.4"/>
    <circle cx="22.5" cy="18" r="1.4" fill="{INK}"/><circle cx="29.5" cy="18" r="1.4" fill="{INK}"/>
    <path d="M23.5 22c2 2 4 2 6 0" fill="none" stroke="{INK}" stroke-width="1.2"/>
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M36 16 Q43 11.5 49 13"/><path d="M37 25 Q43 24 49 22"/></g>
    <circle cx="49" cy="13" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/><circle cx="49" cy="22" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/>
  </g>'''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>\n'


# --- dmg を開いたときの背景（600×400pt）。左の CorkClip から右の Applications へ、小人が案内する ---
def dmg_background():
    arms = '<path d="M37 24 Q41 22 44.5 17"/><path d="M11.5 26 Q8.5 29 8 32.5"/>'
    guide = kobito(300 - 24 * 1.9, 280, s=1.9, arms=arms, legs="walk", face="open")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F7F1E3"/><stop offset="1" stop-color="#EADFC8"/></linearGradient></defs>
  <rect width="600" height="400" fill="url(#bg)"/>
  <path d="M0 0 H600 V56 H0 Z" fill="{CORK}" opacity=".45"/>
  <path d="M0 56 H600" stroke="#8B5E3A" stroke-width="3" opacity=".6"/>
  <text x="300" y="36" text-anchor="middle" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif" font-size="17" font-weight="600" fill="{INK}">CorkClip を Applications フォルダへドラッグしてください</text>
  <path d="M225 190 C265 160 335 160 375 190" fill="none" stroke="#8B5E3A" stroke-width="5" stroke-linecap="round" stroke-dasharray="2 12"/>
  <path d="M366 176 L380 193 L360 199" fill="none" stroke="#8B5E3A" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
  {guide}
  <text x="300" y="384" text-anchor="middle" font-family="Hiragino Sans, sans-serif" font-size="11" fill="#7A817D">kobito-tools</text>
</svg>
'''


def render(svg, png, width, height=None):
    # macOS の SVG 描画で PNG にする（scripts/render-svg.swift）。
    size = [str(width)] + ([str(height)] if height else [])
    subprocess.run(["xcrun", "swift", str(ROOT / "scripts/render-svg.swift"), str(ROOT / svg), str(ROOT / png), *size], check=True)
    print(png)


if __name__ == "__main__":
    for path, draw in (("kobito/icon.svg", corkclip), ("assets/kobito-cling.svg", cling), ("assets/dmg/background.svg", dmg_background)):
        (ROOT / path).write_text(draw())
    render("kobito/icon.svg", "kobito/icon-1024.png", 1024)
    render("assets/kobito-cling.svg", "Resources/kobito-cling.png", 192)  # 64pt を 3倍で
    render("assets/dmg/background.svg", "assets/dmg/background.png", 600, 400)
    render("assets/dmg/background.svg", "assets/dmg/background@2x.png", 1200, 800)
