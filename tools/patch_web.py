#!/usr/bin/env python3
"""Web 导出后处理：手机适配补丁（竖屏旋转提示 + 全屏按钮）。

用法：python tools/patch_web.py [index.html 路径]
每次 Godot 重新导出 Web 后需要重新执行（导出器会覆盖 index.html）。
幂等：重复执行无副作用。
"""
import io
import sys

MARK = 'MOBILE-PATCH'

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


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else 'web/index.html'
    s = io.open(path, encoding='utf-8').read()
    if MARK in s:
        print('already patched:', path)
        return
    old_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0">'
    new_vp = '<meta name="viewport" content="width=device-width, user-scalable=no, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover">'
    if old_vp in s:
        s = s.replace(old_vp, new_vp)
    assert '</body>' in s, 'no </body> found'
    s = s.replace('</body>', INJECT + '\n</body>')
    io.open(path, 'w', encoding='utf-8', newline='\n').write(s)
    print('patched:', path)


if __name__ == '__main__':
    main()
