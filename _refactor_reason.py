import io, re

p = r"E:\alien-invasion-3d\main.gd"
src = io.open(p, encoding="utf-8").read()

reason_of = {
    "win_probe_title": "PROBE",
    "m_probe_title": "PROBE",
    "lose_arrive_title": "ARRIVE",
    "m_arrive_title": "ARRIVE",
    "win_timeout_title": "TIMEOUT",
    "m_timeout_title": "TIMEOUT",
    "win_mine_title": "MINE",
    "m_mine_title": "MINE",
    "win_fire_title": "FIRE",
    "m_fire_title": "FIRE",
    "win_nade_title": "NADE",
    "m_nade_title": "NADE",
}

pat = re.compile(r'_finish\(Texts\.s\("([a-z_]+)"\), Texts\.s\("([a-z_]+)"\), ([^)]+)\)')

def repl(m):
    key, sub, col = m.group(1), m.group(2), m.group(3).strip()
    r = reason_of.get(key)
    if r is None:
        return m.group(0)
    return f'_finish(Texts.s("{key}"), Texts.s("{sub}"), {col}, "{r}")'

src, n = pat.subn(repl, src)
io.open(p, "w", encoding="utf-8").write(src)
print("patched", n)
