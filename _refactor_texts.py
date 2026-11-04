import io, sys, re

p = r"E:\alien-invasion-3d\main.gd"
src = io.open(p, encoding="utf-8").read()

pairs = [
    ('hud_result.text = "等房主开局……"', 'hud_result.text = Texts.s("guest_wait")'),
    ('hud_result.text = "你在出生点。开局这 4 步归你自己 — 走完按空格，才轮到他。"', 'hud_result.text = Texts.s("seat_opening")'),
    ('hud_result.text = "放下了。"', 'hud_result.text = Texts.s("put_down")'),
    ('hud_result.text = "递上去了。等那边的回音。"', 'hud_result.text = Texts.s("probe_wait")'),
    ('hud_result.text = "这儿什么都没有。真乖 —— 继续猜。"', 'hud_result.text = Texts.s("res_empty")'),
    ('hud_result.text = "它踩过这里。印子还热着，它已经走了。"', 'hud_result.text = Texts.s("res_trail")'),
    ('hud_result.text = "找到了。可惜，它先看见了你。"', 'hud_result.text = Texts.s("res_hit")'),
    ('hud_result.text = "擦到了。它流了点东西，然后跑得更快了。"', 'hud_result.text = Texts.s("hit_wounded")'),
    ('hud_result.text = "墙塌了。它没停 —— 那一声你听见了吧。"', 'hud_result.text = Texts.s("wall_crash")'),
    ('hud_result.text = "先布防。它不知道你埋在哪，你也不知道它从哪条路来。"', 'hud_result.text = Texts.s("setup_ask")'),
    ('hud_result.text = "布防完了。等他走开局的 4 步 —— 不计回合，你看不见。"', 'hud_result.text = Texts.s("setup_done_wait")'),
    ('hud_result.text = "布防完了。轮到他先走 4 步 —— 不计回合，你看不见。"', 'hud_result.text = Texts.s("setup_done_host")'),
    ('hud_result.text = "布防完了。它先走 4 步 —— 不计回合，你也看不见。"', 'hud_result.text = Texts.s("setup_done_sp")'),
    ('hud_result.text = "踩响了。它没死，只是更恨你了。"', 'hud_result.text = Texts.s("mine_hit")'),
    ('hud_result.text = "响了。那儿没人 —— 你浪费了一颗。"', 'hud_result.text = Texts.s("mine_miss")'),
    ('hud_result.text = "这颗已经用掉了。别抠空盒子。"', 'hud_result.text = Texts.s("throw_empty")'),
    ('hud_result.text = "%s在手上。点一格，扔出去（Esc 放下）。" % names[kind]', 'hud_result.text = Texts.s("throw_arm") % names[kind]'),
    ('hud_result.text = "那儿扔不了。"', 'hud_result.text = Texts.s("throw_cant")'),
    ('hud_result.text = "扔出去了。"', 'hud_result.text = Texts.s("throw_done")'),
    ('hud_result.text = "晃到了。九格里有东西，它现在睁不开眼。"', 'hud_result.text = Texts.s("flash_hit")'),
    ('hud_result.text = "亮了。九格干净得像新的一样。"', 'hud_result.text = Texts.s("flash_miss")'),
    ('hud_result.text = "放下了。下一回合，它替你去看看。"', 'hud_result.text = Texts.s("nade_placed")'),
    ('hud_result.text = "烧起来了。这片地会一直烫着。"', 'hud_result.text = Texts.s("fire_placed")'),
    ('hud_result.text = "轮到它了。"', 'hud_result.text = Texts.s("turn_other")'),
    ('hud_result.text = "对面断开了。"', 'hud_result.text = Texts.s("peer_left")'),
    ('hud_end.text = "他走了。"', 'hud_end.text = Texts.s("peer_left_end")'),
    ('hud_result.text = sub + "\\n按 R 回标题"', 'hud_result.text = sub + "\\n" + Texts.s("press_r")'),
    ('_notify("他正在布防。布完你走开局的 4 步。")', '_notify(Texts.s("seat_wait_deploy"))'),
    ('_notify("你现在坐在它对面。他查哪一格，你都看得见。")', '_notify(Texts.s("seat_human_here"))'),
    ('_finish("查中了。", "它一直在等你看错 —— 这一次它等错了。", PINK_HOT)', '_finish(Texts.s("win_probe_title"), Texts.s("win_probe_sub"), PINK_HOT)'),
    ('_finish("踩响了。", "它以为那是你查格子的声音。", PINK_HOT)', '_finish(Texts.s("win_mine_title"), Texts.s("win_mine_sub"), PINK_HOT)'),
    ('_finish("它到了。", "你一直看着的那个方向，其实不是它来的方向。", Color(0.80, 0.22, 0.22))', '_finish(Texts.s("lose_arrive_title"), Texts.s("lose_arrive_sub"), Color(0.80, 0.22, 0.22))'),
    ('_finish("天亮了。", "二十回合，它没能进门。", Color(0.75, 0.72, 0.60))', '_finish(Texts.s("win_timeout_title"), Texts.s("win_timeout_sub"), Color(0.75, 0.72, 0.60))'),
    ('_finish("你到了。", "他一直在查别的地方。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("m_arrive_title"), Texts.s("m_arrive_sub"), Color(0.85, 0.35, 0.30))'),
    ('_finish("天亮了。", "二十回合，他没能找到你。", Color(0.75, 0.72, 0.60))', '_finish(Texts.s("m_timeout_title"), Texts.s("m_timeout_sub"), Color(0.75, 0.72, 0.60))'),
    ('_finish("他找到你了。", "你会出现在他下一眼的余光里。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("m_probe_title"), Texts.s("m_probe_sub"), Color(0.85, 0.35, 0.30))'),
    ('_finish("踩雷了。", "他根本没看见你 —— 只是把雷放在了你必经的那条路上。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("m_mine_title"), Texts.s("m_mine_sub"), Color(0.85, 0.35, 0.30))'),
    ('_finish("烧掉了。", "它一直没从火光里走出来。", Color(0.85, 0.40, 0.24))', '_finish(Texts.s("win_fire_title"), Texts.s("win_fire_sub"), Color(0.85, 0.40, 0.24))'),
    ('_finish("你被烧掉了。", "火一直在那儿，你没绕开。", Color(0.85, 0.40, 0.24))', '_finish(Texts.s("m_fire_title"), Texts.s("m_fire_sub"), Color(0.85, 0.40, 0.24))'),
    ('_finish("炸中了。", "你只是把九格都试了一遍。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("win_nade_title"), Texts.s("win_nade_sub"), Color(0.85, 0.35, 0.30))'),
    ('_finish("你被炸中了。", "那颗雷落地的时候，你没走开。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("m_nade_title"), Texts.s("m_nade_sub"), Color(0.85, 0.35, 0.30))'),
    ('_finish("他找到了你。", "灯亮在他那边。", Color(0.85, 0.35, 0.30))', '_finish(Texts.s("m_other_title"), Texts.s("m_other_sub"), Color(0.85, 0.35, 0.30))'),
]

missing = []
for old, new in pairs:
    if old not in src:
        missing.append(old)
    else:
        src = src.replace(old, new)

io.open(p, "w", encoding="utf-8", newline="\n").write(src)
print("missing:", len(missing))
for m in missing:
    print("  MISS:", m[:60])
