timeData = {}

addEvent( "onServerTimeInitialized" )
addEvent( "onServerTimeUpdate", true )
addEventHandler( "onServerTimeUpdate", resourceRoot, function( serverTime )
	if debugMode and timeData.serverTime then
		iprint( "server time:", timeData.serverTime, "Time desync:", serverTime - (timeData.serverTime + (getTickCount() - timeData.tickCount)) )
	end
	timeData.serverTime = serverTime
	timeData.tickCount = getTickCount()
	if not timeData.available then
		timeData.available = true
		triggerEvent( "onServerTimeInitialized", resourceRoot, serverTime )

	end

end, false )

