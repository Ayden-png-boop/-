#!/usr/bin/env python3
"""Web 导出后处理，每次 Godot 重新导出后必须重新执行：

1. 手机适配补丁：强制横屏（全屏+方向锁，失败降级为 2 秒竖屏提示）+ 加载进度 HUD + 全屏按钮（幂等注入）
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
/* 横屏提示：仅 JS 检测到竖屏时显示，2 秒后自动消失（CSS 媒体查询在部分安卓上判断失真） */
#rotate-hint { position: fixed; inset: 0; z-index: 9999; display: none;
  background: linear-gradient(180deg, #06121f 0%, #0a2237 100%);
  color: #cfe4f2; font-family: sans-serif; text-align: center;
  flex-direction: column; justify-content: center; align-items: center; gap: 18px; }
#rotate-hint .icon { font-size: 64px; animation: rot 2s ease-in-out infinite; }
@keyframes rot { 0%, 40% { transform: rotate(0); } 70%, 100% { transform: rotate(90deg); } }
#rotate-hint .t1 { font-size: 22px; font-weight: 600; letter-spacing: 2px; }
#rotate-hint .t2 { font-size: 14px; opacity: .6; letter-spacing: 4px; }
#fs-btn { position: fixed; right: 10px; bottom: 10px; z-index: 9998; display: none;
  width: 42px; height: 42px; border-radius: 10px; border: 1px solid rgba(120,180,220,.35);
  background: rgba(6,18,31,.55); color: #cfe4f2; font-size: 19px; line-height: 40px;
  text-align: center; user-select: none; -webkit-user-select: none; touch-action: manipulation;
  cursor: pointer; }
#load-hud { position: fixed; left: 0; right: 0; bottom: 15%; z-index: 9000;
  display: none; flex-direction: column; align-items: center; gap: 10px;
  color: #cfe4f2; font-family: sans-serif; pointer-events: none; }
#load-hud .lb { font-size: 14px; letter-spacing: 2px; opacity: .9;
  text-shadow: 0 1px 4px rgba(0,0,0,.6); }
#load-hud .tip { font-size: 12px; letter-spacing: 1px; opacity: .55;
  text-shadow: 0 1px 4px rgba(0,0,0,.6); }
#load-bar { width: 62%; max-width: 340px; height: 6px; border-radius: 3px;
  background: rgba(120,180,220,.18); overflow: hidden; }
#load-bar .fill { width: 0%; height: 100%; border-radius: 3px;
  background: linear-gradient(90deg, #4aa3c7, #7fd0ea); transition: width .3s; }
</style>
<div id="rotate-hint"><div class="icon">📱</div><div class="t1">请横屏游玩</div><div class="t2">冰川信使 · 斑头雁的 2040</div></div>
<div id="load-hud"><div class="lb" id="load-label">正在加载游戏资源… 0%</div><div id="load-bar"><div class="fill" id="load-fill"></div></div><div class="tip">首次加载约 20MB，手机网络下可能需要 1~2 分钟</div></div>
<div id="fs-btn" title="全屏">⛶</div>
<script>
(function () {
  var isTouch = matchMedia('(pointer: coarse)').matches || 'ontouchstart' in window;
  if (!isTouch) return;

  // 手动全屏切换按钮
  var b = document.getElementById('fs-btn');
  b.style.display = 'block';
  b.addEventListener('click', function () {
    if (document.fullscreenElement) document.exitFullscreen();
    else document.documentElement.requestFullscreen().catch(function () {});
  });
  window.addEventListener('fullscreenchange', function () {
    b.textContent = document.fullscreenElement ? '✕' : '⛶';
  });

  var hint = document.getElementById('rotate-hint');
  var hintTimer = null;
  function isPortrait() { return window.innerHeight > window.innerWidth; }

  // 强制横屏：全屏 + 方向锁（Android Chrome 需全屏和用户手势，失败则静默降级为 2 秒提示）
  function tryForceLandscape() {
    if (!isPortrait()) return;
    function lock() {
      try {
        if (screen.orientation && screen.orientation.lock) {
          var p = screen.orientation.lock('landscape');
          if (p && p.catch) p.catch(function () {});
        }
      } catch (e) {}
    }
    try {
      if (document.fullscreenElement) { lock(); return; }
      if (document.documentElement.requestFullscreen) {
        var r = document.documentElement.requestFullscreen();
        if (r && r.then) r.then(lock).catch(function () {});
        else lock();
      } else lock();
    } catch (e) {}
  }

  // 方向提示：竖屏时最多显示 2 秒，横屏绝不显示
  function syncHint() {
    clearTimeout(hintTimer);
    if (isPortrait()) {
      hint.style.display = 'flex';
      hintTimer = setTimeout(function () { hint.style.display = 'none'; }, 2000);
    } else {
      hint.style.display = 'none';
    }
  }
  hint.addEventListener('click', function () {
    clearTimeout(hintTimer);
    hint.style.display = 'none';
  });
  window.addEventListener('resize', syncHint);
  window.addEventListener('orientationchange', function () {
    setTimeout(syncHint, 350);
    tryForceLandscape();
  });
  syncHint();
  tryForceLandscape();
  // 浏览器要求用户手势：首次触摸时再尝试一次强制横屏
  document.addEventListener('touchstart', function once() {
    document.removeEventListener('touchstart', once);
    tryForceLandscape();
  }, { passive: true });

  // 加载进度 HUD：轮询 Godot 原生进度条数值，渲染醒目的百分比 + 进度条
  var hud = document.getElementById('load-hud');
  var label = document.getElementById('load-label');
  var fill = document.getElementById('load-fill');
  hud.style.display = 'flex';
  var timer = setInterval(function () {
    var status = document.getElementById('status');
    if (!status) {  // 加载完成，原生 overlay 已被移除
      clearInterval(timer);
      hud.style.display = 'none';
      return;
    }
    var p = document.getElementById('status-progress');
    var v = p && p.hasAttribute('value') ? Number(p.value) : 0;
    var m = p && p.hasAttribute('max') ? Number(p.max) : 0;
    var pct = m > 0 ? Math.min(100, Math.round(v / m * 100)) : 0;
    label.textContent = '正在加载游戏资源… ' + pct + '%';
    fill.style.width = pct + '%';
  }, 250);
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
    # 加载 splash 图加版本号（png 走 immutable 长缓存，内容更新必须换 URL）
    splash = pck[:-4] + '.png'
    s = re.sub(
        r'(id="status-splash"[^>]*src="' + re.escape(splash) + r')(\?[^"]*)?(")',
        r'\g<1>?' + ver + r'\g<3>',
        s)
    print(f'cache-bust: {pck} {ver} ({size} bytes)')
    return s


def apply_mobile_patch(s: str) -> str:
    old_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
    new_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover">'
    if old_vp in s:
        s = s.replace(old_vp, new_vp)
    # 已有旧版补丁则先剥离，保证重新注入的是最新版本（幂等更新）
    if MARK in s:
        s, n = re.subn(r'<!-- MOBILE-PATCH -->.*?</script>\n', '', s, flags=re.S)
        if n != 1:
            raise SystemExit(f'mobile-patch: expected 1 old block, found {n}; aborting')
        print('mobile-patch: old block stripped')
    assert '</body>' in s, 'no </body> found'
    assert MARK not in s, 'mobile-patch block not fully stripped'
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
