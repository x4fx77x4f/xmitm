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
local inbound_sockaddr = assert(socket.getsockname(inbound))
print(string.format("Hosting fake X server on %q via %q at %q", args.fakedisplay, inbound_sockaddr.family, inbound_sockaddr.path))
add_nonblock(inbound)
local little_endian = false
local function unpack_card(data, bits)
	local bytes
	if bits == nil then
		bytes = #data
		bits = bytes*8
	else
		bytes = bits/8
	end
	data = {string.byte(data, 1, bytes)}
	if not little_endian then
		for i=1, bytes/2 do
			local j = bytes-i+1
			data[i], data[j] = data[j], data[i]
		end
	end
	local n = 0
	for i=1, bytes do
		n = bit.bor(n, bit.lshift(data[i], (i-1)*8))
	end
	if n < 0 then
		n = n+2^32
	end
	return n
end
assert(unpack_card("\xa1", 8) == 0xa1)
assert(unpack_card("\xa1\xb2", 16) == 0xa1b2)
assert(unpack_card("\xa1\xb2\xc3\xd4", 32) == 0xa1b2c3d4)
local function receive_string(fd)
	local str, i = {}, 0
	while true do
		local data, err, err_code = socket.recv(fd, 1)
		if data ~= nil then
			assert(#data == 1)
			if data == "\x00" then
				break
			end
			i = i+1
			str[i] = data
		elseif err_code ~= errno.EAGAIN then
			error(err)
		end
	end
	return table.concat(str)
end
local function pack_string(data)
	return data.."\x00"
end
local function send(fd, data)
	if data == "" then
		return
	end
	assert(assert(socket.send(fd, data)) == #data)
end
local function receive(fd, n)
	if n == 0 then
		return ""
	end
	local data, i, length = {}, 0, 0
	while true do
		local fragment, err, err_code = socket.recv(fd, n-length)
		if fragment ~= nil then
			length = length+#fragment
			assert(length <= n)
			i = i+1
			data[i] = fragment
			if length >= n then
				break
			end
		elseif err_code ~= errno.EAGAIN then
			error(err)
		end
	end
	return table.concat(data)
end
local function pad(n)
	return (4-(n%4))%4
end
xpcall(function()
	while true do
		local client, client_sockaddr, err_code = socket.accept(inbound)
		if client ~= nil then
			print(string.format("Client connected via %q", client_sockaddr.family))
			add_nonblock(client)
			local endian = receive(client, 1)
			if endian == "B" then
				little_endian = false
			elseif endian == "l" then
				little_endian = true
			else
				error("bad endian")
			end
			receive(client, 1)
			local major_raw = receive(client, 2)
			local major = unpack_card(major_raw, 16)
			local minor_raw = receive(client, 2)
			local minor = unpack_card(minor_raw, 16)
			local name_length_raw = receive(client, 2)
			local name_length = unpack_card(name_length_raw, 16)
			local data_length_raw = receive(client, 2)
			local data_length = unpack_card(data_length_raw, 16)
			receive(client, 2)
			local name = receive(client, name_length)
			receive(client, pad(name_length))
			local data = receive(client, data_length)
			receive(client, pad(data_length))
			print(string.format("Client sent connection initiation: endian: %q, major: %d, minor: %d, name: %q, data: %q", endian, major, minor, name, data))
			send(outbound, endian)
			send(outbound, "\x00")
			send(outbound, major_raw)
			send(outbound, minor_raw)
			send(outbound, name_length_raw)
			send(outbound, data_length_raw)
			send(outbound, "\x00\x00")
			send(outbound, name)
			send(outbound, string.rep("\x00", pad(name_length)))
			send(outbound, data)
			send(outbound, string.rep("\x00", pad(data_length)))
			print("Sent connection initiation")
			while true do
				local data, err, err_code = socket.recv(client, buffer_size)
				if data ~= nil then
					assert(assert(socket.send(outbound, data)) == #data)
				elseif err_code ~= errno.EAGAIN then
					error(err)
				end
				data, err, err_code = socket.recv(outbound, buffer_size)
				if data ~= nil then
					assert(assert(socket.send(client, data)) == #data)
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
