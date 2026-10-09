#!/usr/bin/env python3
"""Web 导出后处理，每次 Godot 重新导出后必须重新执行：

1. 手机适配补丁：竖屏旋转提示 + 全屏按钮（幂等注入）
2. 缓存穿透：pck/js 引用加版本号（?v=时间戳）。
   服务器对 pck/js 下发 immutable 长缓存，URL 不变的话浏览器永远拿旧文件；
   给 mainPack 和 script src 拼上按 pck 修改时间生成的版本号即可强制更新，
   同时保持长缓存收益（URL 变了才会重新下载）。

用法：python tools/patch_web.py [web 目录或 index.html 路径]
"""
import io
import os
import re
import sys
from datetime import datetime

MARK = 'MOBILE-PATCH'
BUST_MARK = '/*CACHE-BUST*/'

INJECT = '''<!-- MOBILE-PATCH -->
<style>
html, body { height: 100%; }
#rotate-hint { position: fixed; inset: 0; z-index: 9999; display: none;
  background: linear-gradient(180deg, #06121f 0%, #0a2237 100%);
  color: #cfe4f2; font-family: sans-serif; text-align: center;
  flex-direction: column; justify-content: center; align-items: center; gap: 18px; }
@media (orientation: portrait) { #rotate-hint { display: flex; } }
#rotate-hint .icon { font-size: 64px; animation: rot 2s ease-in-out infinite; }
@keyframes rot { 0%, 40% { transform: rotate(0); } 70%, 100% { transform: rotate(90deg); } }
#rotate-hint .t1 { font-size: 22px; font-weight: 600; letter-spacing: 2px; }
#rotate-hint .t2 { font-size: 14px; opacity: .6; letter-spacing: 4px; }
#fs-btn { position: fixed; right: 10px; bottom: 10px; z-index: 9998; display: none;
  width: 42px; height: 42px; border-radius: 10px; border: 1px solid rgba(120,180,220,.35);
  background: rgba(6,18,31,.55); color: #cfe4f2; font-size: 19px; line-height: 40px;
  text-align: center; user-select: none; -webkit-user-select: none; touch-action: manipulation;
  cursor: pointer; }
</style>
<div id="rotate-hint"><div class="icon">📱</div><div class="t1">请旋转手机横屏游玩</div><div class="t2">冰川信使 · 斑头雁的 2040</div></div>
<div id="fs-btn" title="全屏">⛶</div>
<script>
(function () {
  var b = document.getElementById('fs-btn');
  if (!document.documentElement.requestFullscreen) return;
  if (matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window) b.style.display = 'block';
  b.addEventListener('click', function () {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen().catch(function () {});
  });
  window.addEventListener('fullscreenchange', function () {
    b.textContent = document.fullscreenElement ? '✕' : '⛶';
  });
})();
</script>'''


def find_pck(web_dir: str) -> str:
    """找 web 目录下的主 pck（排除 .gz）。"""
    cands = [f for f in os.listdir(web_dir) if f.endswith('.pck')]
    if not cands:
        raise SystemExit('no .pck found in ' + web_dir)
    # 取最大的那个（主包）
    return max(cands, key=lambda f: os.path.getsize(os.path.join(web_dir, f)))


def apply_cache_bust(s: str, web_dir: str) -> str:
    pck = find_pck(web_dir)
    ver = 'v' + datetime.fromtimestamp(os.path.getmtime(os.path.join(web_dir, pck))).strftime('%Y%m%d%H%M')
    size = os.path.getsize(os.path.join(web_dir, pck))
    js_name = pck[:-4] + '.js'

    block = (
        f'{BUST_MARK}\n'
        f"const PCK_VER = '{ver}';\n"
        f"GODOT_CONFIG['mainPack'] = `{pck}?${{PCK_VER}}`;\n"
        f"GODOT_CONFIG['fileSizes'][`{pck}?${{PCK_VER}}`] = {size};\n"
    )
    # 替换旧版本块或插入新块
    if BUST_MARK in s:
        s = re.sub(re.escape(BUST_MARK) + r'.*?\n(?=const engine)', block, s, flags=re.S)
    else:
        anchor = 'const engine = new Engine(GODOT_CONFIG);'
        assert anchor in s, 'GODOT_CONFIG anchor not found'
        s = s.replace(anchor, block + anchor)

    # 引擎 JS 引用加版本号（旧版可能带 ?v=...）
    s = re.sub(
        r'(<script src="' + re.escape(js_name) + r')(\?[^"]*)?(")',
        r'\g<1>?' + ver + r'\g<3>',
        s)
    print(f'cache-bust: {pck} {ver} ({size} bytes)')
    return s


def apply_mobile_patch(s: str) -> str:
    if MARK in s:
        return s
    old_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
    new_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover">'
    if old_vp in s:
        s = s.replace(old_vp, new_vp)
    assert '</body>' in s, 'no </body> found'
    s = s.replace('</body>', INJECT + '\n</body>')
    print('mobile-patch: injected')
    return s


def main() -> None:
    arg = sys.argv[1] if len(sys.argv) > 1 else 'web'
    if os.path.isdir(arg):
        path = os.path.join(arg, 'index.html')
        web_dir = arg
    else:
        path = arg
        web_dir = os.path.dirname(arg) or '.'
    s = io.open(path, encoding='utf-8').read()
    s = apply_mobile_patch(s)
    s = apply_cache_bust(s, web_dir)
    io.open(path, 'w', encoding='utf-8', newline='\n').write(s)
    print('patched:', path)


if __name__ == '__main__':
    main()
