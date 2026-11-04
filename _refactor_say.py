import io
import re

p = r"E:\alien-invasion-3d\main.gd"
src = io.open(p, encoding="utf-8").read()

# 1) 单行 hud_result.text = X  ->  _say(X)
pat = re.compile(r"^(\s*)hud_result\.text = (.+)$", re.M)
funcs = []

def repl(m):
    indent, expr = m.group(1), m.group(2).strip()
    return f"{indent}_say({expr})"

src, n = pat.subn(repl, src)
io.open(p, "w", encoding="utf-8").write(src)
print("replaced", n)
