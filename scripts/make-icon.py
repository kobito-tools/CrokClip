# CorkClip のアイコン（assets/icon/icon.svg）を、kobito-tools シリーズの小人で描く。
# 小人の描き方はシリーズ共通（kobito-workspace の assets/ を参照。元の座標系 viewBox 0 0 49 44 を translate + scale で置く）。
# 使い方: scripts/make-icon.sh から呼ぶ（SVG → PNG・icns への変換もそちらで行う）。
import sys

INK = "#3B4441"
BODY = "#E6E3D9"
SCREEN = "#F6F7F2"
HAT = "#FBFAF6"


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


def ground(y=842, color="#000", opacity=".10", rx=210):
    return f'<ellipse cx="512" cy="{y}" rx="{rx}" ry="22" fill="{color}" opacity="{opacity}"/>'


# --- CorkClip：コック帽の小人が、コピーした物をはさんだクリップボードを片手に、木のさじで味見する（in good taste）---
def toque():
    # 頭の上のコック帽（帯と、ふくらんだ上の部分）。
    return f'''<path d="M15.5 4.5 C9.5 4 8.5 -5 15 -5.5 C15 -11.5 22.5 -13.5 25 -8.5 C27.5 -13.5 35 -11.5 34 -5.5 C40.5 -5 39.5 4 33.5 4.5 Z" fill="{HAT}" stroke="{INK}" stroke-width="1.6"/>
    <g fill="none" stroke="#C9C4B6" stroke-width="1.1"><path d="M20 3 C19.5 0 19.5 -2.5 20.5 -4.5"/><path d="M29 3 C29.5 0 29.5 -2.5 28.5 -4.5"/></g>
    <path d="M14.8 3.2 Q24.5 0.2 34.2 3.2 L33.8 8.6 Q24.5 6 15.2 8.6 Z" fill="{HAT}" stroke="{INK}" stroke-width="1.6"/>'''

def corkclip():
    s = 11.5
    tx, ty = 512 - 24 * s, 300
    arms = '<path d="M11 27 Q7 29.5 6.6 34"/><path d="M37 27 Q41.5 29.5 40.6 24.8"/>'
    spoon = f'''<g stroke="{INK}" stroke-linecap="round" stroke-linejoin="round">
      <path d="M44 25.5 L35.2 22.4" stroke-width="2.6"/><path d="M44 25.5 L35.2 22.4" stroke="#C99A62" stroke-width="1.2"/>
      <ellipse cx="32.6" cy="21.6" rx="3" ry="1.9" transform="rotate(19 32.6 21.6)" fill="#C99A62" stroke-width="1.3"/>
    </g>
    <circle cx="40.6" cy="24.8" r="1.9" fill="#E6E3D9" stroke="{INK}" stroke-width="1.2"/>'''
    board = f'''<g transform="rotate(-7 360 740)" stroke="{INK}" stroke-linejoin="round">
      <rect x="196" y="610" width="300" height="250" rx="26" fill="#B98A5A" stroke-width="16"/>
      <rect x="224" y="642" width="244" height="204" rx="10" fill="#F4EFE3" stroke-width="11"/>
      <rect x="296" y="590" width="100" height="46" rx="14" fill="#8C938E" stroke-width="12"/>
      <g stroke-width="9">
        <rect x="250" y="668" width="62" height="48" rx="7" fill="#A9C3D6"/>
        <path d="M257 709 L276 688 L290 702 L298 694 L306 709" fill="none" stroke-width="6"/>
      </g>
      <g stroke="#C7BFAE" stroke-width="11" stroke-linecap="round">
        <path d="M334 680 L444 680"/><path d="M334 708 L420 708"/>
        <path d="M250 752 L444 752"/><path d="M250 782 L404 782"/>
      </g>
    </g>'''
    sparkle = '<g stroke="#EEF2F5" stroke-width="14" stroke-linecap="round" opacity=".9"><path d="M712 398 L748 364"/><path d="M736 456 L784 452"/><path d="M682 352 L690 306"/></g>'
    content = ground(872, rx=230) + sparkle + kobito(tx, ty, s=s, arms=arms, extra_front=toque() + spoon, face="open") + board
    return squircle("#8FA2B3", "#728698", content, "corkclip")


# --- パネルの縁にしがみつく小人（Resources/kobito-cling.png）。右側の x=54 がパネルの縁で、両手でつかむ（コック帽の分だけ下げて描く。手は KobitoWindow.grip）---
def cling():
    body = f'''<g transform="translate(5 16) rotate(-8 30 22)" stroke-linecap="round" stroke-linejoin="round">
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M19 35 l-2 5 l-1 4.5"/><path d="M28 35.5 l2.5 4 l4 2.5"/></g>
    <path d="M10 23C10 11 16 5 25 5c8 0 13 6 13 16 0 11-6 16-15 16-8 0-13-5-13-14Z" fill="{BODY}" stroke="{INK}" stroke-width="1.7"/>
    <path d="M15 13c5-4 13-4 18 0v12c-5 4-13 4-18 0Z" fill="{SCREEN}" stroke="{INK}" stroke-width="1.4"/>
    <circle cx="22.5" cy="18" r="1.4" fill="{INK}"/><circle cx="29.5" cy="18" r="1.4" fill="{INK}"/>
    <path d="M23.5 22c2 2 4 2 6 0" fill="none" stroke="{INK}" stroke-width="1.2"/>
    {toque()}
    <g fill="none" stroke="{INK}" stroke-width="1.8"><path d="M36 16 Q43 11.5 49 13"/><path d="M37 25 Q43 24 49 22"/></g>
    <circle cx="49" cy="13" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/><circle cx="49" cy="22" r="1.9" fill="{BODY}" stroke="{INK}" stroke-width="1.2"/>
  </g>'''
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64" viewBox="0 0 64 64">{body}</svg>\n'


# --- dmg を開いたときの背景（600×400pt）。左の CorkClip から右の Applications へ、小人が案内する ---
def dmg_background():
    arms = '<path d="M37 24 Q41 22 44.5 17"/><path d="M11.5 26 Q8.5 29 8 32.5"/>'
    guide = kobito(300 - 24 * 1.9, 280, s=1.9, arms=arms, legs="walk", extra_front=toque(), face="open")
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="600" height="400" viewBox="0 0 600 400">
  <defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#F6F3EC"/><stop offset="1" stop-color="#E7E2D6"/></linearGradient></defs>
  <rect width="600" height="400" fill="url(#bg)"/>
  <path d="M0 0 H600 V56 H0 Z" fill="#8FA2B3" opacity=".22"/>
  <text x="300" y="36" text-anchor="middle" font-family="Hiragino Sans, Hiragino Kaku Gothic ProN, sans-serif" font-size="17" font-weight="600" fill="{INK}">CorkClip を Applications フォルダへドラッグしてください</text>
  <path d="M225 190 C265 160 335 160 375 190" fill="none" stroke="#728698" stroke-width="5" stroke-linecap="round" stroke-dasharray="2 12"/>
  <path d="M366 176 L380 193 L360 199" fill="none" stroke="#728698" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
  {guide}
  <text x="300" y="384" text-anchor="middle" font-family="Hiragino Sans, sans-serif" font-size="11" fill="#7A817D">kobito-tools</text>
</svg>
'''


if __name__ == "__main__":
    open(sys.argv[1], "w").write(corkclip())
    if len(sys.argv) > 2:
        open(sys.argv[2], "w").write(cling())
    if len(sys.argv) > 3:
        open(sys.argv[3], "w").write(dmg_background())
