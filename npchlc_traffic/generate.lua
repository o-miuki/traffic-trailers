trailer_connections = {} -- Tabela para rastrear conexões caminhão-trailer
local player_last_squares = {} -- Tabela para rastrear último quadrante de cada jogador

function initTrafficGenerator()
    traffic_density = {peds = 0.10, cars = 0.1, boats = 0.01, planes = 0.01}

    population = {peds = {}, cars = {}, boats = {}, planes = {}}
    element_timers = {}

    players = {}
    for plnum, player in ipairs(getElementsByType("player")) do
        players[player] = true
    end
    addEventHandler("onPlayerJoin", root, addPlayerOnJoin)
    addEventHandler("onPlayerQuit", root, removePlayerOnQuit)

    square_subtable_count = {}

    setTimer(updateTraffic, 1000, 0)
    setTimer(removeFarTrafficElements, 2000, 0) -- Reduzido para 2 segundos
    setTimer(renewTrafficDynamic, 8000, 0) -- Timer para renovação dinâmica
    setTimer(forceReattachTrailers, 3000, 0) -- Timer para re-engate de trailers
end

function addPlayerOnJoin()
    players[source] = true
end

function removePlayerOnQuit()
    local player_key = tostring(source)
    players[source] = nil
    player_last_squares[player_key] = nil
end

function updateTraffic()
    server_coldata = getResourceFromName("server_coldata")
    npc_hlc = getResourceFromName("npc_hlc")

    colcheck = get("npchlc_traffic.check_collisions")
    colcheck = colcheck == "all" and root or colcheck == "local" and resourceRoot or nil

    updateSquarePopulations()
    generateTraffic()
end

function updateSquarePopulations()
    if square_population then
        for dim, square_dim in pairs(square_population) do
            for y, square_row in pairs(square_dim) do
                for x, square in pairs(square_row) do
                    square.count = {peds = 0, cars = 0, boats = 0, planes = 0}
                    square.list = {peds = {}, cars = {}, boats = {}, planes = {}}
                    square.gen_mode = "despawn"
                end
            end
        end
    end

    countPopulationInSquares("peds")
    countPopulationInSquares("cars")
    countPopulationInSquares("boats")
    countPopulationInSquares("planes")

    for player, exists in pairs(players) do
        local px, py, pz = getElementPosition(player)
        local dim = getElementDimension(player)
        local current_x, current_y = math.floor(px/SQUARE_SIZE), math.floor(py/SQUARE_SIZE)
        
        -- Criar chave única para o jogador
        local player_key = tostring(player)
        
        -- Verificar se é a primeira vez ou se mudou significativamente de posição
        local last_square = player_last_squares[player_key]
        local moved_significantly = false
        
        if not last_square then
            -- Primeira vez - forçar spawn em toda área
            moved_significantly = true
            player_last_squares[player_key] = {x = current_x, y = current_y, dim = dim}
        else
            -- Verificar se mudou de quadrante significativamente (mais de 2 quadrantes)
            local distance = math.sqrt((current_x - last_square.x)^2 + (current_y - last_square.y)^2)
            if distance > 2 or last_square.dim ~= dim then
                moved_significantly = true
                player_last_squares[player_key] = {x = current_x, y = current_y, dim = dim}
                
                -- Player moveu significativamente
            end
        end

        -- Área de spawn ao redor do jogador (aumentada para garantir tráfego)
        local spawn_radius = moved_significantly and 16 or 12 -- Radius maior se moveu muito
        
        for sy = current_y - spawn_radius, current_y + spawn_radius do 
            for sx = current_x - spawn_radius, current_x + spawn_radius do
                local square = getPopulationSquare(sx, sy, dim)
                if not square then
                    square = createPopulationSquare(sx, sy, dim, "spawn")
                else
                    square.gen_mode = "spawn"
                end
            end 
        end
        
        -- Área de despawn mais distante
        local despawn_radius = spawn_radius + 4
        for sy = current_y - despawn_radius, current_y + despawn_radius do 
            for sx = current_x - despawn_radius, current_x + despawn_radius do
                local distance_from_player = math.sqrt((sx - current_x)^2 + (sy - current_y)^2)
                if distance_from_player > spawn_radius then
                    local square = getPopulationSquare(sx, sy, dim)
                    if square then
                        square.gen_mode = "despawn"
                    end
                end
            end 
        end
    end

    if colcheck then call(server_coldata, "generateColData", colcheck) end
end

-- Função auxiliar para split string
function split(str, delimiter)
    local result = {}
    local from = 1
    local delim_from, delim_to = string.find(str, delimiter, from)
    while delim_from do
        table.insert(result, string.sub(str, from, delim_from-1))
        from = delim_to + 1
        delim_from, delim_to = string.find(str, delimiter, from)
    end
    table.insert(result, string.sub(str, from))
    return result
end

-- Função de debug para verificar status do tráfego (DESABILITADA)
--[[
function debugTrafficStatus()
    if not square_population then 
        outputDebugString("Nenhum square_population ativo")
        return 
    end
    
    local total_spawn = 0
    local total_despawn = 0
    local total_cars = 0
    local total_peds = 0
    
    for dim, square_dim in pairs(square_population) do
        for y, square_row in pairs(square_dim) do
            for x, square in pairs(square_row) do
                if square.gen_mode == "spawn" then
                    total_spawn = total_spawn + 1
                else
                    total_despawn = total_despawn + 1
                end
                total_cars = total_cars + square.count.cars
                total_peds = total_peds + square.count.peds
            end
        end
    end
    
    outputDebugString("=== STATUS DO TRÁFEGO ===")
    outputDebugString("Quadrantes SPAWN: " .. total_spawn)
    outputDebugString("Quadrantes DESPAWN: " .. total_despawn)
    outputDebugString("Total Carros: " .. total_cars)
    outputDebugString("Total Pedestres: " .. total_peds)
    
    -- Mostrar posição dos jogadores
    for player, _ in pairs(players) do
        local px, py, pz = getElementPosition(player)
        local sx, sy = math.floor(px/SQUARE_SIZE), math.floor(py/SQUARE_SIZE)
        outputDebugString("Player " .. getPlayerName(player) .. " no quadrante (" .. sx .. "," .. sy .. ")")
    end
end
--]]

-- Timer para debug REMOVIDO

function removeFarTrafficElements()
    if not square_population then return end

    local safe_distance = SQUARE_SIZE * 15 -- Distância segura (reduzida de 20 para 15)
    local removed_count = 0

    -- Percorrer todos os veículos
    for vehicle, _ in pairs(population.cars) do
        if isElement(vehicle) then
            local vx, vy, vz = getElementPosition(vehicle)
            local should_remove = true
            local closest_distance = math.huge

            -- Verificar distância para todos os jogadores
            for player, _ in pairs(players) do
                if isElement(player) then
                    local px, py, pz = getElementPosition(player)
                    local distance = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                    
                    if distance < closest_distance then
                        closest_distance = distance
                    end
                    
                    -- Se está muito perto de qualquer jogador, não remover
                    if distance < safe_distance then
                        should_remove = false
                        break
                    end
                end
            end

            -- Se está longe de todos os jogadores, verificar linha de visão apenas do mais próximo
            if should_remove and closest_distance < safe_distance * 2 then -- Só verificar se não está MUITO longe
                for player, _ in pairs(players) do
                    if isElement(player) then
                        local px, py, pz = getElementPosition(player)
                        local distance = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                        
                        if distance == closest_distance then -- Jogador mais próximo
                            -- Verificar se está visível (linha de visão)
                            if isLineOfSightClear(px, py, pz + 1, vx, vy, vz + 1, true, false, false, true, false, true, false) then
                                should_remove = false -- Está visível, não remover
                            end
                            break
                        end
                    end
                end
            end

            -- Remover veículo e ocupantes
            if should_remove then
                local occupants = getVehicleOccupants(vehicle)
                
                -- Remover trailer se existir
                if trailer_connections[vehicle] then
                    local trailer = trailer_connections[vehicle]
                    if isElement(trailer) then
                        destroyElement(trailer)
                    end
                    trailer_connections[vehicle] = nil
                end
                
                destroyElement(vehicle)
                removed_count = removed_count + 1
                
                -- Remover ocupantes
                for seat, ped in pairs(occupants) do
                    if isElement(ped) and population.peds[ped] then
                        destroyElement(ped)
                    end
                end
            end
        end
    end

    -- Percorrer pedestres (apenas os que não estão em veículos)
    for ped, _ in pairs(population.peds) do
        if isElement(ped) and not isPedInVehicle(ped) then
            local px, py, pz = getElementPosition(ped)
            local should_remove = true
            local closest_distance = math.huge

            -- Verificar distância para todos os jogadores
            for player, _ in pairs(players) do
                if isElement(player) then
                    local plx, ply, plz = getElementPosition(player)
                    local distance = getDistanceBetweenPoints3D(plx, ply, plz, px, py, pz)
                    
                    if distance < closest_distance then
                        closest_distance = distance
                    end
                    
                    -- Se está muito perto de qualquer jogador, não remover
                    if distance < safe_distance then
                        should_remove = false
                        break
                    end
                end
            end

            -- Verificar linha de visão apenas se necessário
            if should_remove and closest_distance < safe_distance * 2 then
                for player, _ in pairs(players) do
                    if isElement(player) then
                        local plx, ply, plz = getElementPosition(player)
                        local distance = getDistanceBetweenPoints3D(plx, ply, plz, px, py, pz)
                        
                        if distance == closest_distance then -- Jogador mais próximo
                            if isLineOfSightClear(plx, ply, plz + 1, px, py, pz + 1, true, false, false, true, false, true, false) then
                                should_remove = false -- Está visível, não remover
                            end
                            break
                        end
                    end
                end
            end

            if should_remove then
                destroyElement(ped)
                removed_count = removed_count + 1
            end
        end
    end

    if removed_count > 0 then
        outputDebugString("Remoção individual: " .. removed_count .. " elementos removidos")
    end
end

function countPopulationInSquares(trtype)
    for element, exists in pairs(population[trtype]) do
        if getElementType(element) ~= "ped" or not isPedInVehicle(element) then
            local x, y = getElementPosition(element)
            local dim = getElementDimension(element)
            x, y = math.floor(x/SQUARE_SIZE), math.floor(y/SQUARE_SIZE)

            for sy = y-2, y+2 do for sx = x-2, x+2 do
                local square = getPopulationSquare(sx, sy, dim)
                if sx == x and sy == y then
                    if not square then square = createPopulationSquare(sx, sy, dim, "despawn") end
                    square.list[trtype][element] = true
                end
                if square then square.count[trtype] = square.count[trtype]+1 end
            end end
        end
    end
end

function createPopulationSquare(x, y, dim, genmode)
    if not square_population then
        square_population = {}
        square_subtable_count[square_population] = 0
    end
    local square_dim = square_population[dim]
    if not square_dim then
        square_dim = {}
        square_subtable_count[square_dim] = 0
        square_population[dim] = square_dim
        square_subtable_count[square_population] = square_subtable_count[square_population]+1
    end
    local square_row = square_dim[y]
    if not square_row then
        square_row = {}
        square_subtable_count[square_row] = 0
        square_dim[y] = square_row
        square_subtable_count[square_dim] = square_subtable_count[square_dim]+1
    end
    local square = square_row[x]
    if not square then
        square = {}
        square_subtable_count[square] = 0
        square_row[x] = square
        square_subtable_count[square_row] = square_subtable_count[square_row]+1
    end
    square.count = {peds = 0, cars = 0, boats = 0, planes = 0}
    square.list = {peds = {}, cars = {}, boats = {}, planes = {}}
    square.gen_mode = genmode
    return square
end

function destroyPopulationSquare(x, y, dim)
    if not square_population then return end
    local square_dim = square_population[dim]
    if not square_dim then return end
    local square_row = square_dim[y]
    if not square_row then return end
    local square = square_row[x]
    if not square then return end
    
    square_subtable_count[square] = nil
    square_row[x] = nil
    square_subtable_count[square_row] = square_subtable_count[square_row]-1
    if square_subtable_count[square_row] ~= 0 then return end
    square_subtable_count[square_row] = nil
    square_dim[y] = nil
    square_subtable_count[square_dim] = square_subtable_count[square_dim]-1
    if square_subtable_count[square_dim] ~= 0 then return end
    square_subtable_count[square_dim] = nil
    square_population[dim] = nil
    square_subtable_count[square_population] = square_subtable_count[square_population]-1
    if square_subtable_count[square_population] ~= 0 then return end
    square_subtable_count[square_population] = nil
    square_population = nil
end

function getPopulationSquare(x, y, dim)
    if not square_population then return end
    local square_dim = square_population[dim]
    if not square_dim then return end
    local square_row = square_dim[y]
    if not square_row then return end
    return square_row[x]
end

function generateTraffic()
    if not square_population then return end
    for dim, square_dim in pairs(square_population) do
        for y, square_row in pairs(square_dim) do
            for x, square in pairs(square_row) do
                local genmode = square.gen_mode
                if genmode == "spawn" then
                    spawnTrafficInSquare(x, y, dim, "peds")
                    spawnTrafficInSquare(x, y, dim, "cars")
                    spawnTrafficInSquare(x, y, dim, "boats")
                    spawnTrafficInSquare(x, y, dim, "planes")
                end
            end
        end
    end
end

skins = {0,7,9,10,11,12,13,14,15,16,17,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,43,44,46,47,48,49,50,53,54,55,56,57,58,59,60,61,66,67,68,69,70,71,72,73,76,77,78,79,82,83,84,88,89,91,93,94,95,96,98,100,101,102,103,104,105,106,107,108,109,110,111,112,113,114,115,116,117,118,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,141,142,143,147,148,150,151,153,157,158,159,160,161,162,170,173,174,175,181,182,183,184,185,186,187,188,196,197,198,199,200,201,202,206,210,214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,231,232,233,234,235,236,239,240,241,242,247,248,250,253,254,255,258,259,260,261,262,263}
vehicles = {489, 402, 582, 555, 560, 431, 492, 551, 426, 420, 500, 499, 507, 598, 554, 428, 409, 541, 429, 603, 400, 581, 481, 462, 521, 463, 522, 468, 586, 605, 547, 400, 496, 401, 479, 514, 515}
skincount, vehiclecount = #skins, #vehicles

count_needed = 0

function spawnTrafficInSquare(x, y, dim, trtype)
    local square_tm_id = square_id[y] and square_id[y][x]
    if not square_tm_id then return end
    local square = square_population and square_population[dim] and square_population[dim][y] and square_population[dim][y][x]
    if not square then return end

    local conns = square_conns[square_tm_id][trtype]
    local cpos1 = square_cpos1[square_tm_id][trtype]
    local cpos2 = square_cpos2[square_tm_id][trtype]
    local cdens = square_cdens[square_tm_id][trtype]
    local ttden = square_ttden[square_tm_id][trtype]
    count_needed = count_needed+math.max(ttden*traffic_density[trtype]-square.count[trtype]/25, 0)

    while count_needed >= 1 do
        local sqpos = ttden*math.random()
        local connpos
        local connnum = 1
        while true do
            connpos = cdens[connnum]
            if sqpos > connpos then
                sqpos = sqpos-connpos
            else
                connpos = sqpos/connpos
                break
            end
            connnum = connnum+1
        end

        local connid = conns[connnum]
        connpos = cpos1[connnum]*(1-connpos)+cpos2[connnum]*connpos
        local n1, n2, nb = conn_n1[connid], conn_n2[connid], conn_nb[connid]
        local ll, rl = conn_lanes.left[connid], conn_lanes.right[connid]
        local lanecount = ll+rl
        if lanecount == 0 and math.random(2) > 1 or lanecount ~= 0 and math.random(lanecount) > rl then
            n1, n2, ll, rl = n2, n1, rl, ll
            connpos = (nb and math.pi*0.5 or 1)-connpos
        end
        lane = rl == 0 and 0 or math.random(rl)
        local x, y, z
        local x1, y1, z1 = getNodeConnLanePos(n1, connid, lane, false)
        local x2, y2, z2 = getNodeConnLanePos(n2, connid, lane, true)
        local dx, dy, dz = x2-x1, y2-y1, z2-z1
        local rx = math.deg(math.atan2(dz, math.sqrt(dx*dx+dy*dy)))
        local rz
        if nb then
            local bx, by, bz = node_x[nb], node_y[nb], (z1+z2)*0.5
            local x1, y1, z1 = x1-bx, y1-by, z1-bz
            local x2, y2, z2 = x2-bx, y2-by, z2-bz
            local possin, poscos = math.sin(connpos), math.cos(connpos)
            x = bx+possin*x1+poscos*x2
            y = by+possin*y1+poscos*y2
            z = bz+possin*z1+poscos*z2
            local tx = -poscos
            local ty = possin
            tx, ty = x1*tx+x2*ty, y1*tx+y2*ty
            rz = -math.deg(math.atan2(tx, ty))
        else
            x = x1*(1-connpos)+x2*connpos
            y = y1*(1-connpos)+y2*connpos
            z = z1*(1-connpos)+z2*connpos
            rz = -math.deg(math.atan2(dx, dy))
        end

        local speed = conn_maxspeed[connid]/180
        local vmult = speed/math.sqrt(dx*dx+dy*dy+dz*dz)
        local vx, vy, vz = dx*vmult, dy*vmult, dz*vmult

        local model
        if trtype == "peds" then
            model = skins[math.random(skincount)]
        else
            -- Detectar área urbana ou rural/rodovia baseado na posição
            local world_x, world_y = x, y
            
            -- Los Santos (área urbana) - coordenadas aproximadas
            local is_urban = (world_x > 44 and world_x < 2997 and world_y > -2892 and world_y < -596)
            
            if is_urban then
                -- Área urbana: carros e motos
                local urban_vehicles = {489, 402, 582, 555, 560, 431, 551, 426, 420, 500, 499, 507, 598, 554, 428, 409, 541, 429, 603, 400, 496, 401, 479, 462, 521, 463, 522, 468, 586, 605}
                model = urban_vehicles[math.random(#urban_vehicles)]
            else
                -- Área rural/rodovia: caminhões, tratores, veículos pesados, carros e motos
                local rural_vehicles = {514, 515, 414, 455, 456, 578, 579, 600, 424, 573, 531, 408, 423, 588, 434, 443, 470, 524, 525, 531, 489, 402, 582, 555, 560, 431, 551, 426, 420, 500, 499, 507, 462, 521, 463, 522}
                model = rural_vehicles[math.random(#rural_vehicles)]
            end
        end
        local colx, coly, colz = x, y, z+z_offset[model]

        local create = true
        if colcheck then
            local box = call(server_coldata, "createModelIntersectionBox", model, colx, coly, colz, rz)
            create = not call(server_coldata, "doesModelBoxIntersect", box, dim)
        end

        if create and trtype == "peds" then
            local ped = createPed(model, x, y, z+1, rz)
            setElementDimension(ped, dim)
            element_timers[ped] = {}
            addEventHandler("onElementDestroy", ped, removePedFromListOnDestroy, false)
            addEventHandler("onPedWasted", ped, removeDeadPed, false)
            population.peds[ped] = true

            if colcheck then call(server_coldata, "updateElementColData", ped) end

            call(npc_hlc, "enableHLCForNPC", ped, "walk", 0.99, 40/180)
            ped_lane[ped] = lane
            initPedRouteData(ped)
            addNodeToPedRoute(ped, n1)
            addNodeToPedRoute(ped, n2, nb)
            for nodenum = 1, 4 do addRandomNodeToPedRoute(ped) end

        elseif create and trtype == "cars" then
            local zoff = z_offset[model]/math.cos(math.rad(rx))
            local car = createVehicle(model, x, y, z+zoff, rx, 0, rz)
            setElementDimension(car, dim)
            element_timers[car] = {}
            addEventHandler("onElementDestroy", car, removeCarFromListOnDestroy, false)
            addEventHandler("onVehicleExplode", car, removeDestroyedCar, false)
            population.cars[car] = true

            if colcheck then call(server_coldata, "updateElementColData", car) end

            local ped1 = createPed(skins[math.random(skincount)], x, y, z+1)
            warpPedIntoVehicle(ped1, car)
            setElementDimension(ped1, dim)
            element_timers[ped1] = {}
            addEventHandler("onElementDestroy", ped1, removePedFromListOnDestroy, false)
            addEventHandler("onPedWasted", ped1, removeDeadPed, false)
            population.peds[ped1] = true

            local maxpass = getVehicleMaxPassengers(model)

            if maxpass >= 1 and math.random() < 0.5 then
                local ped2 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped2, car, 1)
                setElementDimension(ped2, dim)
                element_timers[ped2] = {}
                addEventHandler("onElementDestroy", ped2, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped2, removeDeadPed, false)
                population.peds[ped2] = true
            end

            if maxpass >= 2 and math.random() < 0.25 then
                local ped3 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped3, car, 2)
                setElementDimension(ped3, dim)
                element_timers[ped3] = {}
                addEventHandler("onElementDestroy", ped3, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped3, removeDeadPed, false)
                population.peds[ped3] = true
            end

            if maxpass >= 3 and math.random() < 0.25 then
                local ped4 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped4, car, 3)
                setElementDimension(ped4, dim)
                element_timers[ped4] = {}
                addEventHandler("onElementDestroy", ped4, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped4, removeDeadPed, false)
                population.peds[ped4] = true
            end

            -- Sistema de trailer para caminhões
            if (model == 514 or model == 515) and math.random() < 0.3 then -- 30% chance
                local trailers = {435, 450, 584, 590, 591}
                local trailer_model = trailers[math.random(#trailers)]
                
                local trailer = createVehicle(trailer_model, x, y, z+zoff, rx, 0, rz)
                setElementDimension(trailer, dim)
                
                if colcheck then call(server_coldata, "updateElementColData", trailer) end
                
                element_timers[trailer] = {}
                addEventHandler("onElementDestroy", trailer, removeCarFromListOnDestroy, false)
                addEventHandler("onVehicleExplode", trailer, removeDestroyedCar, false)
                population.cars[trailer] = true
                
                -- Salvar conexão
                trailer_connections[car] = trailer
                
                -- Engatar trailer
                setTimer(function()
                    if isElement(car) and isElement(trailer) then
                        local success = attachTrailerToVehicle(car, trailer)
                        if success then
                            -- Iniciar monitoramento após delay
                            setTimer(function()
                                if isElement(car) and isElement(trailer) then
                                    startTrailerMonitoring(car, trailer)
                                end
                            end, 2000, 1)
                        end
                    end
                end, 500, 1)
            end

            setElementVelocity(car, vx, vy, vz)

            call(npc_hlc, "enableHLCForNPC", ped1, "walk", 0.99, speed)
            ped_lane[ped1] = lane
            initPedRouteData(ped1)
            addNodeToPedRoute(ped1, n1)
            addNodeToPedRoute(ped1, n2, nb)
            for nodenum = 1, 4 do addRandomNodeToPedRoute(ped1) end
        end

        square.count[trtype] = square.count[trtype]+1

        count_needed = count_needed-1
    end
end

function removePedFromListOnDestroy()
    for timer, exists in pairs(element_timers[source]) do
        killTimer(timer)
    end
    element_timers[source] = nil
    population.peds[source] = nil
end

function removeDeadPed()
    element_timers[source][setTimer(destroyElement, 20000, 1, source)] = true
end

function removeCarFromListOnDestroy()
    -- Limpar conexões de trailer
    if trailer_connections[source] then
        trailer_connections[source] = nil
    end
    
    -- Limpar timers
    if element_timers[source] then
        for timer, exists in pairs(element_timers[source]) do
            if isTimer(timer) then
                killTimer(timer)
            end
        end
        element_timers[source] = nil
    end
    population.cars[source] = nil
end

function removeDestroyedCar()
    element_timers[source][setTimer(destroyElement, 60000, 1, source)] = true
end

function despawnTrafficInSquare(x, y, dim, trtype)
    local square = square_population and square_population[dim] and square_population[dim][y] and square_population[dim][y][x]
    if not square then return end

    if trtype == "peds" then
        for element, exists in pairs(square.list[trtype]) do
            destroyElement(element)
        end
    else
        for element, exists in pairs(square.list[trtype]) do
            local occupants = getVehicleOccupants(element)
            local destroy = true
            for seat, ped in pairs(occupants) do
                if not population.peds[ped] then destroy = false end
            end
            if destroy then
                destroyElement(element)
                for seat, ped in pairs(occupants) do
                    destroyElement(ped)
                end
            end
        end
    end
end

-- Sistema de monitoramento e re-engate de trailers
function startTrailerMonitoring(truck, trailer)
    if not isElement(truck) or not isElement(trailer) then return end
    
    local monitor_timer = setTimer(function()
        if isElement(truck) and isElement(trailer) then
            local attached_trailer = getVehicleTowedByVehicle(truck)
            
            -- Se não há trailer engatado
            if not attached_trailer then
                local truck_x, truck_y, truck_z = getElementPosition(truck)
                local trailer_x, trailer_y, trailer_z = getElementPosition(trailer)
                local distance = getDistanceBetweenPoints3D(truck_x, truck_y, truck_z, trailer_x, trailer_y, trailer_z)
                
                -- Distância aumentada e sem verificação de velocidade
                if distance < 30 then
                    local success = attachTrailerToVehicle(truck, trailer)
                    if success then
                        outputDebugString("Trailer re-engatado automaticamente! Distância: " .. math.floor(distance) .. "m")
                    end
                end
            end
        else
            -- Elementos destruídos, parar monitoramento
            killTimer(monitor_timer)
            if trailer_connections[truck] then
                trailer_connections[truck] = nil
            end
        end
    end, 1000, 0) -- Mudou de 500ms para 1000ms para menos processamento
    
    if not element_timers[truck] then element_timers[truck] = {} end
    element_timers[truck][monitor_timer] = true
end

function forceReattachTrailers()
    local reattached_count = 0
    for truck, trailer in pairs(trailer_connections) do
        if isElement(truck) and isElement(trailer) then
            local attached = getVehicleTowedByVehicle(truck)
            if not attached then
                local truck_x, truck_y, truck_z = getElementPosition(truck)
                local trailer_x, trailer_y, trailer_z = getElementPosition(trailer)
                local distance = getDistanceBetweenPoints3D(truck_x, truck_y, truck_z, trailer_x, trailer_y, trailer_z)
                
                if distance < 35 then -- Distância aumentada para 35m
                    local success = attachTrailerToVehicle(truck, trailer)
                    if success then
                        reattached_count = reattached_count + 1
                    end
                end
            end
        else
            trailer_connections[truck] = nil
        end
    end
    
    if reattached_count > 0 then
        outputDebugString("Força re-engate: " .. reattached_count .. " trailers reengatados")
    end
end

-- NOVA FUNÇÃO: Renovação dinâmica do tráfego
function renewTrafficDynamic()
    if not square_population then return end
    
    local renewal_count = 0
    for dim, square_dim in pairs(square_population) do
        for y, square_row in pairs(square_dim) do
            for x, square in pairs(square_row) do
                if square.gen_mode == "spawn" and math.random() < 0.02 then -- 2% chance por quadrante
                    -- Remove 1 veículo aleatório para renovar o tráfego
                    for vehicle, _ in pairs(square.list.cars) do
                        if math.random() < 0.1 then -- 10% chance de remover este veículo
                            if isElement(vehicle) then
                                local occupants = getVehicleOccupants(vehicle)
                                destroyElement(vehicle)
                                for seat, ped in pairs(occupants) do
                                    if isElement(ped) then
                                        destroyElement(ped)
                                    end
                                end
                                renewal_count = renewal_count + 1
                                break -- Remove apenas 1 por quadrante
                            end
                        end
                    end
                end
                
                -- Renovar pedestres ocasionalmente
                if square.gen_mode == "spawn" and math.random() < 0.015 then -- 1.5% chance
                    for ped, _ in pairs(square.list.peds) do
                        if not isPedInVehicle(ped) and math.random() < 0.08 then -- 8% chance
                            if isElement(ped) then
                                destroyElement(ped)
                                renewal_count = renewal_count + 1
                                break -- Remove apenas 1 por quadrante
                            end
                        end
                    end
                end
            end
        end
    end
    
    if renewal_count > 0 then
        outputDebugString("Tráfego renovado: " .. renewal_count .. " elementos removidos para renovação")
    end
end