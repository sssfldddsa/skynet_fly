local skynet = require "skynet"
local SEAT_STATE = require "SEAT_STATE"
local jsonet_util = require "jsonet_util"
local log = require "log"
local setmetatable = setmetatable
local assert = assert

local M = {}

local meta = {__index = M}

function M:new()
	local t = {
		player = nil,
		state = SEAT_STATE.empty,
	}

	setmetatable(t,meta)
	return t
end

function M:enter(player)
	assert(player)
	self.player = player
	self.state = SEAT_STATE.waitting
end

function M:leave()
	self.player = nil
	self.state = SEAT_STATE.empty
end

function M:is_empty()
	return self.state == SEAT_STATE.empty
end

function M:is_can_leave()
	--return self.state ~= SEAT_STATE.playing
	return true
end

function M:send_msg(packname,pack)
	if not self.player then
		return nil
	end

	if self.player.fd > 0 then
		jsonet_util.send(self.player.fd,packname,pack)
	else
		log.info("send_msg not fd ",self.player_id)
	end
end

function M:get_player()
	return self.player
end

function M:game_start()
	self.state = SEAT_STATE.playing
end

function M:game_over()
	self.state = SEAT_STATE.waitting
end

return M