#!/usr/bin/env python3
"""Check the exact manifest, artwork files and token ABI using only Python's standard library."""

import hashlib
import json
from pathlib import Path
import struct
import zlib


ROOT = Path(__file__).resolve().parents[1]


def check_png(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", f"{path}: not a PNG"
    offset = 8
    chunks = []
    compressed = bytearray()
    header = None
    while offset < len(data):
        size = struct.unpack_from(">I", data, offset)[0]
        kind = data[offset + 4 : offset + 8]
        payload = data[offset + 8 : offset + 8 + size]
        expected_crc = struct.unpack_from(">I", data, offset + 8 + size)[0]
        assert zlib.crc32(kind + payload) & 0xFFFFFFFF == expected_crc, f"{path}: corrupt chunk"
        chunks.append(kind)
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        if kind == b"IDAT":
            compressed.extend(payload)
        offset += 12 + size
    assert chunks[0] == b"IHDR" and chunks[-1] == b"IEND", f"{path}: incomplete PNG"
    assert header == (1024, 1024, 8, 2, 0, 0, 0), f"{path}: expected 1024-square opaque RGB PNG, got {header}"
    assert b"tRNS" not in chunks, f"{path}: transparency is not allowed"
    pixels = zlib.decompress(compressed)
    assert len(pixels) == 1024 * (1024 * 3 + 1), f"{path}: invalid scanlines"
    return hashlib.sha256(data).hexdigest()


def main():
    manifest = json.loads((ROOT / "launch.json").read_text())
    assert set(manifest) == {"kind", "token", "contracts", "pool", "economics", "notes"}
    assert manifest["kind"] == "custom_token"
    assert manifest["token"] == {
        "contract": "TESTToken", "name": "Only test", "symbol": "TEST", "decimals": 18,
        "constructorArgs": [], "totalSupply": "1000000000000000000000000000",
    }
    assert manifest["contracts"] == []
    assert manifest["pool"] == {
        "pairedCurrency": "0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7", "fee": 12500,
        "tickSpacing": 60, "initialPrice": "125270724187523965593206900",
    }
    assert manifest["economics"] == {
        "poolBps": 9000, "initialMarketCapWei": "2500000000000000000000",
        "remainderTo": "0x000000000000000000000000000000000000dead",
    }
    assert isinstance(manifest["notes"], str) and manifest["notes"]

    hashes = [check_png(ROOT / "logos" / f"logo-{n}.png") for n in range(1, 6)]
    assert len(set(hashes)) == 5, "options must be distinct files"
    assert check_png(ROOT / "artifacts/logo.png") == hashes[1], "selected logo must match option 2"

    artifact = json.loads((ROOT / "out/TESTToken.sol/TESTToken.json").read_text())
    names = {entry["name"] for entry in artifact["abi"] if entry["type"] == "function"}
    assert names == {
        "name", "symbol", "decimals", "totalSupply", "balanceOf", "allowance",
        "cumulativeTransferred", "approve", "transfer", "transferFrom",
    }, f"unexpected ABI functions: {names}"
    constructors = [entry for entry in artifact["abi"] if entry["type"] == "constructor"]
    assert len(constructors) == 1 and constructors[0]["inputs"] == []
    assert not artifact["bytecode"].get("linkReferences")
    assert not artifact["deployedBytecode"].get("linkReferences")
    print("PASS: exact launch manifest; five distinct 1024x1024 opaque logos; selected icon; fixed token ABI; no linked libraries")


if __name__ == "__main__":
    main()
