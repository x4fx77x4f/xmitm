#!/usr/bin/env luajit
local argparse = require("argparse")
local parser = argparse()
parser:option("--display -d", "Real X server to connect to. Defaults to DISPLAY environment variable.")
parser:option("--fakedisplay -D", "Fake X server to host. Defaults to FAKEDISPLAY environment variable, or \":9\" if not set.")
parser:flag("--block-error", "Don't send errors to clients.")
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
local function fprintf(stream, ...)
	stream:write(string.format(...))
end
local function printf(...)
	return fprintf(io.stdout, ...)
end
local function add_nonblock(fd)
	local flags = assert(fcntl.fcntl(fd, fcntl.F_GETFL))
	flags = bit.bor(flags, fcntl.O_NONBLOCK)
	assert(fcntl.fcntl(fd, fcntl.F_SETFL, flags))
end
local inbound = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
local path = "/tmp/.X11-unix/X"..string.match(args.fakedisplay, ":(%d+)$")
unistd.unlink(path)
assert(socket.bind(inbound, {
	family = socket.AF_UNIX,
	path = path,
}))
assert(socket.listen(inbound, 1))
local inbound_sockaddr = assert(socket.getsockname(inbound))
printf("Hosting fake X server on %q via %q at %q\n", args.fakedisplay, inbound_sockaddr.family, inbound_sockaddr.path)
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
	while true do
		local sent, err, err_code = socket.send(fd, data)
		if sent ~= nil then
			assert(sent == #data)
			break
		elseif err_code ~= errno.EAGAIN then
			error(err)
		end
	end
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
local function proxy(inbound, outbound, bytes)
	local data = receive(inbound, bytes)
	send(outbound, data)
	return data
end
local function proxy_card(inbound, outbound, bits)
	return unpack_card(proxy(inbound, outbound, bits/8), bits)
end
local clients = {}
xpcall(function()
	while true do
		local client, client_sockaddr, err_code = socket.accept(inbound)
		if client ~= nil then
			printf("Client connected via %q\n", client_sockaddr.family)
			add_nonblock(client)
			local outbound = assert(socket.socket(socket.AF_UNIX, socket.SOCK_STREAM, 0))
			assert(socket.connect(outbound, {
				family = socket.AF_UNIX,
				path = "/tmp/.X11-unix/X"..string.match(args.display, ":(%d+)$"),
			}))
			local outbound_sockaddr = assert(socket.getsockname(outbound))
			printf("Connected to real X server on %q via %q at %q\n", args.display, outbound_sockaddr.family, outbound_sockaddr.path)
			add_nonblock(outbound)
			local endian = receive(client, 1)
			if endian == "B" then
				little_endian = false
			elseif endian == "l" then
				little_endian = true
			else
				error("bad endian")
			end
			local padding_1 = receive(client, 1)
			local major_raw = receive(client, 2)
			local major = unpack_card(major_raw, 16)
			local minor_raw = receive(client, 2)
			local minor = unpack_card(minor_raw, 16)
			local name_length_raw = receive(client, 2)
			local name_length = unpack_card(name_length_raw, 16)
			local data_length_raw = receive(client, 2)
			local data_length = unpack_card(data_length_raw, 16)
			local padding_2 = receive(client, 2)
			local name = receive(client, name_length)
			local padding_3 = receive(client, pad(name_length))
			local data = receive(client, data_length)
			local padding_4 = receive(client, pad(data_length))
			send(outbound, endian)
			send(outbound, padding_1)
			send(outbound, major_raw)
			send(outbound, minor_raw)
			send(outbound, name_length_raw)
			send(outbound, data_length_raw)
			send(outbound, padding_2)
			send(outbound, name)
			send(outbound, padding_3)
			send(outbound, data)
			send(outbound, padding_4)
			printf("C->S: Connection setup: endian: %q, major: %d, minor: %d, name: %q, data: %q\n", endian, major, minor, name, data)
			local status = receive(outbound, 1)
			send(client, status)
			if status == "\x00" then
				local reason_length_raw = receive(outbound, 1)
				local reason_length = string.byte(reason_length_raw)
				local major_raw = receive(outbound, 2)
				local major = unpack_card(major_raw, 16)
				local minor_raw = receive(outbound, 2)
				local minor = unpack_card(minor_raw, 16)
				local additional_length_raw = receive(outbound, 2)
				local additional_length = unpack_card(additional_length_raw, 16)*4
				local reason = receive(outbound, reason_length)
				local padding_1 = receive(outbound, additional_length*4-reason_length)
				send(client, reason_length_raw)
				send(client, major_raw)
				send(client, minor_raw)
				send(client, additional_length_raw)
				send(client, reason)
				send(client, padding_1)
				printf("S->C: Connection setup failed: major: %d, minor: %d, reason: %q\n", major, minor, reason)
			elseif status == "\x02" then
				local padding_1 = receive(outbound, 5)
				local additional_length_raw = receive(outbound, 2)
				local additional_length = unpack_card(additional_length_raw, 16)
				local additional = receive(outbound, additional_length)
				local reason = string.gsub(additional, "%z+$", "")
				send(client, padding_1)
				send(client, additional_length_raw)
				send(client, additional)
				printf("S->C: Connection setup authenticate: reason: %q\n", reason)
			elseif status == "\x01" then
				proxy(outbound, client, 1)
				local major = proxy_card(outbound, client, 16)
				local minor = proxy_card(outbound, client, 16)
				local additional_length = proxy_card(outbound, client, 16)
				local release_number = proxy_card(outbound, client, 32)
				local resource_id_base = proxy_card(outbound, client, 32)
				local resource_id_mask = proxy_card(outbound, client, 32)
				local motion_buffer_size = proxy_card(outbound, client, 32)
				local vendor_length = proxy_card(outbound, client, 16)
				local maximum_request_length = proxy_card(outbound, client, 16)
				local screen_count = proxy_card(outbound, client, 8)
				local format_count = proxy_card(outbound, client, 8)
				local image_byte_order = proxy_card(outbound, client, 8)
				local bitmap_format_bit_order = proxy_card(outbound, client, 8)
				local bitmap_format_scanline_unit = proxy_card(outbound, client, 8)
				local bitmap_format_scanline_pad = proxy_card(outbound, client, 8)
				local min_keycode = proxy_card(outbound, client, 8)
				local max_keycode = proxy_card(outbound, client, 8)
				proxy(outbound, client, 4)
				local vendor = proxy(outbound, client, vendor_length)
				proxy(outbound, client, pad(vendor_length))
				proxy(outbound, client, 8*format_count)
				-- why is x making me do fucking algebra?
				local m = (additional_length-8-2*format_count)*4-vendor_length-pad(vendor_length)
				assert(m%4 == 0)
				proxy(outbound, client, m)
				printf("S->C: Connection setup success: major: %d, minor: %d, release_number: %d\n", major, minor, release_number)
			else
				printf("S->C: Connection setup unknown 0x%02x\n", string.byte(status))
			end
			local function func()
				local data, err, err_code = socket.recv(client, 1)
				if data ~= nil and #data == 0 then
					printf("C->S: bad data length (expected 1, got %d)\n", #data)
					data, err, err_code = nil, "bad data length", errno.EAGAIN
					return true
				end
				if data ~= nil then
					send(outbound, data)
					local opcode = string.byte(data)
					proxy(client, outbound, 1)
					local request_length_raw = receive(client, 2)
					local request_length = unpack_card(request_length_raw)*4-4
					send(outbound, request_length_raw)
					--print(string.format("%02x %02x", string.byte(request_length_raw, 1, 2)))
					printf("C->S: Request: opcode: %d (0x%02x), request_length: %d\n", opcode, opcode, request_length)
					if request_length < 0 then
						request_length = proxy_card(client, outbound, 32)*4-8
					end
					assert(request_length >= 0)
					proxy(client, outbound, request_length)
				elseif err_code ~= errno.EAGAIN then
					printf("C->S: Receive failure: err: %q, err_code: %d\n", err, err_code)
					return true
				end
				data, err, err_code = socket.recv(outbound, 1)
				if data ~= nil and #data == 0 then
					printf("S->C: bad data length (expected 1, got %d)\n", #data)
					data, err, err_code = nil, "bad data length", errno.EAGAIN
					return true
				end
				if data ~= nil then
					if data == "\x00" then
						local code_raw = receive(outbound, 1)
						local code = string.byte(code_raw)
						printf("S->C: Error: code: %d (0x%02x)\n", code, code)
						local data2 = receive(outbound, 30)
						if not args.block_error then
							send(client, data)
							send(client, code_raw)
							send(client, data2)
						end
					elseif data == "\x01" then
						send(client, data)
						proxy(outbound, client, 3)
						local reply_length = proxy_card(outbound, client, 32)*4
						proxy(outbound, client, 24)
						printf("S->C: Reply: reply_length: %d\n", reply_length)
						proxy(outbound, client, reply_length)
					else
						send(client, data)
						local code = string.byte(data)
						printf("S->C: Event: code: %d (0x%02x)\n", code, code)
						proxy(outbound, client, 31)
					end
				elseif err_code ~= errno.EAGAIN then
					printf("S->C: Receive failure: err: %q, err_code: %d\n", err, err_code)
					return true
				end
				--print(os.time())
			end
			clients[#clients+1] = {
				func = func,
				client = client,
				outbound = outbound,
			}
		elseif err_code ~= errno.EAGAIN then
			error(client_sockaddr)
		end
		local dead = {}
		for i=1, #clients do
			local data = clients[i]
			if data.func() then
				dead[#dead+1] = i
			end
		end
		for i=1, #dead do
			local j = dead[i]
			local data = clients[j]
			printf("Shutting down client\n")
			assert(socket.shutdown(data.client, socket.SHUT_RDWR))
			assert(socket.shutdown(data.outbound, socket.SHUT_RDWR))
			assert(unistd.close(data.client))
			assert(unistd.close(data.outbound))
			table.remove(clients, j)
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
printf("Shutting down\n")
assert(socket.shutdown(inbound, socket.SHUT_RDWR))
assert(unistd.close(inbound))
