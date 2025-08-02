--[[
	Speed up the API
]] --
local getTickCount = getTickCount
local timeData = timeData

function getServerTime()
	if not timeData.available then return false end
	return timeData.serverTime + (getTickCount() - timeData.tickCount)
end

--[[

    -- Usage
	local timeNow = exports.servertimesync:getServerTime()
	if timeNow then
        
        -- Remove days
		timeNow = timeNow % (1000 * 60 * 60 * 24) 

		local hours = math.floor( timeNow / (1000 * 60 * 60) )
		local minutes = math.floor( (timeNow - (hours * (1000 * 60 * 60))) / (1000 * 60) )
		setTime( hours, minutes )
	end

]]

debugMode = false
