# MCH-NICC

Port of the [ST-NICC](https://demozoo.org/productions/59549/) demo to the [MCH2022 badge](https://badge.team/docs/badges/mch2022/)!

## Running on linux
Requires SDL2

```
make sdl
./sdl data/scene1.bin
```

## Running on the MCH2022
Work in progress!

## Understanding the code
I recommend first reading `data/format.txt`.
That document explains how the bitstream is organized.
I used it to build the linux implementation.
When you understand the layout, `sdl.c` provides the whole implementation in one file.

## Licence
GPL-2 licenced. See LICENCE for more information.
