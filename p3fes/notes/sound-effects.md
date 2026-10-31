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
