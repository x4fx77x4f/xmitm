# xmitm
X server proxy written in Lua similar to [xtrace](https://tracker.debian.org/pkg/xtrace).

Can run many applications, but some might not work.

Created with the intention of working around a crash in the [s&box](https://sbox.facepunch.com/about/) editor caused by it sending a ConfigureWindow message with a window ID that is invalid due to a previous call to DestroyWindow. Does successfully prevent the crash, but it's still very broken for reasons likely other than the proxy.

## Usage
1. `git clone https://github.com/x4fx77x4f/xmitm.git xmitm`
2. `cd xmitm`

### General usage
3. `./init.lua --help`
4. `./init.lua` (to run the proxy)
5. `DISPLAY=:9 glxgears` (to run the application)

### s&box editor
3. `./init.lua --block-error-code=3`
4. Add `DISPLAY=:9 ` to the beginning of your launch options (with `%command%` after if you don't already have it)
5. Launch s&box editor

## Extensions
xmitm implements the [Big Requests Extension](https://www.x.org/releases/X11R7.6/doc/bigreqsproto/bigreq.html) allowing for requests that are longer than 262,140 bytes.

xmitm implements the [X Generic Event Extension](https://www.x.org/releases/X11R7.6/doc/xextproto/geproto.html) allowing for events that are longer than 32 bytes.

## License
To the extent possible under law, the author(s) have dedicated all copyright and related and neighboring rights to this software to the public domain worldwide. This software is distributed without any warranty.

A copy of the CC0 legalcode is in [`./COPYING`](./COPYING).
