import io, re

p = r"E:\alien-invasion-3d\main.gd"
src = io.open(p, encoding="utf-8").read()

# 上一次的正则把 Color(0.75, 0.72, 0.60) 吞成了 Color(0.75, 0.72, 0.60, "TIMEOUT")
pat = re.compile(r'Color\(([0-9.,\s]+?), "([A-Z]+)"\)\)')

def repl(m):
    return f'Color({m.group(1)}), "{m.group(2)}")'

src, n = pat.subn(repl, src)
io.open(p, "w", encoding="utf-8").write(src)
print("fixed", n)
