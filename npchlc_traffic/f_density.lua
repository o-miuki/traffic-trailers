function setTrafficDensity(trtype,density)
	density = tonumber(density)
	if density then
		density = density*0.01
		if traffic_density[trtype] then
			traffic_density[trtype] = density
			-- ADICIONADO: Forçar atualização imediata do tráfego
			setTimer(function()
				updateTraffic()
				outputChatBox("Densidade de " .. trtype .. " alterada para " .. (density*100) .. "%", root)
			end, 100, 1)
			return true
		end
	else
		density = tonumber(trtype)
		if density then
			density = density*0.01
			for trtype in pairs(traffic_density) do
				traffic_density[trtype] = density
			end
			-- ADICIONADO: Forçar atualização imediata do tráfego
			setTimer(function()
				updateTraffic()
				outputChatBox("Densidade geral alterada para " .. (density*100) .. "%", root)
			end, 100, 1)
			return true
		end
	end
	return false
end

function getTrafficDensity(trtype)
	return trtype and traffic_density[trtype] or false
end

-- ADICIONADO: Função para forçar atualização imediata do tráfego
function forceTrafficUpdate()
    if updateTraffic then
        updateTraffic()
        outputChatBox("Tráfego atualizado manualmente!", root)
    else
        outputChatBox("Sistema de tráfego não inicializado!", root)
    end
end

-- ADICIONADO: Comando para testar atualização manual
addCommandHandler("updatetraffic", forceTrafficUpdate)

-- ADICIONADO: Comando para spawnar tráfego instantaneamente ao redor do player
addCommandHandler("spawntraffic", function(player)
    if not square_id or not spawnTrafficInSquare then
        outputChatBox("Sistema de tráfego não inicializado!", player)
        return
    end
    
    local x, y = getElementPosition(player)
    local dim = getElementDimension(player)
    x, y = math.floor(x/SQUARE_SIZE), math.floor(y/SQUARE_SIZE)
    
    local spawned = 0
    -- Forçar spawn em 3x3 quadrados ao redor do player
    for sy = y-1, y+1 do
        for sx = x-1, x+1 do
            -- Verificar se o square existe
            if square_id[sy] and square_id[sy][sx] then
                spawnTrafficInSquare(sx, sy, dim, "cars")
                spawned = spawned + 1
            end
        end
    end
    
    outputChatBox("Tentativa de spawn em " .. spawned .. " quadrados ao redor!", player)
end)

-- ADICIONADO: Comando para limpar todo o tráfego
addCommandHandler("cleartraffic", function(player)
    local cleared_cars = 0
    local cleared_peds = 0
    
    if population and population.cars then
        for car, exists in pairs(population.cars) do
            if isElement(car) then
                destroyElement(car)
                cleared_cars = cleared_cars + 1
            end
        end
    end
    
    if population and population.peds then
        for ped, exists in pairs(population.peds) do
            if isElement(ped) and not isPedInVehicle(ped) then
                destroyElement(ped)
                cleared_peds = cleared_peds + 1
            end
        end
    end
    
    -- Limpar as tabelas
    if population then
        population.cars = {}
        population.peds = {}
    end
    
    -- Limpar conexões de trailer
    if trailer_connections then
        trailer_connections = {}
    end
    
    outputChatBox("Tráfego limpo! Carros: " .. cleared_cars .. ", Peds: " .. cleared_peds, player)
end)

-- ADICIONADO: Comando para ver status do tráfego
addCommandHandler("trafficstatus", function(player)
    if not traffic_density then
        outputChatBox("Sistema de tráfego não inicializado!", player)
        return
    end
    
    local car_count = 0
    local ped_count = 0
    local trailer_count = 0
    
    if population then
        if population.cars then
            for car, exists in pairs(population.cars) do
                if isElement(car) then
                    car_count = car_count + 1
                end
            end
        end
        
        if population.peds then
            for ped, exists in pairs(population.peds) do
                if isElement(ped) then
                    ped_count = ped_count + 1
                end
            end
        end
    end
    
    if trailer_connections then
        for truck, trailer in pairs(trailer_connections) do
            if isElement(truck) and isElement(trailer) then
                trailer_count = trailer_count + 1
            end
        end
    end
    
    outputChatBox("=== STATUS DO TRÁFEGO ===", player)
    outputChatBox("Carros ativos: " .. car_count, player)
    outputChatBox("Peds ativos: " .. ped_count, player)
    outputChatBox("Trailers engatados: " .. trailer_count, player)
    outputChatBox("Densidade carros: " .. (traffic_density.cars * 100) .. "%", player)
    outputChatBox("Densidade peds: " .. (traffic_density.peds * 100) .. "%", player)
end)