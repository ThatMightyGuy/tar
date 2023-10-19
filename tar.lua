-- Tar extraction module based off LUARocks : github.com/keplerproject/luarocks
-- By Danny @ anscamobile
--
-- Restored directory creation
-- Handles space-padded numbers, e.g. in the size field, so it can handle a TAR file
-- created by the OS X UNIX tar.
--
-- By David Gross

-- Sample code is MIT licensed -- Copyright (C) 2011 InfusedDreams. All Rights Reserved.

-- Lua File System 
-- (nevermind, that's OpenOS Filesystem API): https://ocdoc.cil.li/api:filesystem
local fs = require("filesystem")
local shell = require("shell")

local tar = {}

local blocksize = 512

-- trim5 from http://lua-users.org/wiki/StringTrim
local function trim(str)
  return str:match'^%s*(.*%S)' or ''
end

local hlens = {
	name = 100,
	mode = 8,
	uid = 8,
	gid = 8,
	size = 12,
	mtime = 12,
	chksum = 8,
	typeflag = 1;
	linkname = 100,
	magic = 6,
	version = 2,
	uname = 32,
	gname = 32,
	devmajor = 8,
	devminor = 8,
	prefix = 155,
	filler = 12
}

-- Pads the string to the right.
-- Why? Maximum width of string.format is only 99 characters:
-- https://www.reddit.com/r/lua/comments/vegc9u/stringformat_has_a_maximum_field_width_or/
local function right_pad(str, char, len)
	str = tostring(str)
	return str..char:rep(len - #str)
end

-- Pads the string to the left.
-- Why? Maximum width of string.format is only 99 characters:
-- https://www.reddit.com/r/lua/comments/vegc9u/stringformat_has_a_maximum_field_width_or/
local function left_pad(str, char, len)
	str = tostring(str)
	return char:rep(len - #str)..str
end

-- Sets the last char of a string to space (20h)
local function space(str)
	str = str:sub(1, -2)
	str = str.." "
	return str
end

-- Sets the last two chars of a string to 20 00
local function space_term(str)
	str = str:sub(1, -3)
	str = str.." \0"
	return str
end

local function get_typeflag(flag)
	if flag == "0" or flag == "\0" then return "file"
	elseif flag == "1" then return "link"
	elseif flag == "2" then return "symlink" -- "reserved" in POSIX, "symlink" in GNU
	elseif flag == "3" then return "character"
	elseif flag == "4" then return "block"
	elseif flag == "5" then return "directory"
	elseif flag == "6" then return "fifo"
	elseif flag == "7" then return "contiguous" -- "reserved" in POSIX, "contiguous" in GNU
	elseif flag == "x" then return "next file"
	elseif flag == "g" then return "global extended header"
	elseif flag == "L" then return "long name"
	elseif flag == "K" then return "long link name"
	end
	return nil
end

local function octal_to_number(octal)
	local exp = 0
	local number = 0
	octal = trim(octal)
	for i = #octal,1,-1 do
		local digit = tonumber(octal:sub(i,i))
		if not digit then break end
		number = number + (digit * 8^exp)
		exp = exp + 1
	end
	return number
end

--[[
It is correct that the checksum is the sum of the 512 header
bytes after filling the checksum field itself with spaces.
The checksum is then written as a string giving the *octal*
representation of the checksum. Maybe you forgot to convert
your hand computed sum to octal ??.
]]

-- I have no idea what this is about. Contributor left a message? David Gross himself? Doesn't matter.

local function checksum_header(block)
	local sum = 256
	for i = 1,148 do
		sum = sum + block:byte(i)
	end
	for i = 157,500 do
		sum = sum + block:byte(i)
	end
	return sum
end

local function nullterm(s)
	return s:match("^[^%z]*")
end

local function read_header_block(block)
	local header = {}
	header.name = nullterm(block:sub(1,100))
	header.mode = nullterm(block:sub(101,108))
	header.uid = octal_to_number(nullterm(block:sub(109,116)))
	header.gid = octal_to_number(nullterm(block:sub(117,124)))
	header.size = octal_to_number(nullterm(block:sub(125,136)))
	header.mtime = octal_to_number(nullterm(block:sub(137,148)))
	header.chksum = octal_to_number(nullterm(block:sub(149,156)))
	header.typeflag = get_typeflag(block:sub(157,157))
	header.linkname = nullterm(block:sub(158,257))
	header.magic = block:sub(258,263)
	header.version = block:sub(264,265)
	header.uname = nullterm(block:sub(266,297))
	header.gname = nullterm(block:sub(298,329))
	header.devmajor = octal_to_number(nullterm(block:sub(330,337)))
	header.devminor = octal_to_number(nullterm(block:sub(338,345)))
	header.prefix = block:sub(346,500)
	header.pad = block:sub(501,512)
	if header.magic ~= "ustar " and header.magic ~= "ustar\0" then
		return false, "Invalid header magic "..header.magic
	end
	if header.version ~= "00" and header.version ~= " \0" then
		return false, "Unknown version "..header.version
	end
	if not checksum_header(block) == header.chksum then
		return false, "Failed header checksum"
	end
	return header
end

local function write_header(filename, size, mode, type)
	size = left_pad(string.format("%o", size), "0", hlens.size - 1)
	local header = right_pad(filename, "\0", hlens.name)
	header = header..space_term(right_pad(mode, "\0", 8))
	header = header..space_term(right_pad("000000", "\0", hlens.uid))
	header = header..space_term(right_pad("000000", "\0", hlens.gid))
	header = header..space(right_pad(size, "\0", hlens.size))
	header = header..space(right_pad(left_pad(string.format("%o", os.time()), "0", hlens.mtime - 1), "\0", hlens.mtime))
	header = header..space(right_pad("", " ", hlens.chksum))
	header = header..right_pad(type, "\0", hlens.typeflag)
	header = header..right_pad("", "\0", hlens.linkname)
	header = header..right_pad("ustar", "\0", hlens.magic)
	header = header..right_pad("00", "\0", hlens.version)
	header = header..right_pad("", "\0", hlens.uname)
	header = header..right_pad("", "\0", hlens.gname)
	header = header..space_term(right_pad("000000", "\0", hlens.devmajor))
	header = header..space_term(right_pad("000000", "\0", hlens.devminor))
	header = header..right_pad("", "\0", hlens.prefix + hlens.filler)
	header = header:sub(1, 148)..space(left_pad(string.format("%o", checksum_header(header)).."\0\0", "0", hlens.chksum))..header:sub(157)
	return header
end

function tar.decompress(filePath, destdir, onComplete)
	if onComplete then
		local t = type(onComplete)
		if t ~= "function" then
			return nil, "onComplete: expected function, got "..t
		end
	end

	local destPath = ""

	if not fs.exists(filePath) then
		return nil, "File not found: "..filePath
	end

	destPath = destdir

	local tar_handle = io.open(filePath, "rb")
	if not tar_handle then return nil, "Error opening "..filePath end

	local long_name, long_link_name
	while true do
		local block

		-- Read a header
		repeat
			block = tar_handle:read(blocksize)
		until (not block) or checksum_header(block) > 256
		if not block then break end
		local header, err = read_header_block(block)
		if not header then
			-- Needs testing! Surely we don't want just a false here, or an empty table that
			-- just will crash with a nil when accessed in the next line. How about, for now, we return an error?
			return nil, err
		end

		-- read entire file that follows header
		local file_data = tar_handle:read(math.ceil(header.size / blocksize) * blocksize):sub(1, header.size)

		if header.typeflag == "long name" then
			long_name = nullterm(file_data)
		elseif header.typeflag == "long link name" then
			long_link_name = nullterm(file_data)
		else
			if long_name then
				header.name = long_name
				long_name = nil
			end
			if long_link_name then
				header.name = long_link_name
				long_link_name = nil
			end
		end

		local pathname

		if (false) then
			pathname = destPath.."/"..header.name
		else
			if (destPath and string.sub(destPath,-1) ~= "/") then
				pathname = destPath.."/"..header.name
			else
				pathname = destPath..header.name
			end
		end

		if header.typeflag == "directory" then
			fs.makeDirectory(pathname)
		elseif header.typeflag == "file" then
			local file_handle = io.open(pathname, "wb")
			if not file_handle then return nil, "Error opening file "..pathname end
			file_handle:write(file_data)
			file_handle:close()

		end
	end

	if onComplete then onComplete() end
	return true
end

local function compress_file(src, dest)
	local srcfile = io.open(src, "rb")
	if not srcfile then return nil, "Error opening source file "..src end
	local destfile = io.open(dest, "ab")
	if not destfile then return nil, "Error opening destination file "..dest end

	local fileSize = srcfile:seek("end")
	srcfile:seek("set")
	-- local mode = string.format("%o", 777) -- Set desired permissions
	local header = write_header(src, fileSize, "000666", 0)
	destfile:write(header)

	-- Write file content
	destfile:write(srcfile:read("*a"))

	local paddingBytes = (blocksize - (fileSize % blocksize)) % blocksize
	destfile:write(string.rep("\0", paddingBytes))

	srcfile:close()
	destfile:close()

	return true
end

-- Compresses a file/directory with an optional filter function and a completion callback.
-- Please note that it does not fill a zero block at the end, as it's more work
-- and GNU tar silently ignores it unless a flag is set
function tar.compress(src, dest, filter, onComplete)
	src = shell.resolve(src)
	dest = shell.resolve(dest)

	local function isEligible(file)
		local result = file ~= "." and file ~= ".."
		if filter then result = result and filter() end
		return result
	end

	if onComplete then
		local t = type(onComplete)
		if t ~= "function" then
			return nil, "onComplete: expected function, got "..t
		end
	end
	if fs.exists(dest) then return nil, "Destination file already exists" end
	if not fs.isDirectory(src) then return compress_file(src, dest) end

	local function recursiveCompress(path)
		for file in fs.list(path) do
			if isEligible(file) then
				local filePath = path.."/"..file
				if fs.isDirectory(filePath) then
					recursiveCompress(filePath)
				else
					filePath = path..file
					local status, err = compress_file(filePath, dest)
					if not status then return nil, err end
				end
				if tar.verbose then print(filePath) end
			end
		end
		return true
	end

	local status, err = recursiveCompress(src)
	if not status then return nil, err end

	if onComplete then onComplete() end
	return true
end

return tar
