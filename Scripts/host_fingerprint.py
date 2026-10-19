"""Read-only, independently implemented arm64-code-v1 compatibility fingerprint.

Prints fingerprints; never updates the allowlist or modifies an application.
"""
from pathlib import Path
import hashlib
import json
import struct
import sys

ROOT = Path(__file__).resolve().parents[1]


def fingerprint(data):
    def number(offset, width=4, big=False):
        if offset < 0 or offset + width > len(data):
            raise ValueError('Mach-O bounds')
        return int.from_bytes(data[offset:offset+width], 'big' if big else 'little')
    magic = number(0, big=True)
    if magic in (0xcafebabe, 0xcafebabf):
        count = number(4, big=True)
        stride = 32 if magic == 0xcafebabf else 20
        if not 0 < count <= 16 or 8+count*stride > len(data):
            raise ValueError('Architecture table')
        selected, ranges = [], []
        for i in range(count):
            p = 8+i*stride
            wide = stride == 32
            start = number(p+8, 8 if wide else 4, True)
            size = number(p+(16 if wide else 12), 8 if wide else 4, True)
            align = number(p+(24 if wide else 16), 4, True)
            if (align > 31 or start < 8+count*stride or size < 32 or
                    start+size > len(data) or start % (1 << align) or
                    any(start < b and a < start+size for a, b in ranges)):
                raise ValueError('Architecture range')
            ranges.append((start, start+size))
            if number(p, 4, True) == 0x100000c:
                selected.append(data[start:start+size])
        if len(selected) != 1:
            raise ValueError('Unique arm64 required')
        data = selected[0]
    if number(0) != 0xfeedfacf or number(4) != 0x100000c:
        raise ValueError('arm64 required')
    count, size = number(16), number(20)
    if not 0 < count <= 4096 or size < count*8 or size > len(data)-32:
        raise ValueError('Load table size')
    p, signature, link = 32, None, None
    for _ in range(count):
        command, length = number(p), number(p+4)
        if length < 8 or length % 8 or p+length > 32+size:
            raise ValueError('Load command bounds')
        if command == 0x2c and (length != 24 or number(p+16)):
            raise ValueError('Encrypted')
        if command == 0x1d:
            if length != 16 or signature is not None:
                raise ValueError('Signature command')
            signature = p, number(p+8), number(p+12)
        if command == 0x19:
            if length < 72:
                raise ValueError('Segment command')
            if data[p+8:p+24] == b'__LINKEDIT'+b'\0'*6:
                if link is not None or length != 72 or number(p+64):
                    raise ValueError('LINKEDIT command')
                start, length_bytes, vm = number(p+40, 8), number(p+48, 8), number(p+32, 8)
                if start+length_bytes > len(data) or vm != (length_bytes+16383) & ~16383:
                    raise ValueError('LINKEDIT sizes')
                link = p, start, length_bytes
        p += length
    if p != 32+size or signature is None or link is None:
        raise ValueError('Missing commands')
    sig_command, offset, length_bytes = signature
    link_command, start, link_bytes = link
    if (offset < p or offset < start or not length_bytes or offset+length_bytes != len(data)
            or start+link_bytes != len(data)):
        raise ValueError('Signature must end LINKEDIT')
    result = bytearray(data[:offset])
    struct.pack_into('<I', result, sig_command+12, 0)
    struct.pack_into('<Q', result, link_command+48, offset-start)
    struct.pack_into('<Q', result, link_command+32, (offset-start+16383) & ~16383)
    return hashlib.sha256(result).hexdigest()


if __name__ == '__main__':
    app = Path(sys.argv[1])
    record = json.loads((ROOT/'Compatibility/Pixelmator-4.3.json').read_text())
    print(json.dumps({p: fingerprint((app/p).read_bytes()) for p in record['fileSHA256']}, indent=2))
