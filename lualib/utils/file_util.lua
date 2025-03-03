local lfs = require "lfs"
local string_util = require "string_util"

local string = string
local tinsert = table.insert
local tremove = table.remove
local assert = assert
local tostring = tostring
local io = io

local M = {}

--递归遍历目录
function M.diripairs(path_url)
	local stack = {}
	
	local function push_stack(path)
		local next,meta1,meta2 = lfs.dir(path)
		tinsert(stack,{
			path = path,
			next = next,
			meta1 = meta1,
			meta2 = meta2,
		})
	end

	local root_info = lfs.attributes(path_url)
	if root_info and root_info.mode == 'directory' then
		push_stack(path_url)
	end

	return function() 
		while #stack > 0 do
			local cur = stack[#stack]
			local file_name = cur.next(cur.meta1,cur.meta2)
			if file_name == '..' or file_name == '.' then
			elseif file_name then
				local file_path = cur.path .. '/' .. file_name
				local file_info = lfs.attributes(file_path)
				if file_info.mode == 'directory' then
					push_stack(file_path)
				end
				return file_name,file_path,file_info
			else
				tremove(stack,#stack)
			end
		end
		return nil,nil,nil
	end
end

--创建 lua文件 查找规则，优先级 server下非service文件夹 > server上上级目录common文件夹非service文件夹 > skynet_fly lualib下所有文件夹 > skynet lualib下所以文件夹
function M.create_luapath(skynet_fly_path)
	local server_path = './'
	local skynet_path = skynet_fly_path .. '/skynet'
	local common_path = '../../common/'

	--server下非service文件夹
	local lua_path = server_path .. '?.lua;'
	for file_name,file_path,file_info in M.diripairs(server_path) do
		if file_info.mode == 'directory' and file_name ~= 'service' then
			lua_path = lua_path .. file_path .. '/?.lua;'
		end
	end

	--server上上级目录common所有文件夹
	lua_path = lua_path .. common_path .. '?.lua;'
	for file_name,file_path,file_info in M.diripairs(common_path) do
		if file_info.mode == 'directory' and file_name ~= 'service' then
			lua_path = lua_path .. file_path .. '/?.lua;'
		end
	end

	--skynet_fly lualib下所有文件夹
	lua_path = lua_path .. skynet_fly_path .. '/lualib/?.lua;'
	for file_name,file_path,file_info in M.diripairs(skynet_fly_path .. '/lualib') do
		if file_info.mode == 'directory' then
			lua_path = lua_path .. file_path .. '/?.lua;'
		end
	end

	--skynet_fly 3rd下所以文件夹
	for file_name,file_path,file_info in M.diripairs(skynet_fly_path .. '/3rd') do
		if file_info.mode == 'directory' then
			lua_path = lua_path .. file_path .. '/?.lua;'
		end
	end

	--skynet lualib下所以文件夹
	lua_path = lua_path .. skynet_path .. '/lualib/?.lua;'
	for file_name,file_path,file_info in M.diripairs(skynet_path .. '/lualib') do
		if file_info.mode == 'directory' then
			lua_path = lua_path .. file_path .. '/?.lua;'
		end
	end

	return lua_path
end

--打开并读取文件
function M.readallfile(file_path)
	local file = io.open(file_path,'r')
	assert(file,"can`t open file_path " .. tostring(file_path))
	local str = file:read("*all")
	file:close()
	return str
end

--获取当前目录文件夹名称
function M.get_cur_dir_name()
	local curdir = lfs.currentdir()
	local strsplit = string_util.split(curdir,'/')
	return strsplit[#strsplit]
end

function M.path_join(a,b)
    if a:sub(-1) == "/" then
        if b:sub(1, 1) == "/" then
            return a .. b:sub(2)
        end
        return a .. b
    end
    if b:sub(1, 1) == '/' then
        return a .. b
    end
    return string.format("%s/%s", a, b)
end



return M