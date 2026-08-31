#!/usr/bin/env python3
"""
patch_edid_5994.py

Takes a raw EDID dump and produces a copy where the detailed timing
descriptor (DTD) for a given resolution has its pixel clock scaled by
1000/1001 -- the same "NTSC pulldown" factor that turns 24p into
23.976, 30p into 29.97, and 60p into 59.94.

Everything else (H-total, V-total, sync widths) stays byte-for-byte
identical to what the display already advertises at the whole-number
rate. That matters: it means we're not inventing a new custom timing
that the display, cable, or downstream video gear has never seen --
we're asking for the exact same signal, just 0.1% slower. This is the
same technique used industry-wide to derive broadcast frame rates.

Usage:
    python3 patch_edid_5994.py monitor.bin --list
        Lists every detailed timing found in the EDID (base block +
        any CTA/EIA-861 extension blocks), so you can confirm which
        one is your 3840x2160 mode before patching it.

    python3 patch_edid_5994.py monitor.bin 3840 2160 monitor_59_94.bin
        Patches the 3840x2160 DTD's pixel clock by 1000/1001 and
        writes the result, with a corrected checksum, to the output
        file. That output file is what you feed to the app / to
        force-edid.
"""
import sys

BLOCK_SIZE = 128
DTD_SIZE = 18
BASE_DTD_OFFSETS = [54, 72, 90, 108]
PULLDOWN = 1000 / 1001


def read_dtd(block, offset):
    dtd = block[offset:offset + DTD_SIZE]
    pixel_clock_10khz = dtd[0] | (dtd[1] << 8)
    if pixel_clock_10khz == 0:
        return None  # a 0x0000 pixel clock means this is a display
                     # descriptor (name/serial/range limits), not a DTD
    hactive = dtd[2] | ((dtd[4] >> 4) << 8)
    vactive = dtd[5] | ((dtd[7] >> 4) << 8)
    return {
        "offset": offset,
        "pixel_clock_khz": pixel_clock_10khz * 10,
        "hactive": hactive,
        "vactive": vactive,
    }


def find_dtds(edid):
    found = []
    for off in BASE_DTD_OFFSETS:
        info = read_dtd(edid, off)
        if info:
            found.append(info)

    num_extensions = edid[126]
    for ext_index in range(num_extensions):
        ext_off = BLOCK_SIZE * (1 + ext_index)
        if ext_off + BLOCK_SIZE > len(edid):
            break
        ext = edid[ext_off:ext_off + BLOCK_SIZE]
        if ext[0] != 0x02:  # only CTA/EIA-861 extensions carry DTDs
            continue
        pos = ext[2]  # offset to first DTD within this block
        while pos and pos + DTD_SIZE <= 127:
            info = read_dtd(ext, pos)
            if not info:
                break
            info["offset"] = ext_off + pos
            found.append(info)
            pos += DTD_SIZE
    return found


def patch(edid, offset):
    old_10khz = edid[offset] | (edid[offset + 1] << 8)
    new_10khz = round(old_10khz * PULLDOWN)
    edid[offset] = new_10khz & 0xFF
    edid[offset + 1] = (new_10khz >> 8) & 0xFF

    block_start = (offset // BLOCK_SIZE) * BLOCK_SIZE
    block_end = block_start + BLOCK_SIZE
    edid[block_end - 1] = 0
    edid[block_end - 1] = (256 - sum(edid[block_start:block_end - 1]) % 256) % 256

    return old_10khz * 10 / 1000, new_10khz * 10 / 1000  # (old MHz, new MHz)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    with open(sys.argv[1], "rb") as f:
        edid = bytearray(f.read())

    dtds = find_dtds(edid)

    if "--list" in sys.argv:
        print(f"Found {len(dtds)} detailed timing(s) in {sys.argv[1]}:")
        for d in dtds:
            print(f"  offset {d['offset']:>3}: {d['hactive']}x{d['vactive']}  "
                  f"pixel clock {d['pixel_clock_khz'] / 1000:.2f} MHz")
        return

    if len(sys.argv) < 4:
        print("Usage:")
        print("  patch_edid_5994.py <in.bin> --list")
        print("  patch_edid_5994.py <in.bin> <hactive> <vactive> [out.bin]")
        sys.exit(1)

    hactive, vactive = int(sys.argv[2]), int(sys.argv[3])
    out_path = sys.argv[4] if len(sys.argv) > 4 else "monitor_59_94.bin"

    targets = [d for d in dtds if d["hactive"] == hactive and d["vactive"] == vactive]
    if not targets:
        print(f"No {hactive}x{vactive} detailed timing found in this EDID.")
        print("Run with --list to see what's actually in there.")
        sys.exit(1)

    for d in targets:
        old_mhz, new_mhz = patch(edid, d["offset"])
        print(f"Patched {hactive}x{vactive} @ offset {d['offset']}: "
              f"{old_mhz:.3f} MHz -> {new_mhz:.3f} MHz "
              f"(refresh goes from an even 60 Hz to ~59.94 Hz)")

    with open(out_path, "wb") as f:
        f.write(edid)
    print(f"Wrote {out_path}")


if __name__ == "__main__":
    main()
