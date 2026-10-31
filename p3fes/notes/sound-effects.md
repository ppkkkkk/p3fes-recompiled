# Sound effects: investigation notes

Menu and field sound effects are played by Sony's Sound Kit: EE `sceSkSs*` calls (h_maestro_*) go through libsdr
(`sceSdRemote`) as SIF RPCs to SDRDRV.IRX (sid 0x80000701, user command 0x90F0), which hands them to SKSOUND, and
from there to SKHSYNTH/MODHSYN (synthesizer) and SKSESQ/MODSESQ (sound-effect sequencer). Music and voices use a
separate path (CRI ADX: CRI_ADXI.IRX with its own RPC server 0x90000200 and DTX transfers).

## Done
- libsdr (`sceSdRemoteInit`, `sceSdRemote`, `sceSdTransToIOP`) runs as guest code (p3fes.toml `keep_guest`); the HLE
  stubs answered locally and nothing reached the IOP.
- IOP `sceSifBindRpc` to an EE server marks the client bound (SDRDRV's callback thread spun on it forever).
- RPC settling only runs threads that preempt the server's thread.

## Current state
- The SK commands reach the IOP every frame. Each menu cursor move produces two SK commands that fail:
  `[04000000, 2, 0, 2]` returns -0x130 and `[04000000, 3, 0, 1]` returns -0x12B (SKSESQ.IRX, from MODSESQ
  export 9 at 0x1E20 and exports 10 to 12, which return -1).
- Cause found so far: in the SKSESQ object (module base + 0x1A20) the sequence-set table has data for sets 0 and 1
  (pointers into the 0xF6F80 / 0xF7EC0 region, which holds `SCEIVers`/`SCEISequ` data) but the per-set "sequences
  present" mask (state block + 0x50 + 0x14) is 0 for every set, so every play request is rejected. Sets 2 and 3 have
  no data at all.
- The .sq / .hd banks are DMA'd to other IOP addresses (0x0E9F40, 10336 bytes and 0x0EC7C0, 42944 bytes), and the
  .bd sample data is streamed in 4 KB chunks through 0xF6F80 and uploaded to SPU2 RAM (command 0xA). So the set data
  pointers may point at the transfer buffer instead of the .sq: check how h_maestro_0010cdd0 attaches the banks and
  which IOP addresses it passes.
- No SPU2 key-on after boot (`PS2X_SPU2_DIAG=1`).

## Tools
- `PS2X_RPC_LOG=1` (RPC words), `PS2X_IOP_TRACE=<n>` + `PS2X_IOP_TRACE_NOCLIB=1` (IOP import calls with arguments),
  `PS2X_RAM_DUMP=<field>:<path>` (EE RAM, and IOP RAM to `<path>.iop`), `PS2X_SIFDMA_LOG=1` / `PS2X_SIFDMA_DUMP=<addr>`.
- Module load order and bases: see `[IOP] loaded IRX` lines (SKSESQ is id 15).

## Packets seen (PS2X_RPC_LOG, 8 words)
SDR user command 0x90F0; word 0 = module (0x01000000 HSYNTH, 0x04000000 SESQ), word 1 = command, then arguments.
- `[01000000,0,3,-1,0x0E9F40,0x2860,0x5010,0x08C180]`: HSYNTH bind, .hd at IOP 0x0E9F40 (10336 bytes), samples at
  SPU2 address 0x08C180. A second one binds the .hd at 0x0EC7C0.
- `[04000000,0,0,-1,0x0F6F80,0x0F40]` and `[04000000,0,0,-1,0x0F7EC0,0x2DE0]`: SESQ data for sets 0 and 1 (the .sq);
  `[04000000,0,5,set,set,0x00782C00]` follows each (0x782C00 is the EE packet buffer).
- Per menu move: `[04000000,3,0,1,0xA,..]` (status, -0x12B), `[04000000,2,0,2,0xA,n,0x40]` (control, -0x130),
  `[04000000,2,0,0,0xA,..]` (returns a counter).
- IOP side: SKSESQ calls MODSESQ export 6 for the set bind with a3 = 0x782C00, export 7 then export 9 (play, mode
  0x101) for each request; export 9 fails because the set's "sequences present" mask is 0.
- IOP heap: 0x0F6F80 is first a 4 KB transfer buffer (allocated and freed twice), then allocated for the set-0 .sq
  (3904 bytes); 4 KB sample chunks are still DMA'd to 0x0F6F80 afterwards without a new allocation, overwriting it.
  Next: check whether MODSESQ export 6 is meant to read the set data through a3, and where the "present" mask is
  computed.
