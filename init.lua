#!/usr/bin/env luajit
local argparse = require("argparse")
local parser = argparse()
parser:option("--display -d", "Real X server to connect to. Defaults to DISPLAY environment variable.")
parser:option("--fakedisplay -D", "Fake X server to host. Defaults to FAKEDISPLAY environment variable, or \":9\" if not set.")
local args = parser:parse()
local socket = require("posix.sys.socket")
local unistd = require("posix.unistd")
if args.display == nil then
	args.display = os.getenv("DISPLAY")
	assert(args.display ~= nil)
end
assert(string.find(args.display, "^:%d+$") ~= nil)
if args.fakedisplay == nil then
	args.fakedisplay = os.getenv("FAKEDISPLAY")
	if args.fakedisplay == nil then
		args.fakedisplay = ":9"
	end
end
assert(string.find(args.fakedisplay, "^:%d+$") ~= nil)
local outbound = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
assert(socket.connect(outbound, {
	family = socket.AF_UNIX,
	path = "/tmp/.X11-unix/X"..string.match(args.display, ":(%d+)$"),
}))
local outbound_sockaddr = assert(socket.getsockname(outbound))
print(string.format("Connected to real X server on %q via %q at %q", args.display, outbound_sockaddr.family, outbound_sockaddr.path))
local inbound = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
local path = "/tmp/.X11-unix/X"..string.match(args.fakedisplay, ":(%d+)$")
unistd.unlink(path)
assert(socket.bind(inbound, {
	family = socket.AF_UNIX,
	path = path,
}))
assert(socket.listen(inbound, 1))
--assert(socket.accept(inbound))
local inbound_sockaddr = assert(socket.getsockname(inbound))
print(string.format("Hosting fake X server on %q via %q at %q", args.fakedisplay, inbound_sockaddr.family, inbound_sockaddr.path))
assert(socket.shutdown(outbound, socket.SHUT_RDWR))
assert(socket.shutdown(inbound, socket.SHUT_RDWR))
assert(unistd.close(outbound))
assert(unistd.close(inbound))
