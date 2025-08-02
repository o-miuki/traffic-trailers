timeData = {}

local refreshInterval = 10 -- minutes
local loadedPlayers = {}

setElementCallPropagationEnabled( resourceRoot, false )

do
	--[[

        Prepare the server time so that it is ready to use

    ]]
	addEvent( "onServerTimeAvailable" )

	local prepareTimeData = {}
	local function findTimeStampIncrementPoint()
		local timestamp = getRealTime().timestamp
		if timestamp ~= prepareTimeData.lastTimeStamp then
			timeData.serverTime = timestamp * 1000
			timeData.tickCount = getTickCount()
			triggerClientEvent( loadedPlayers, "onServerTimeUpdate", resourceRoot, timeData.serverTime )
			if not timeData.available then
				triggerEvent( "onServerTimeAvailable", resourceRoot, timeData.serverTime )
				timeData.available = true
			end
			if isTimer( prepareTimeData.checkTimer ) then killTimer( prepareTimeData.checkTimer ) end
		end
	end

	local function prepareTime()
		local timestamp = getRealTime().timestamp
		prepareTimeData.lastTimeStamp = timestamp
		prepareTimeData.checkTimer = setTimer( findTimeStampIncrementPoint, 30, 30 )
	end

	local function refreshTime()
		local timeNow = getTickCount()
		timeData.serverTime = timeData.serverTime + (timeNow - timeData.tickCount)
		timeData.tickCount = timeNow
		triggerClientEvent( loadedPlayers, "onServerTimeUpdate", resourceRoot, timeData.serverTime )
	end

	addEventHandler( "onResourceStart", resourceRoot, function()
		prepareTime()
		setTimer( refreshTime, 1000 * 60 * refreshInterval, 0 )
	end, false )
end

addEventHandler( "onPlayerResourceStart", root, function( loadedResource )
	if getResourceRootElement( loadedResource ) == resourceRoot then
		loadedPlayers[#loadedPlayers + 1] = source
		if timeData.available then
			triggerClientEvent( source, "onServerTimeUpdate", resourceRoot, timeData.serverTime + (getTickCount() - timeData.tickCount) )
		end
	end
end )

addEventHandler( "onPlayerQuit", root, function()
	for i = 1, #loadedPlayers do
		if loadedPlayers[i] == source then
			table.remove( loadedPlayers, i )
			break
		end
	end
end )

