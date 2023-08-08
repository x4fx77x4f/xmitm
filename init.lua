#!/usr/bin/env luajit
local argparse = require("argparse")
local parser = argparse()
parser:option("--display -d", "Real X server to connect to. Defaults to DISPLAY environment variable.")
parser:option("--fakedisplay -D", "Fake X server to host. Defaults to FAKEDISPLAY environment variable, or \":9\" if not set.")
parser:option("--buffer-size", "Maximum number of bytes to read or write at once.", "1024")
local args = parser:parse()
local socket = require("posix.sys.socket")
local unistd = require("posix.unistd")
local fcntl = require("posix.fcntl")
local errno = require("posix.errno")
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
local buffer_size = assert(tonumber(args.buffer_size))
local outbound = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
assert(socket.connect(outbound, {
	family = socket.AF_UNIX,
	path = "/tmp/.X11-unix/X"..string.match(args.display, ":(%d+)$"),
}))
local outbound_sockaddr = assert(socket.getsockname(outbound))
print(string.format("Connected to real X server on %q via %q at %q", args.display, outbound_sockaddr.family, outbound_sockaddr.path))
local function add_nonblock(fd)
	local flags = assert(fcntl.fcntl(fd, fcntl.F_GETFL))
	flags = bit.bor(flags, fcntl.O_NONBLOCK)
	assert(fcntl.fcntl(fd, fcntl.F_SETFL, flags))
end
add_nonblock(outbound)
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
add_nonblock(inbound)
xpcall(function()
	while true do
		local client, client_sockaddr, err_code = socket.accept(inbound)
		if client ~= nil then
			print(string.format("Client connected via %q", client_sockaddr.family))
			add_nonblock(client)
			while true do
				local data, err, err_code = socket.recv(client, buffer_size)
				if data ~= nil then
					assert(socket.send(outbound, data))
				elseif err_code ~= errno.EAGAIN then
					error(err)
				end
				data, err, err_code = socket.recv(outbound, buffer_size)
				if data ~= nil then
					assert(socket.send(client, data))
				elseif err_code ~= errno.EAGAIN then
					error(err)
				end
			end
			break
		elseif err_code ~= errno.EAGAIN then
			error(client_sockaddr)
		end
	end
end, function(err)
	local err_type = type(err)
	if err_type == "number" then
		err = tostring(err)
	elseif err_type ~= "string" then
		err = "(error object is not a string)"
	end
	err = debug.traceback(err, 2)
	io.stderr:write(err)
	io.stderr:write("\n")
end)
print("Shutting down")
assert(socket.shutdown(outbound, socket.SHUT_RDWR))
assert(socket.shutdown(inbound, socket.SHUT_RDWR))
assert(unistd.close(outbound))
assert(unistd.close(inbound))
