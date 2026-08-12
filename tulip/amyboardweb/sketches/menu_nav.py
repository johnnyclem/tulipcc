# AMYboard Sketch
# Top-level code runs once at boot. loop(step) is called every 32nd note.
# DESCRIPTION: Minimal encoder menu — Juno / DX7 patches + I/O config.
#
# Controls (any amyboard.encoder() device):
#   turn        — move cursor / scroll list
#   short click — enter / load / cycle value
#   hold        — go back
#
# Needs a front-panel I2C encoder (Adafruit STEMMA single/quad, or M5 8Encoder)
# plus the 128x128 OLED. Daisy-chain both on the front Grove jack.
import amyboard, amy, midi
from patches import patches as PRESETS

# --- Patch banks ---
JUNO_BASE, JUNO_N = 0, 128
DX7_BASE, DX7_N = 128, 128

# --- Screens ---
SCR_MAIN = 0
SCR_PATCHES = 1
SCR_IO = 2

# --- I/O item indices ---
IO_MIDI = 0
IO_VOICES = 1
IO_CV1 = 2
IO_CV2 = 3
IO_N = 4

CV_MODES = ("Off", "Note V/oct", "CC23")
MAIN_ITEMS = ("JUNO", "DX7", "I/O")

# --- State ---
screen = SCR_MAIN
main_sel = 0
bank = "JUNO"          # or "DX7"
patch_sel = 0          # index within bank (0..127)
loaded = -1            # absolute AMY patch number, or -1
io_sel = 0
voices = 6
midi_out = "A"         # "A" or "B"
cv_mode = [0, 0]       # per CV jack: index into CV_MODES
dirty = True

enc = None
last_pos = 0
_no_enc_drawn = False

d = amyboard.display
if d is None or not getattr(d, "available", False):
    amyboard.init_display()
    d = amyboard.display


def _clip(name, n=16):
    name = (name or "").strip()
    return name if len(name) <= n else name[: n - 1] + "~"


def _bank_abs(i):
    base = JUNO_BASE if bank == "JUNO" else DX7_BASE
    return base + (i % (JUNO_N if bank == "JUNO" else DX7_N))


def _ensure_encoder():
    global enc, last_pos, _no_enc_drawn
    if enc is not None and enc.encoders > 0:
        return True
    enc = amyboard.encoder()
    if enc.encoders > 0:
        # Some singles count the wrong way; invert so clockwise = +1.
        enc.invert(True, 0)
        last_pos = enc.read(0)
        _no_enc_drawn = False
        if enc.leds > 0:
            enc.led(0, 0, 40, 0)
        return True
    return False


def _apply_midi_type():
    try:
        amyboard.set_midi_type(midi_out)
    except Exception:
        pass


def _apply_patch(abs_idx):
    global loaded
    amy.send(synth=1, patch=abs_idx, num_voices=voices)
    loaded = abs_idx
    if enc is not None and enc.leds > 0:
        enc.led(0, 0, 80, 0)


def _cv_from_note(note):
    # 1V/oct, MIDI 0 = 0V (matches midi2cv sketch)
    return note / 12.0


def _cv_from_cc(val):
    # 0..127 -> -10..+10 V
    return (val / 127.0) * 20.0 - 10.0


def _midi_cb(m):
    if not m or len(m) < 3:
        return
    status = m[0] & 0xF0
    a, b = m[1], m[2]
    for ch in (0, 1):
        mode = cv_mode[ch]
        if mode == 0:
            continue
        if mode == 1 and status == 0x90 and b > 0:
            amyboard.cv_out(_cv_from_note(a), channel=ch)
        elif mode == 2 and status == 0xB0 and a == 23:
            amyboard.cv_out(_cv_from_cc(b), channel=ch)


midi.add_callback(_midi_cb)
_apply_midi_type()


# ---------- drawing (only from loop, never tight-spin) ----------

def _header(title):
    d.fill(0)
    d.text(title, 0, 0, 255)
    d.hline(0, 10, 128, 128)


def draw_no_encoder():
    global _no_enc_drawn
    if _no_enc_drawn:
        return
    d.fill(0)
    d.text("MENU NAV", 0, 0, 255)
    d.text("plug encoder", 0, 24, 255)
    d.text("on front I2C", 0, 36, 255)
    d.text("Grove jack", 0, 48, 255)
    d.text("(STEMMA QT", 0, 72, 255)
    d.text(" or M5 unit)", 0, 84, 255)
    amyboard.display_refresh()
    _no_enc_drawn = True


def draw_main():
    _header("MENU")
    for i, name in enumerate(MAIN_ITEMS):
        y = 16 + i * 14
        mark = ">" if i == main_sel else " "
        d.text("%s %s" % (mark, name), 0, y, 255)
    if loaded >= 0:
        d.text(_clip("*%s" % PRESETS[loaded], 16), 0, 72, 128)
    d.text("turn/click", 0, 100, 64)
    d.text("hold=back", 0, 112, 64)
    amyboard.display_refresh()


def draw_patches():
    abs_i = _bank_abs(patch_sel)
    name = PRESETS[abs_i] if abs_i < len(PRESETS) else "?"
    _header(bank)
    d.text("%03d / %d" % (patch_sel, JUNO_N - 1), 0, 16, 255)
    d.text(_clip(name, 16), 0, 32, 255)
    if len(name.strip()) > 16:
        d.text(_clip(name.strip()[16:], 16), 0, 44, 255)
    if abs_i == loaded:
        d.text("[LOADED]", 0, 64, 255)
    else:
        d.text("click=load", 0, 64, 128)
    d.text("hold=back", 0, 100, 64)
    amyboard.display_refresh()


def _io_label(i):
    if i == IO_MIDI:
        return "MIDI OUT", midi_out
    if i == IO_VOICES:
        return "VOICES", str(voices)
    if i == IO_CV1:
        return "CV1", CV_MODES[cv_mode[0]]
    if i == IO_CV2:
        return "CV2", CV_MODES[cv_mode[1]]
    return "?", "?"


def draw_io():
    _header("I/O")
    # show 4 lines; selected marked
    for i in range(IO_N):
        lab, val = _io_label(i)
        y = 16 + i * 16
        mark = ">" if i == io_sel else " "
        # name on left, value truncated on right-ish
        line = "%s%s" % (mark, lab)
        d.text(line, 0, y, 255)
        d.text(_clip(val, 10), 56, y, 255 if i == io_sel else 128)
    d.text("click=cycle", 0, 100, 64)
    d.text("hold=back", 0, 112, 64)
    amyboard.display_refresh()


def redraw():
    global dirty
    if screen == SCR_MAIN:
        draw_main()
    elif screen == SCR_PATCHES:
        draw_patches()
    elif screen == SCR_IO:
        draw_io()
    dirty = False


# ---------- input ----------

def on_turn(delta):
    global main_sel, patch_sel, io_sel, dirty
    if delta == 0:
        return
    step = 1 if delta > 0 else -1
    # multi-detent: use sign only (one step per event burst)
    if abs(delta) > 1:
        step = 1 if delta > 0 else -1
    if screen == SCR_MAIN:
        main_sel = (main_sel + step) % len(MAIN_ITEMS)
        dirty = True
    elif screen == SCR_PATCHES:
        n = JUNO_N if bank == "JUNO" else DX7_N
        patch_sel = (patch_sel + step) % n
        dirty = True
    elif screen == SCR_IO:
        io_sel = (io_sel + step) % IO_N
        dirty = True


def on_press():
    global screen, bank, patch_sel, dirty, midi_out, voices
    if screen == SCR_MAIN:
        name = MAIN_ITEMS[main_sel]
        if name == "JUNO":
            bank = "JUNO"
            if loaded >= JUNO_BASE and loaded < JUNO_BASE + JUNO_N:
                patch_sel = loaded - JUNO_BASE
            else:
                patch_sel = 0
            screen = SCR_PATCHES
        elif name == "DX7":
            bank = "DX7"
            if loaded >= DX7_BASE and loaded < DX7_BASE + DX7_N:
                patch_sel = loaded - DX7_BASE
            else:
                patch_sel = 0
            screen = SCR_PATCHES
        elif name == "I/O":
            screen = SCR_IO
        dirty = True
    elif screen == SCR_PATCHES:
        _apply_patch(_bank_abs(patch_sel))
        dirty = True
    elif screen == SCR_IO:
        if io_sel == IO_MIDI:
            midi_out = "B" if midi_out == "A" else "A"
            _apply_midi_type()
        elif io_sel == IO_VOICES:
            voices = 1 if voices >= 8 else voices + 1
            if loaded >= 0:
                _apply_patch(loaded)
        elif io_sel == IO_CV1:
            cv_mode[0] = (cv_mode[0] + 1) % len(CV_MODES)
        elif io_sel == IO_CV2:
            cv_mode[1] = (cv_mode[1] + 1) % len(CV_MODES)
        dirty = True


def on_hold():
    global screen, dirty
    if screen in (SCR_PATCHES, SCR_IO):
        screen = SCR_MAIN
        dirty = True
        if enc is not None and enc.leds > 0:
            enc.led(0, 20, 20, 40)


# ---------- main loop ----------

def loop(step):
    global last_pos, dirty
    if not _ensure_encoder():
        # re-check every half bar so hot-plug works
        if step % 16 == 0:
            draw_no_encoder()
        return

    pos = enc.read(0)
    delta = pos - last_pos
    if delta:
        last_pos = pos
        on_turn(delta)

    enc.poll_button_events()
    while True:
        ev = enc.button_event(0)
        if not ev:
            break
        _i, kind = ev
        if kind == amyboard.PRESS:
            on_press()
        elif kind == amyboard.HELD:
            on_hold()

    if dirty:
        redraw()


# first paint (no encoder yet → prompt)
if _ensure_encoder():
    redraw()
else:
    draw_no_encoder()
