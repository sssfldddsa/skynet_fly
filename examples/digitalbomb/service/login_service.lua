local skynet = require "skynet"
require "skynet.manager"
local timer = require "timer"
local log = require "log"
local queue = require "skynet.queue"
local contriner_client = require "contriner_client"
local assert = assert
local x_pcall = x_pcall

local gate
local check_plug = nil

local g_fd_agent_map = {}
local g_player_map = {}
local g_login_lock_map = {}

local function close_fd(fd)
	skynet.send(gate,'lua','kick',fd)
end

local CMD = {}

function CMD.goout(player_id)
	assert(g_player_map[player_id])

	g_player_map[player_id] = nil
	check_plug.login_out(player_id)
end

local SOCKET = {}

function SOCKET.open(fd, addr)
	local agent = {
		fd = fd,
		addr = addr,
		queue = queue(),
		login_time_out = timer:new(check_plug.time_out,1,close_fd,fd)
	}
	g_fd_agent_map[fd] = agent
	skynet.send(gate,'lua','forward',fd)
end

function SOCKET.close(fd)
	local agent = g_fd_agent_map[fd]
	if not agent then
		log.warn("close not agent ",fd)
		return
	end

	agent.fd = 0
	g_fd_agent_map[fd] = nil
	agent.login_time_out:cancel()

	local player_id = agent.player_id
	local player = g_player_map[player_id]
	if player then
		local hall_client = player.hall_client
		hall_client:mod_send('disconnect',fd,player_id)
		check_plug.disconnect(fd,player_id)
	end
end

function SOCKET.error(fd, msg)
	local agent = g_fd_agent_map[fd]
	if not agent then
		log.warn("error not agent ",fd)
		return
	end

	close_fd(fd)
end

function SOCKET.warning(fd, size)
	log.info('SOCKET.warning:',fd,size)
end

function SOCKET.data(msg)
	log.info('SOCKET.data:',msg)
end

function CMD.socket(cmd,...)
	assert(SOCKET[cmd],'not cmd '.. cmd)
	local f = SOCKET[cmd]
	f(...)
end

local function connect_hall(fd,player_id)
	local old_agent = g_player_map[player_id]
	local hall_client = nil
	if old_agent then
		hall_client = old_agent.hall_client
		check_plug.repeat_login(old_agent.fd,player_id)
		close_fd(old_agent.fd)
	else
		hall_client = contriner_client:new("hall_m",nil,function() return false end)
		hall_client:set_mod_num(player_id)
	end
	
	local ret,errcode,errmsg = hall_client:mod_call("connect",fd,player_id,gate)
	if not ret then
		check_plug.login_failed(fd,player_id,errcode,errmsg)
		return
	end

	g_player_map[player_id] = {
		player_id = player_id,
		hall_client = hall_client,
		fd = fd,
	}

	check_plug.login_succ(fd,player_id,ret)
	return true
end

local function check_func(fd,...)
	local player_id,errcode,errmsg = check_plug.check(fd,...)
	if not player_id then
		check_plug.login_failed(fd,player_id,errcode,errmsg)
		return
	end

	if g_login_lock_map[player_id] then
		--正在登入中
		check_plug.logining(fd,player_id)
		return
	end
	
	g_login_lock_map[player_id] = true
	local isok,err = x_pcall(connect_hall,fd,player_id)
	g_login_lock_map[player_id] = nil
	if not isok then
		log.fatal("connect_hall failed ",err)
		return
	end
	
	return player_id
end

skynet.start(function()
	skynet.dispatch('lua',function(session,source,cmd,...)
		local f = CMD[cmd]
		assert(f,'cmd no found :'..cmd)
	
		if session == 0 then
			f(...)
		else
			skynet.retpack(f(...))
		end
	end)

	local confclient = contriner_client:new("share_config_m")
	local loginconf = confclient:mod_call('query','loginconf')
	assert(loginconf.gateconf,"not gateconf")
	assert(loginconf.check_plug,"not check_plug")

	check_plug = require (loginconf.check_plug)
	assert(check_plug.init,"check_plug not init")				   --初始化
	assert(check_plug.unpack,"check_plug not unpack")              --解包函数
	assert(check_plug.check,"check_plug not check")				   --登录检查
	assert(check_plug.login_succ,"check_plug not login_succ")	   --登录成功
	assert(check_plug.login_failed,"check_plug not login_failed")  --登录失败
	assert(check_plug.disconnect,"check_plug not disconnect")      --掉线
	assert(check_plug.login_out,"check_plug not login_out")        --登出
	assert(check_plug.time_out,"check_plug not time_out")		   --登录超时时间
	
	assert(check_plug.logining,"check_plug not logining")          --正在登录中
	assert(check_plug.repeat_login,"check_plug not repeat_login")  --重复登录

	skynet.register_protocol {
		id = skynet.PTYPE_CLIENT,
		name = "client",
		unpack = check_plug.unpack,
		dispatch = function(fd,source,...)
			skynet.ignoreret()
			local agent = g_fd_agent_map[fd]
			if not agent then
				log.info("dispatch not agent ",fd)
				return
			end

			--避免重复登录，登录成功之后把消息转发到agent那边去，这里只处理登录
			if agent.is_login then
				log.info("repeat login ",fd)
				return
			end
			
			local player_id = agent.queue(check_func,fd,...)
			if not player_id then
				close_fd(fd)
			else
				agent.login_time_out:cancel()
				agent.player_id = player_id
				agent.is_login = true
			end
		end,
	}

	gate = skynet.newservice('gate')
	check_plug.init()
	skynet.call(gate,'lua','open',loginconf.gateconf)	
	skynet.register('.login')
end)