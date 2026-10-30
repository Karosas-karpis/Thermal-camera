#!/usr/bin/env python3
"""Receive raw MI48 SPI frames from the Basys 3 UART (uart_dump.v) and analyse them.

  python3 dump_frames.py                      # /dev/ttyUSB1, 921600 baud, 3 frames
  python3 dump_frames.py --port /dev/ttyUSB1 --frames 10 --save frames
  python3 dump_frames.py --file frames_0.bin   # analyse a saved frame, no board needed

Packet: DE AD BE EF, flags byte, then 80 header + 62x80 pixel (5040 in all) big-endian 16-bit words,
then a 16-bit sum of all the words (a mismatch means bytes were lost or changed on the UART).
flags bit0 = reader's CRC ok, bit1 = sync_early seen, bit2 = sync_late seen.
"""
import argparse
import sys

import numpy as np

MAGIC = bytes([0xDE, 0xAD, 0xBE, 0xEF])
LEAD_WORDS = 9                         # words before the header (SPI_LEAD_WORDS in top_thermal.v)
HEADER_WORDS = 80
ROWS, COLS = 62, 80
WORDS = HEADER_WORDS + ROWS * COLS      # frame length on the wire; the lead words are part of it
TEMP_LO, TEMP_HI = 2300, 8000          # 0.1 K units, same range the FPGA accepts


def open_port(path, baud):
    try:
        import serial
        return serial.Serial(path, baud, timeout=2)
    except ImportError:
        pass
    import os
    import termios
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY)
    attrs = termios.tcgetattr(fd)
    speed = getattr(termios, "B%d" % baud)
    attrs[0] = 0
    attrs[1] = 0
    attrs[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attrs[3] = 0
    attrs[4] = attrs[5] = speed
    attrs[6][termios.VMIN] = 0
    attrs[6][termios.VTIME] = 20
    termios.tcsetattr(fd, termios.TCSANOW, attrs)

    class Port:
        def read(self, n):
            out = b""
            while len(out) < n:
                chunk = os.read(fd, n - len(out))
                if not chunk:
                    break
                out += chunk
            return out

        def reset_input_buffer(self):
            termios.tcflush(fd, termios.TCIFLUSH)

    return Port()


def read_packet(port):
    """Return (flags, words) for the next complete packet, or None on timeout."""
    window = b""
    while window != MAGIC:
        b = port.read(1)
        if not b:
            return None
        window = (window + b)[-4:]
    flags = port.read(1)
    body = port.read(WORDS * 2 + 2)
    if not flags or len(body) != WORDS * 2 + 2:
        return None
    words = np.frombuffer(body[:-2], dtype=">u2").astype(np.int64)
    got = int(words.sum()) & 0xFFFF
    want = (body[-2] << 8) | body[-1]
    if got != want:
        print("UART TRANSPORT ERROR: sum %04X != sent %04X (bytes lost or corrupted between FPGA and PC)" % (got, want))
    return flags[0], words


def _make_table(poly, reflected):
    table = []
    for i in range(256):
        if reflected:
            c = i
            for _ in range(8):
                c = (c >> 1) ^ poly if c & 1 else c >> 1
        else:
            c = i << 8
            for _ in range(8):
                c = ((c << 1) ^ poly) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
        table.append(c)
    return table


# name: (poly as used, reflected, init, xorout)
CRC_ALGOS = {
    "CCITT-FALSE": (0x1021, False, 0xFFFF, 0x0000),
    "XMODEM": (0x1021, False, 0x0000, 0x0000),
    "AUG-CCITT": (0x1021, False, 0x1D0F, 0x0000),
    "KERMIT": (0x8408, True, 0x0000, 0x0000),
    "X-25": (0x8408, True, 0xFFFF, 0xFFFF),
    "MCRF4XX": (0x8408, True, 0xFFFF, 0x0000),
    "ARC": (0xA001, True, 0x0000, 0x0000),
    "MODBUS": (0xA001, True, 0xFFFF, 0x0000),
}
_TABLES = {name: _make_table(a[0], a[1]) for name, a in CRC_ALGOS.items()}


def crc16(data, name):
    poly, reflected, crc, xorout = CRC_ALGOS[name]
    table = _TABLES[name]
    if reflected:
        for byte in data:
            crc = (crc >> 8) ^ table[(crc ^ byte) & 0xFF]
    else:
        for byte in data:
            crc = ((crc << 8) & 0xFFFF) ^ table[(crc >> 8) ^ byte]
    return crc ^ xorout


def words_to_bytes(w, order):
    w = np.asarray(w, dtype=np.uint16)
    return (w.astype(">u2") if order == "be" else w.astype("<u2")).tobytes()


def analyse(words, flags):
    lead = words[:LEAD_WORDS]
    hdr = words[LEAD_WORDS:LEAD_WORDS + HEADER_WORDS]
    # Hypothesis: the lead words are the last LEAD_WORDS pixels, sent first
    pix = np.concatenate([words[LEAD_WORDS + HEADER_WORDS:], lead])
    img = pix.reshape(ROWS, COLS)

    print("flags: crc_ok=%d sync_early=%d sync_late=%d" % (flags & 1, (flags >> 1) & 1, (flags >> 2) & 1))
    print("lead words        :", " ".join("%04X" % v for v in lead))
    print("header words 0-15 :", " ".join("%04X" % v for v in hdr[:16]))
    print("header words 64-79:", " ".join("%04X" % v for v in hdr[64:80]))
    print("first 12 pixels   :", " ".join("%04X" % v for v in pix[:12]))
    print("last 12 pixels    :", " ".join("%04X" % v for v in pix[-12:]))

    ok = (pix >= TEMP_LO) & (pix <= TEMP_HI)
    print("pixels in %d..%d: %d/%d" % (TEMP_LO, TEMP_HI, ok.sum(), pix.size),
          "| min %d max %d median %d" % (pix.min(), pix.max(), np.median(pix)))
    bad = np.flatnonzero(~ok)
    if bad.size:
        print("  out-of-range pixel indices (first 20):", bad[:20].tolist())

    # Header CRC guess: word 7 against standard CRC-16s over several candidate ranges
    want = int(hdr[7])
    stream = words.copy()
    stream[LEAD_WORDS + 7] = 0
    body = words[LEAD_WORDS + HEADER_WORDS:]
    hdr_wo7 = np.delete(hdr, 7)
    windows = {
        "pixels (body, lead)": np.concatenate([body, lead]),
        "pixels (lead, body)": np.concatenate([lead, body]),
        "body only": body,
        "header w/o word 7": hdr_wo7,
        "header words 0-6": hdr[:7],
        "header w/o 7 + pixels": np.concatenate([hdr_wo7, body, lead]),
        "whole stream, w7=0": stream,
        "stream from header, w7=0": stream[LEAD_WORDS:],
    }
    hits = []
    for wname, w in windows.items():
        for order in ("be", "le"):
            data = words_to_bytes(w, order)
            for aname in CRC_ALGOS:
                if crc16(data, aname) == want:
                    hits.append("%s | %s bytes | %s" % (wname, order, aname))
    print("header word 7 = %04X; CRC-16 matches: %s" % (want, hits if hits else "none of the tried variants"))

    # Seam detector: mean |difference| between horizontally adjacent pixels per column pair.
    # A shift of N words shows as a seam (high value) at column N-1 -> N.
    diff = np.abs(np.diff(img, axis=1)).mean(axis=0)
    order_ = np.argsort(diff)[::-1][:5]
    print("column seams (col -> col+1, mean |diff|):",
          ", ".join("%d->%d: %.1f" % (c, c + 1, diff[c]) for c in order_),
          "| typical %.1f" % np.median(diff))
    # Row-wrap test: does the end of row r continue into the start of row r+1 better than into its own start?
    wrap = np.abs(img[:-1, -1] - img[1:, 0]).mean()
    same = np.abs(img[:, -1] - img[:, 0]).mean()
    print("row end -> next row start: %.1f | row end -> own row start: %.1f" % (wrap, same))
    return img


def save_png(img, name):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError:
        print("(matplotlib not installed: no PNG)")
        return
    plt.figure(figsize=(8, 6))
    plt.imshow(img / 10.0 - 273.15, cmap="inferno", interpolation="nearest")
    plt.colorbar(label="C")
    plt.savefig(name, dpi=100)
    plt.close()
    print("saved", name)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="/dev/ttyUSB1")
    ap.add_argument("--baud", type=int, default=921600)
    ap.add_argument("--frames", type=int, default=3)
    ap.add_argument("--save", help="save frames as <name>_<n>.bin (flags byte + raw words) and PNGs")
    ap.add_argument("--file", help="analyse a saved .bin instead of reading the port")
    args = ap.parse_args()

    if args.file:
        raw = open(args.file, "rb").read()
        analyse(np.frombuffer(raw[1:], dtype=">u2").astype(np.int64), raw[0])
        return

    port = open_port(args.port, args.baud)
    packets = []
    for n in range(args.frames):
        port.reset_input_buffer()       # start from a fresh packet; nothing slow runs while reading
        pkt = read_packet(port)
        if pkt is None:
            sys.exit("timeout: no packet. Is the board programmed, and is %s the Basys 3 UART port (try ttyUSB0)?" % args.port)
        packets.append(pkt)

    for n, (flags, words) in enumerate(packets):
        print("\n=== frame %d ===" % n)
        img = analyse(words, flags)
        if args.save:
            open("%s_%d.bin" % (args.save, n), "wb").write(bytes([flags]) + words.astype(">u2").tobytes())
            save_png(img, "%s_%d.png" % (args.save, n))


if __name__ == "__main__":
    main()
