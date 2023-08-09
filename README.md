# xmitm
Work in progress X server proxy written in Lua similar to [xtrace](https://tracker.debian.org/pkg/xtrace).

Can run glxgears and some Wine applications. Most applications exhibit strange behavior and/or crash. Looking for assistance.

Created with the intention of working around a crash in the [s&box](https://sbox.facepunch.com/about/) editor caused by it sending a ConfigureWindow message with a window ID that is invalid due to a previous call to DestroyWindow. Not currently usable for this purpose.

## Usage
1. `git clone https://github.com/x4fx77x4f/xmitm.git xmitm`
2. `cd xmitm`
3. `./init.lua --help`
4. `./init.lua` (to run the proxy)
5. `DISPLAY=:9 glxgears` (to run the application)

## License
To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to this software to the public domain worldwide. This software is distributed without any warranty.

A copy of the CC0 legalcode is in [`./COPYING`](./COPYING).

Attribution is preferred but not required. Commercial use is discouraged but not forbidden.
