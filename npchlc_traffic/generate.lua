trailer_connections = {} -- Tabela para rastrear conexões caminhão-trailer
local player_last_squares = {} -- Tabela para rastrear último quadrante de cada jogador

-- SISTEMA DE IA AVANÇADO
local vehicle_ai = {} -- Dados de IA por veículo
local traffic_sensors = {} -- Sensores de tráfego
local lane_change_cooldown = {} -- Cooldown para mudanças de faixa
local vehicle_behavior = {} -- Comportamento específico por tipo de veículo

-- Configurações de IA
local AI_CONFIG = {
    SENSOR_DISTANCE = 50, -- Distância do sensor frontal
    SIDE_SENSOR_DISTANCE = 15, -- Distância do sensor lateral
    SAFE_FOLLOWING_DISTANCE = 8, -- Distância segura de seguimento
    EMERGENCY_BRAKE_DISTANCE = 4, -- Distância para freada de emergência
    LANE_CHANGE_COOLDOWN = 3000, -- Cooldown entre mudanças de faixa (ms)
    LANE_CHANGE_CHECK_DISTANCE = 25, -- Distância para verificar mudança de faixa
    HEAVY_VEHICLE_MULTIPLIER = 1.5, -- Multiplicador para veículos pesados
    AGGRESSIVE_CHANCE = 0.1, -- 10% chance de comportamento agressivo
    CAUTIOUS_CHANCE = 0.2, -- 20% chance de comportamento cauteloso
}

-- Tipos de veículos por categoria
local VEHICLE_CATEGORIES = {
    HEAVY = {514, 515, 414, 455, 456, 578, 579, 600, 424, 573, 531, 408, 423, 588, 434, 443, 470, 524, 525},
    SPORTS = {402, 411, 415, 429, 451, 477, 494, 502, 503, 506, 541, 559, 560, 565, 587, 602, 603},
    MOTORCYCLE = {462, 463, 468, 471, 521, 522, 581, 586},
    NORMAL = {400, 401, 404, 405, 410, 412, 419, 421, 426, 436, 445, 458, 466, 467, 474, 475, 479, 480, 491, 492, 496, 500, 507, 516, 517, 518, 526, 527, 529, 533, 534, 535, 536, 540, 542, 545, 546, 547, 549, 550, 551, 554, 555, 558, 561, 562, 566, 567, 575, 576, 580, 582, 583, 585, 589, 596, 597, 598, 599, 604, 605}
}

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
    setTimer(removeFarTrafficElements, 2000, 0)
    setTimer(renewTrafficDynamic, 8000, 0)
    setTimer(forceReattachTrailers, 3000, 0)
    setTimer(updateTrafficAI, 100, 0) -- Sistema de IA principal
    setTimer(processLaneChanges, 500, 0) -- Processamento de mudanças de faixa
    setTimer(cleanupAIData, 10000, 0) -- Limpeza de dados de IA
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
        
        local player_key = tostring(player)
        local last_square = player_last_squares[player_key]
        local moved_significantly = false
        
        if not last_square then
            moved_significantly = true
            player_last_squares[player_key] = {x = current_x, y = current_y, dim = dim}
        else
            local distance = math.sqrt((current_x - last_square.x)^2 + (current_y - last_square.y)^2)
            if distance > 2 or last_square.dim ~= dim then
                moved_significantly = true
                player_last_squares[player_key] = {x = current_x, y = current_y, dim = dim}
            end
        end

        local spawn_radius = moved_significantly and 16 or 12
        
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

-- FUNÇÕES DE IA AVANÇADA

function getVehicleCategory(model)
    for category, models in pairs(VEHICLE_CATEGORIES) do
        for _, vehicleModel in ipairs(models) do
            if vehicleModel == model then
                return category
            end
        end
    end
    return "NORMAL"
end

function initVehicleAI(vehicle, driver)
    if not isElement(vehicle) or not isElement(driver) then return end
    
    local model = getElementModel(vehicle)
    local category = getVehicleCategory(model)
    
    -- Determinar comportamento
    local behavior = "normal"
    local rand = math.random()
    if rand < AI_CONFIG.AGGRESSIVE_CHANCE then
        behavior = "aggressive"
    elseif rand < AI_CONFIG.AGGRESSIVE_CHANCE + AI_CONFIG.CAUTIOUS_CHANCE then
        behavior = "cautious"
    end
    
    vehicle_ai[vehicle] = {
        driver = driver,
        category = category,
        behavior = behavior,
        last_speed_check = 0,
        target_speed = 1.0,
        current_speed = 0,
        sensor_data = {},
        lane_change_timer = 0,
        stuck_timer = 0,
        last_position = {x = 0, y = 0, z = 0},
        emergency_brake = false,
        following_vehicle = nil,
        preferred_lane = math.random(2) == 1 and "left" or "right"
    }
    
    vehicle_behavior[vehicle] = behavior
    
    -- Configurar velocidade base por categoria e comportamento
    local base_speed = 0.99
    if category == "HEAVY" then
        base_speed = 0.75
    elseif category == "SPORTS" then
        base_speed = 1.1
    elseif category == "MOTORCYCLE" then
        base_speed = 1.05
    end
    
    -- Ajustar por comportamento
    if behavior == "aggressive" then
        base_speed = base_speed * 1.2
    elseif behavior == "cautious" then
        base_speed = base_speed * 0.8
    end
    
    vehicle_ai[vehicle].target_speed = math.min(base_speed, 1.2)
end

function updateTrafficAI()
    local processed = 0
    for vehicle, ai_data in pairs(vehicle_ai) do
        if isElement(vehicle) and isElement(ai_data.driver) then
            processVehicleAI(vehicle, ai_data)
            processed = processed + 1
            
            -- Limitar processamento por frame
            if processed >= 20 then break end
        else
            vehicle_ai[vehicle] = nil
            vehicle_behavior[vehicle] = nil
            lane_change_cooldown[vehicle] = nil
        end
    end
end

function processVehicleAI(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local current_time = getTickCount()
    
    -- Verificar se está preso
    local distance_moved = getDistanceBetweenPoints3D(vx, vy, vz, ai_data.last_position.x, ai_data.last_position.y, ai_data.last_position.z)
    if distance_moved < 1 then
        ai_data.stuck_timer = ai_data.stuck_timer + 100
    else
        ai_data.stuck_timer = 0
    end
    ai_data.last_position = {x = vx, y = vy, z = vz}
    
    -- Sensor frontal
    local front_sensor = scanFrontSensor(vehicle, ai_data)
    ai_data.sensor_data.front = front_sensor
    
    -- Sensores laterais
    local left_sensor = scanLateralSensor(vehicle, ai_data, "left")
    local right_sensor = scanLateralSensor(vehicle, ai_data, "right")
    ai_data.sensor_data.left = left_sensor
    ai_data.sensor_data.right = right_sensor
    
    -- Determinar ação baseada nos sensores
    local action = determineAction(vehicle, ai_data)
    
    -- Executar ação
    executeAction(vehicle, ai_data, action)
    
    -- Atualizar velocidade do NPC
    updateNPCSpeed(vehicle, ai_data)
end

function scanFrontSensor(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    
    -- Calcular posição do sensor frontal
    local rad = math.rad(rz)
    local sensor_x = vx + math.sin(rad) * AI_CONFIG.SENSOR_DISTANCE
    local sensor_y = vy + math.cos(rad) * AI_CONFIG.SENSOR_DISTANCE
    
    local sensor_data = {
        clear = true,
        distance = AI_CONFIG.SENSOR_DISTANCE,
        target_vehicle = nil,
        relative_speed = 0
    }
    
    -- Verificar linha de visão e procurar veículos
    local hit, hit_x, hit_y, hit_z, hit_element = processLineOfSight(vx, vy, vz + 1, sensor_x, sensor_y, vz + 1, 
        true, true, false, true, false, false, false, false, vehicle)
    
    if hit and hit_element and getElementType(hit_element) == "vehicle" and hit_element ~= vehicle then
        local distance = getDistanceBetweenPoints3D(vx, vy, vz, hit_x, hit_y, hit_z)
        
        if distance <= AI_CONFIG.SENSOR_DISTANCE then
            sensor_data.clear = false
            sensor_data.distance = distance
            sensor_data.target_vehicle = hit_element
            
            -- Calcular velocidade relativa
            local my_vel_x, my_vel_y, my_vel_z = getElementVelocity(vehicle)
            local target_vel_x, target_vel_y, target_vel_z = getElementVelocity(hit_element)
            
            local my_speed = math.sqrt(my_vel_x^2 + my_vel_y^2)
            local target_speed = math.sqrt(target_vel_x^2 + target_vel_y^2)
            
            sensor_data.relative_speed = my_speed - target_speed
        end
    end
    
    return sensor_data
end

function scanLateralSensor(vehicle, ai_data, side)
    local vx, vy, vz = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    
    -- Calcular posição do sensor lateral
    local rad = math.rad(rz)
    local offset = side == "left" and -math.pi/2 or math.pi/2
    
    local sensor_x = vx + math.sin(rad + offset) * AI_CONFIG.SIDE_SENSOR_DISTANCE
    local sensor_y = vy + math.cos(rad + offset) * AI_CONFIG.SIDE_SENSOR_DISTANCE
    
    local sensor_data = {
        clear = true,
        distance = AI_CONFIG.SIDE_SENSOR_DISTANCE,
        safe_for_lane_change = true
    }
    
    -- Verificar múltiplos pontos para mudança de faixa
    for i = 0, 2 do
        local check_distance = AI_CONFIG.LANE_CHANGE_CHECK_DISTANCE * (i - 1)
        local check_x = vx + math.sin(rad) * check_distance + math.sin(rad + offset) * AI_CONFIG.SIDE_SENSOR_DISTANCE
        local check_y = vy + math.cos(rad) * check_distance + math.cos(rad + offset) * AI_CONFIG.SIDE_SENSOR_DISTANCE
        
        local hit, hit_x, hit_y, hit_z, hit_element = processLineOfSight(vx, vy, vz + 1, check_x, check_y, vz + 1, 
            true, true, false, true, false, false, false, false, vehicle)
        
        if hit and hit_element and getElementType(hit_element) == "vehicle" and hit_element ~= vehicle then
            local distance = getDistanceBetweenPoints3D(vx, vy, vz, hit_x, hit_y, hit_z)
            
            if distance <= AI_CONFIG.LANE_CHANGE_CHECK_DISTANCE then
                sensor_data.clear = false
                sensor_data.safe_for_lane_change = false
                sensor_data.distance = math.min(sensor_data.distance, distance)
            end
        end
    end
    
    return sensor_data
end

function determineAction(vehicle, ai_data)
    local front_sensor = ai_data.sensor_data.front
    local left_sensor = ai_data.sensor_data.left
    local right_sensor = ai_data.sensor_data.right
    
    -- NOVA VERIFICAÇÃO: Emergência para qualquer obstáculo (ped ou veículo)
    if not front_sensor.clear and front_sensor.distance < AI_CONFIG.EMERGENCY_BRAKE_DISTANCE then
        return "emergency_brake"
    end
    
    -- NOVA VERIFICAÇÃO: Freada preventiva para pedestres
    if front_sensor.target_vehicle and getElementType(front_sensor.target_vehicle) == "ped" then
        if front_sensor.distance < AI_CONFIG.SAFE_FOLLOWING_DISTANCE * 2 then
            return "emergency_brake"
        end
    end
    
    -- Seguimento seguro
    if not front_sensor.clear and front_sensor.distance < AI_CONFIG.SAFE_FOLLOWING_DISTANCE then
        -- Verificar se pode mudar de faixa
        if canChangeLane(vehicle, ai_data) then
            -- Escolher melhor faixa
            if left_sensor.safe_for_lane_change and not right_sensor.safe_for_lane_change then
                return "change_lane_left"
            elseif right_sensor.safe_for_lane_change and not left_sensor.safe_for_lane_change then
                return "change_lane_right"
            elseif left_sensor.safe_for_lane_change and right_sensor.safe_for_lane_change then
                -- Escolher baseado no comportamento
                if ai_data.behavior == "aggressive" then
                    return ai_data.preferred_lane == "left" and "change_lane_left" or "change_lane_right"
                else
                    return "change_lane_" .. ai_data.preferred_lane
                end
            else
                return "slow_down"
            end
        else
            return "slow_down"
        end
    end
    
    -- Comportamento preso
    if ai_data.stuck_timer > 5000 then
        if canChangeLane(vehicle, ai_data) and (left_sensor.safe_for_lane_change or right_sensor.safe_for_lane_change) then
            return left_sensor.safe_for_lane_change and "change_lane_left" or "change_lane_right"
        end
    end
    
    -- Comportamento normal
    return "normal_drive"
end

function canChangeLane(vehicle, ai_data)
    local current_time = getTickCount()
    local last_change = lane_change_cooldown[vehicle] or 0
    
    if current_time - last_change < AI_CONFIG.LANE_CHANGE_COOLDOWN then
        return false
    end
    
    -- Veículos pesados são mais relutantes para mudar de faixa
    if ai_data.category == "HEAVY" and math.random() < 0.7 then
        return false
    end
    
    -- Comportamento cauteloso muda menos
    if ai_data.behavior == "cautious" and math.random() < 0.6 then
        return false
    end
    
    return true
end

function executeAction(vehicle, ai_data, action)
    local current_time = getTickCount()
    
    if action == "emergency_brake" then
        ai_data.target_speed = 0.1
        ai_data.emergency_brake = true
        
    elseif action == "slow_down" then
        local front_sensor = ai_data.sensor_data.front
        local speed_factor = math.max(0.3, front_sensor.distance / AI_CONFIG.SAFE_FOLLOWING_DISTANCE)
        
        if ai_data.category == "HEAVY" then
            speed_factor = speed_factor * 0.8 -- Veículos pesados freiam mais cedo
        end
        
        ai_data.target_speed = ai_data.target_speed * speed_factor
        ai_data.emergency_brake = false
        
    elseif action == "change_lane_left" or action == "change_lane_right" then
        executeLaneChange(vehicle, ai_data, action)
        lane_change_cooldown[vehicle] = current_time
        
    elseif action == "normal_drive" then
        -- Restaurar velocidade normal
        local base_speed = 0.99
        if ai_data.category == "HEAVY" then
            base_speed = 0.75
        elseif ai_data.category == "SPORTS" then
            base_speed = 1.1
        elseif ai_data.category == "MOTORCYCLE" then
            base_speed = 1.05
        end
        
        if ai_data.behavior == "aggressive" then
            base_speed = base_speed * 1.2
        elseif ai_data.behavior == "cautious" then
            base_speed = base_speed * 0.8
        end
        
        ai_data.target_speed = math.min(base_speed, 1.2)
        ai_data.emergency_brake = false
    end
end

function executeLaneChange(vehicle, ai_data, direction)
    local vx, vy, vz = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    
    -- Calcular nova posição
    local rad = math.rad(rz)
    local offset = direction == "change_lane_left" and -math.pi/2 or math.pi/2
    local lane_width = 3.5 -- Largura padrão da faixa
    
    local new_x = vx + math.sin(rad + offset) * lane_width
    local new_y = vy + math.cos(rad + offset) * lane_width
    
    -- Verificar se a nova posição é válida
    local hit = processLineOfSight(vx, vy, vz, new_x, new_y, vz, true, false, false, true, false, false, false, false, vehicle)
    
    if not hit then
        -- Executar mudança suave usando timer
        local steps = 10
        local step_count = 0
        local start_x, start_y = vx, vy
        
        local change_timer = setTimer(function()
            if isElement(vehicle) then
                step_count = step_count + 1
                local progress = step_count / steps
                
                local current_x = start_x + (new_x - start_x) * progress
                local current_y = start_y + (new_y - start_y) * progress
                
                setElementPosition(vehicle, current_x, current_y, vz)
                
                if step_count >= steps then
                    killTimer(change_timer)
                end
            else
                killTimer(change_timer)
            end
        end, 50, steps)
        
        -- Atualizar preferência de faixa
        ai_data.preferred_lane = direction == "change_lane_left" and "left" or "right"
    end
end

function updateNPCSpeed(vehicle, ai_data)
    if not isElement(ai_data.driver) then return end
    
    -- Suavizar mudanças de velocidade
    local speed_diff = ai_data.target_speed - ai_data.current_speed
    local acceleration = 0.02
local braking = 0.06

local speed_change = speed_diff > 0 and math.min(speed_diff, acceleration) or math.max(speed_diff, -braking)
 -- Mudança gradual
    
    if ai_data.emergency_brake then
        speed_change = speed_diff * 0.5 -- Mudança rápida em emergência
    end
    
    ai_data.current_speed = ai_data.current_speed + speed_change
    ai_data.current_speed = math.max(0.1, math.min(ai_data.current_speed, 1.2))
    
    -- Aplicar velocidade
    if ai_data.current_speed <= 0.15 then
    -- Ativa o freio de mão simulando o "segurar no lugar"
    call(npc_hlc, "enableHLCForNPC", ai_data.driver, "walk", 0.99, 0)
else
    call(npc_hlc, "enableHLCForNPC", ai_data.driver, "walk", 0.99, ai_data.current_speed)
end

end

function processLaneChanges()
    -- Processar mudanças de faixa mais complexas aqui se necessário
    local processed = 0
    for vehicle, ai_data in pairs(vehicle_ai) do
        if isElement(vehicle) and processed < 5 then
            -- Lógica adicional para mudanças de faixa inteligentes
            checkOpportunisticLaneChange(vehicle, ai_data)
            processed = processed + 1
        end
    end
end

function checkOpportunisticLaneChange(vehicle, ai_data)
    -- Mudanças oportunísticas para ultrapassagem
    if ai_data.behavior == "aggressive" and canChangeLane(vehicle, ai_data) then
        local front_sensor = ai_data.sensor_data.front
        
        if not front_sensor.clear and front_sensor.relative_speed > 0.1 then
            -- Veículo à frente é mais lento, tentar ultrapassar
            local left_sensor = ai_data.sensor_data.left
            local right_sensor = ai_data.sensor_data.right
            
            if left_sensor and left_sensor.safe_for_lane_change then
                executeLaneChange(vehicle, ai_data, "change_lane_left")
                lane_change_cooldown[vehicle] = getTickCount()
            elseif right_sensor and right_sensor.safe_for_lane_change then
                executeLaneChange(vehicle, ai_data, "change_lane_right")
                lane_change_cooldown[vehicle] = getTickCount()
            end
        end
    end
end

function cleanupAIData()
    -- Limpeza periódica de dados de IA para veículos destruídos
    for vehicle, _ in pairs(vehicle_ai) do
        if not isElement(vehicle) then
            vehicle_ai[vehicle] = nil
            vehicle_behavior[vehicle] = nil
            lane_change_cooldown[vehicle] = nil
        end
    end
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

function removeFarTrafficElements()
    if not square_population then return end

    local safe_distance = SQUARE_SIZE * 15
    local removed_count = 0

    for vehicle, _ in pairs(population.cars) do
        if isElement(vehicle) then
            local vx, vy, vz = getElementPosition(vehicle)
            local should_remove = true
            local closest_distance = math.huge

            for player, _ in pairs(players) do
                if isElement(player) then
                    local px, py, pz = getElementPosition(player)
                    local distance = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                    
                    if distance < closest_distance then
                        closest_distance = distance
                    end
                    
                    if distance < safe_distance then
                        should_remove = false
                        break
                    end
                end
            end

            if should_remove and closest_distance < safe_distance * 2 then
                for player, _ in pairs(players) do
                    if isElement(player) then
                        local px, py, pz = getElementPosition(player)
                        local distance = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
                        
                        if distance == closest_distance then
                            if isLineOfSightClear(px, py, pz + 1, vx, vy, vz + 1, true, false, false, true, false, true, false) then
                                should_remove = false
                            end
                            break
                        end
                    end
                end
            end

            if should_remove then
                local occupants = getVehicleOccupants(vehicle)
                
                -- Limpar dados de IA
                vehicle_ai[vehicle] = nil
                vehicle_behavior[vehicle] = nil
                lane_change_cooldown[vehicle] = nil
                
                if trailer_connections[vehicle] then
                    local trailer = trailer_connections[vehicle]
                    if isElement(trailer) then
                        destroyElement(trailer)
                    end
                    trailer_connections[vehicle] = nil
                end
                
                destroyElement(vehicle)
                removed_count = removed_count + 1
                
                for seat, ped in pairs(occupants) do
                    if isElement(ped) and population.peds[ped] then
                        destroyElement(ped)
                    end
                end
            end
        end
    end

    for ped, _ in pairs(population.peds) do
        if isElement(ped) and not isPedInVehicle(ped) then
            local px, py, pz = getElementPosition(ped)
            local should_remove = true
            local closest_distance = math.huge

            for player, _ in pairs(players) do
                if isElement(player) then
                    local plx, ply, plz = getElementPosition(player)
                    local distance = getDistanceBetweenPoints3D(plx, ply, plz, px, py, pz)
                    
                    if distance < closest_distance then
                        closest_distance = distance
                    end
                    
                    if distance < safe_distance then
                        should_remove = false
                        break
                    end
                end
            end

            if should_remove and closest_distance < safe_distance * 2 then
                for player, _ in pairs(players) do
                    if isElement(player) then
                        local plx, ply, plz = getElementPosition(player)
                        local distance = getDistanceBetweenPoints3D(plx, ply, plz, px, py, pz)
                        
                        if distance == closest_distance then
                            if isLineOfSightClear(plx, ply, plz + 1, px, py, pz + 1, true, false, false, true, false, true, false) then
                                should_remove = false
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
        ------outputDebugString("Remoção individual: " .. removed_count .. " elementos removidos")
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
            -- Sistema melhorado de seleção de veículos por área
            local world_x, world_y = x, y
            
            -- Detectar tipo de via baseado na velocidade máxima
            local max_speed = conn_maxspeed[connid] or 50
            local is_highway = max_speed > 80
            local is_urban = (world_x > 44 and world_x < 2997 and world_y > -2892 and world_y < -596)
            
            if is_highway then
                -- Rodovias: mais veículos pesados, carros rápidos
                local highway_vehicles = {
                    -- Veículos pesados (40%)
                    514, 515, 414, 455, 456, 578, 579, 600, 424, 573, 531, 408, 423, 588, 434, 443, 470, 524, 525,
                    -- Carros rápidos (35%)
                    402, 411, 415, 429, 451, 477, 494, 502, 503, 506, 541, 559, 560, 565, 587, 602, 603,
                    -- Carros normais (20%)
                    400, 401, 404, 405, 426, 436, 445, 458, 466, 467, 474, 475, 479, 480, 491, 492, 496, 500, 507,
                    -- Motos (5%)
                    462, 463, 468, 471, 521, 522, 581, 586
                }
                model = highway_vehicles[math.random(#highway_vehicles)]
            elseif is_urban then
                -- Área urbana: carros pequenos, táxis, motos
                local urban_vehicles = {
                    -- Carros urbanos (60%)
                    400, 401, 404, 405, 410, 412, 419, 421, 426, 436, 445, 458, 466, 467, 474, 475, 479, 480, 491, 492, 496, 500, 507, 516, 517, 518, 526, 527, 529, 533, 534, 535, 536, 540, 542, 545, 546, 547, 549, 550, 551, 554, 555, 558, 561, 562, 566, 567, 575, 576, 580, 582, 583, 585, 589, 596, 597, 598, 599, 604, 605,
                    -- Táxis (15%)
                    420, 438,
                    -- Motos (20%)
                    462, 463, 468, 471, 521, 522, 581, 586,
                    -- Alguns veículos de serviço (5%)
                    431, 437, 482, 483, 508, 524, 525
                }
                model = urban_vehicles[math.random(#urban_vehicles)]
            else
                -- Área rural: mix equilibrado
                local rural_vehicles = {
                    -- Carros normais (50%)
                    400, 401, 404, 405, 410, 412, 419, 421, 426, 436, 445, 458, 466, 467, 474, 475, 479, 480, 491, 492, 496, 500, 507,
                    -- Veículos pesados (25%)
                    514, 515, 414, 455, 456, 578, 579, 600, 424, 573, 531, 408, 423, 588, 434, 443, 470, 524, 525,
                    -- Veículos rurais/utilitários (20%)
                    459, 479, 482, 495, 500, 543, 554, 568, 579, 600,
                    -- Motos (5%)
                    462, 463, 468, 471, 521, 522, 581, 586
                }
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

            -- Inicializar IA do veículo
            initVehicleAI(car, ped1)

            local maxpass = getVehicleMaxPassengers(model)

            -- Sistema inteligente de passageiros baseado no tipo de veículo
            local passenger_chance = 0.5
            local category = getVehicleCategory(model)
            
            if category == "HEAVY" then
                passenger_chance = 0.2 -- Caminhões raramente têm passageiros
            elseif category == "SPORTS" then
                passenger_chance = 0.3 -- Carros esportivos geralmente têm 1 pessoa
            elseif category == "MOTORCYCLE" then
                passenger_chance = 0.15 -- Motos raramente têm carona
            end

            if maxpass >= 1 and math.random() < passenger_chance then
                local ped2 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped2, car, 1)
                setElementDimension(ped2, dim)
                element_timers[ped2] = {}
                addEventHandler("onElementDestroy", ped2, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped2, removeDeadPed, false)
                population.peds[ped2] = true
            end

            if maxpass >= 2 and math.random() < (passenger_chance * 0.5) then
                local ped3 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped3, car, 2)
                setElementDimension(ped3, dim)
                element_timers[ped3] = {}
                addEventHandler("onElementDestroy", ped3, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped3, removeDeadPed, false)
                population.peds[ped3] = true
            end

            if maxpass >= 3 and math.random() < (passenger_chance * 0.25) then
                local ped4 = createPed(skins[math.random(skincount)], x, y, z+1)
                warpPedIntoVehicle(ped4, car, 3)
                setElementDimension(ped4, dim)
                element_timers[ped4] = {}
                addEventHandler("onElementDestroy", ped4, removePedFromListOnDestroy, false)
                addEventHandler("onPedWasted", ped4, removeDeadPed, false)
                population.peds[ped4] = true
            end

            -- Sistema melhorado de trailers
            if category == "HEAVY" and (model == 514 or model == 515) and math.random() < 0.4 then -- 40% chance para caminhões
                local trailers = {435, 450, 584, 590, 591, 592, 593}
                local trailer_model = trailers[math.random(#trailers)]
                
                local trailer = createVehicle(trailer_model, x - 8, y, z+zoff, rx, 0, rz)
                setElementDimension(trailer, dim)
                
                if colcheck then call(server_coldata, "updateElementColData", trailer) end
                
                element_timers[trailer] = {}
                addEventHandler("onElementDestroy", trailer, removeCarFromListOnDestroy, false)
                addEventHandler("onVehicleExplode", trailer, removeDestroyedCar, false)
                population.cars[trailer] = true
                
                -- Salvar conexão
                trailer_connections[car] = trailer
                
                -- Engatar trailer com delay
                setTimer(function()
                    if isElement(car) and isElement(trailer) then
                        local success = attachTrailerToVehicle(car, trailer)
                        if success then
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
    -- Limpar dados de IA
    vehicle_ai[source] = nil
    vehicle_behavior[source] = nil
    lane_change_cooldown[source] = nil
    
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
            
            if not attached_trailer then
                local truck_x, truck_y, truck_z = getElementPosition(truck)
                local trailer_x, trailer_y, trailer_z = getElementPosition(trailer)
                local distance = getDistanceBetweenPoints3D(truck_x, truck_y, truck_z, trailer_x, trailer_y, trailer_z)
                
                if distance < 30 then
                    local success = attachTrailerToVehicle(truck, trailer)
                    if success then
                        ---outputDebugString("Trailer re-engatado automaticamente! Distância: " .. math.floor(distance) .. "m")
                    end
                end
            end
        else
            killTimer(monitor_timer)
            if trailer_connections[truck] then
                trailer_connections[truck] = nil
            end
        end
    end, 1000, 0)
    
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
                
                if distance < 35 then
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
        ---outputDebugString("Força re-engate: " .. reattached_count .. " trailers reengatados")
    end
end

function renewTrafficDynamic()
    if not square_population then return end
    
    local renewal_count = 0
    for dim, square_dim in pairs(square_population) do
        for y, square_row in pairs(square_dim) do
            for x, square in pairs(square_row) do
                if square.gen_mode == "spawn" and math.random() < 0.02 then
                    for vehicle, _ in pairs(square.list.cars) do
                        if math.random() < 0.1 then
                            if isElement(vehicle) then
                                local occupants = getVehicleOccupants(vehicle)
                                destroyElement(vehicle)
                                for seat, ped in pairs(occupants) do
                                    if isElement(ped) then
                                        destroyElement(ped)
                                    end
                                end
                                renewal_count = renewal_count + 1
                                break
                            end
                        end
                    end
                end
                
                if square.gen_mode == "spawn" and math.random() < 0.015 then
                    for ped, _ in pairs(square.list.peds) do
                        if not isPedInVehicle(ped) and math.random() < 0.08 then
                            if isElement(ped) then
                                destroyElement(ped)
                                renewal_count = renewal_count + 1
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    
    if renewal_count > 0 then
        ---outputDebugString("Tráfego renovado: " .. renewal_count .. " elementos removidos para renovação")
    end
end

-- FUNÇÕES ADICIONAIS DE IA AVANÇADA

-- Sistema de detecção de intersecções
function detectIntersection(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local rx, ry, rz = getElementRotation(vehicle)
    
    -- Verificar se há intersecção à frente
    local rad = math.rad(rz)
    local check_distance = 25
    local check_x = vx + math.sin(rad) * check_distance
    local check_y = vy + math.cos(rad) * check_distance
    
    -- Aqui você pode implementar lógica específica para detectar intersecções
    -- baseado no sistema de nós do seu mapa
    
    return false -- Placeholder
end

-- Sistema de prioridade em intersecções
function processIntersectionBehavior(vehicle, ai_data)
    if detectIntersection(vehicle, ai_data) then
        -- Reduzir velocidade ao se aproximar de intersecção
        ai_data.target_speed = ai_data.target_speed * 0.7
        
        -- Verificar se há outros veículos na intersecção
        local vx, vy, vz = getElementPosition(vehicle)
        local nearby_vehicles = {}
        
        for other_vehicle, other_ai in pairs(vehicle_ai) do
            if other_vehicle ~= vehicle and isElement(other_vehicle) then
                local ox, oy, oz = getElementPosition(other_vehicle)
                local distance = getDistanceBetweenPoints3D(vx, vy, vz, ox, oy, oz)
                
                if distance < 20 then
                    table.insert(nearby_vehicles, {vehicle = other_vehicle, distance = distance})
                end
            end
        end
        
        -- Implementar regra de prioridade (direita tem preferência)
        for _, nearby in ipairs(nearby_vehicles) do
            -- Lógica de prioridade aqui
        end
    end
end

-- Sistema de adaptação de velocidade por clima/hora
function adaptSpeedForConditions(vehicle, ai_data)
    local hour = getRealTime().hour
    local speed_modifier = 1.0
    
    -- Reduzir velocidade à noite (22h às 6h)
    if hour >= 22 or hour <= 6 then
        speed_modifier = speed_modifier * 0.9
    end
    
    -- Reduzir velocidade no horário de rush (7-9h e 17-19h)
    if (hour >= 7 and hour <= 9) or (hour >= 17 and hour <= 19) then
        speed_modifier = speed_modifier * 0.8
    end
    
    -- Aplicar modificador
    ai_data.target_speed = ai_data.target_speed * speed_modifier
end

-- Sistema de comunicação entre veículos (V2V)
function processVehicleToVehicleCommunication(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local communication_range = 100
    
    -- Procurar outros veículos na área
    for other_vehicle, other_ai in pairs(vehicle_ai) do
        if other_vehicle ~= vehicle and isElement(other_vehicle) then
            local ox, oy, oz = getElementPosition(other_vehicle)
            local distance = getDistanceBetweenPoints3D(vx, vy, vz, ox, oy, oz)
            
            if distance <= communication_range then
                -- Compartilhar informações sobre condições de tráfego
                if other_ai.emergency_brake then
                    -- Se outro veículo está freando, reduzir velocidade preventivamente
                    ai_data.target_speed = ai_data.target_speed * 0.9
                end
                
                -- Coordenar mudanças de faixa
                if other_ai.sensor_data.front and not other_ai.sensor_data.front.clear then
                    -- Facilitar ultrapassagem do outro veículo
                    if ai_data.sensor_data.left and ai_data.sensor_data.left.safe_for_lane_change then
                        -- Dar espaço para ultrapassagem
                        ai_data.target_speed = ai_data.target_speed * 0.95
                    end
                end
            end
        end
    end
end

-- Sistema de aprendizado de rotas
local route_learning = {}

function learnRoutePatterns(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local current_time = getRealTime().hour
    local route_key = math.floor(vx/100) .. "_" .. math.floor(vy/100)
    
    if not route_learning[route_key] then
        route_learning[route_key] = {
            congestion_times = {},
            average_speed = {},
            traffic_density = 0
        }
    end
    
    local route_data = route_learning[route_key]
    
    -- Registrar velocidade média nesta área
    if not route_data.average_speed[current_time] then
        route_data.average_speed[current_time] = {}
    end
    
    local current_speed = ai_data.current_speed or 0
    table.insert(route_data.average_speed[current_time], current_speed)
    
    -- Manter apenas os últimos 10 registros por hora
    if #route_data.average_speed[current_time] > 10 then
        table.remove(route_data.average_speed[current_time], 1)
    end
    
    -- Calcular velocidade média para esta hora
    local total_speed = 0
    for _, speed in ipairs(route_data.average_speed[current_time]) do
        total_speed = total_speed + speed
    end
    local avg_speed = total_speed / #route_data.average_speed[current_time]
    
    -- Se a velocidade média está baixa, esta área está congestionada
    if avg_speed < 0.5 then
        if not route_data.congestion_times[current_time] then
            route_data.congestion_times[current_time] = 0
        end
        route_data.congestion_times[current_time] = route_data.congestion_times[current_time] + 1
    end
end

function applyLearnedBehavior(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    local current_time = getRealTime().hour
    local route_key = math.floor(vx/100) .. "_" .. math.floor(vy/100)
    
    if route_learning[route_key] then
        local route_data = route_learning[route_key]
        
        -- Se esta área costuma ter congestionamento neste horário
        if route_data.congestion_times[current_time] and route_data.congestion_times[current_time] > 5 then
            -- Ajustar comportamento proativamente
            ai_data.target_speed = ai_data.target_speed * 0.8
            
            -- Aumentar chance de mudança de faixa
            if canChangeLane(vehicle, ai_data) then
                local left_sensor = ai_data.sensor_data.left
                local right_sensor = ai_data.sensor_data.right
                
                if left_sensor and left_sensor.safe_for_lane_change and math.random() < 0.3 then
                    executeLaneChange(vehicle, ai_data, "change_lane_left")
                    lane_change_cooldown[vehicle] = getTickCount()
                elseif right_sensor and right_sensor.safe_for_lane_change and math.random() < 0.3 then
                    executeLaneChange(vehicle, ai_data, "change_lane_right")
                    lane_change_cooldown[vehicle] = getTickCount()
                end
            end
        end
    end
end

-- Sistema de detecção de situações especiais
function detectSpecialSituations(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    
    -- Detectar veículos de emergência próximos
    local emergency_vehicles = {416, 427, 490, 523, 528, 596, 597, 598, 599} -- Ambulâncias, polícia, bombeiros
    
    for other_vehicle, exists in pairs(population.cars) do
        if isElement(other_vehicle) and other_vehicle ~= vehicle then
            local model = getElementModel(other_vehicle)
            
            for _, emergency_model in ipairs(emergency_vehicles) do
                if model == emergency_model then
                    local ox, oy, oz = getElementPosition(other_vehicle)
                    local distance = getDistanceBetweenPoints3D(vx, vy, vz, ox, oy, oz)
                    
                    if distance < 50 then
                        -- Dar passagem para veículo de emergência
                        ai_data.target_speed = ai_data.target_speed * 0.5
                        
                        -- Tentar mudar de faixa se possível
                        if canChangeLane(vehicle, ai_data) then
                            local left_sensor = ai_data.sensor_data.left
                            local right_sensor = ai_data.sensor_data.right
                            
                            if right_sensor and right_sensor.safe_for_lane_change then
                                executeLaneChange(vehicle, ai_data, "change_lane_right")
                                lane_change_cooldown[vehicle] = getTickCount()
                            elseif left_sensor and left_sensor.safe_for_lane_change then
                                executeLaneChange(vehicle, ai_data, "change_lane_left")
                                lane_change_cooldown[vehicle] = getTickCount()
                            end
                        end
                        
                        return true -- Situação especial detectada
                    end
                end
            end
        end
    end
    
    return false
end

-- Sistema de comportamento em diferentes tipos de via
function adaptBehaviorToRoadType(vehicle, ai_data)
    local vx, vy, vz = getElementPosition(vehicle)
    
    -- Detectar tipo de via baseado na posição (você pode expandir isso)
    local is_highway = false -- Implementar detecção de rodovia
    local is_residential = false -- Implementar detecção de área residencial
    local is_commercial = false -- Implementar detecção de área comercial
    
    -- Coordenadas aproximadas para diferentes tipos de área em San Andreas
    -- Highway (rodovias principais)
    if (vx > 2200 and vx < 2700 and vy > -2600 and vy < -2000) or -- Highway próximo a LV
       (vx > -2800 and vx < -2200 and vy > -200 and vy < 200) then -- Highway SF-LS
        is_highway = true
    end
    
    -- Residential (áreas residenciais)
    if (vx > 2000 and vx < 2300 and vy > -1800 and vy < -1400) or -- Residential LV
       (vx > 800 and vx < 1200 and vy > -2100 and vy < -1700) then -- Residential LS
        is_residential = true
    end
    
    -- Commercial (áreas comerciais)
    if (vx > 1400 and vx < 1800 and vy > -1800 and vy < -1400) or -- Downtown LS
       (vx > 2100 and vx < 2400 and vy > -1700 and vy < -1400) then -- Las Venturas Strip
        is_commercial = true
    end
    
    if is_highway then
        -- Comportamento em rodovia: velocidades mais altas, menos mudanças de faixa
        ai_data.target_speed = ai_data.target_speed * 1.2
        AI_CONFIG.LANE_CHANGE_COOLDOWN = 5000 -- Mais tempo entre mudanças
        
    elseif is_residential then
        -- Comportamento em área residencial: velocidades menores, mais cuidado
        ai_data.target_speed = ai_data.target_speed * 0.7
        AI_CONFIG.SAFE_FOLLOWING_DISTANCE = AI_CONFIG.SAFE_FOLLOWING_DISTANCE * 1.3
        
    elseif is_commercial then
        -- Comportamento em área comercial: velocidade moderada, mais mudanças
        ai_data.target_speed = ai_data.target_speed * 0.8
        AI_CONFIG.LANE_CHANGE_COOLDOWN = 2000 -- Menos tempo entre mudanças
    end
end

-- Sistema de formação de comboios (platooning)
function processPlatooningBehavior(vehicle, ai_data)
    if ai_data.category ~= "HEAVY" then return end -- Apenas para veículos pesados
    
    local vx, vy, vz = getElementPosition(vehicle)
    local platoon_range = 30
    local platoon_members = {}
    
    -- Procurar outros veículos pesados próximos
    for other_vehicle, other_ai in pairs(vehicle_ai) do
        if other_vehicle ~= vehicle and isElement(other_vehicle) and other_ai.category == "HEAVY" then
            local ox, oy, oz = getElementPosition(other_vehicle)
            local distance = getDistanceBetweenPoints3D(vx, vy, vz, ox, oy, oz)
            
            if distance <= platoon_range then
                table.insert(platoon_members, {vehicle = other_vehicle, distance = distance, ai = other_ai})
            end
        end
    end
    
    -- Se há outros veículos pesados próximos, formar comboio
    if #platoon_members > 0 then
        -- Ordenar por distância
        table.sort(platoon_members, function(a, b) return a.distance < b.distance end)
        
        local leader = platoon_members[1]
        
        -- Seguir o líder mais próximo
        local target_distance = 12 -- Distância ideal no comboio
        
        if leader.distance < target_distance - 2 then
            -- Muito próximo, reduzir velocidade
            ai_data.target_speed = ai_data.target_speed * 0.9
        elseif leader.distance > target_distance + 2 then
            -- Muito longe, acelerar
            ai_data.target_speed = ai_data.target_speed * 1.1
        end
        
        -- Sincronizar velocidade com o líder
        ai_data.target_speed = (ai_data.target_speed + leader.ai.target_speed) / 2
    end
end

-- Sistema de economia de combustível (simulado)
function optimizeForFuelEfficiency(vehicle, ai_data)
    if ai_data.category == "HEAVY" then
        -- Veículos pesados tentam manter velocidade constante
        local current_speed = ai_data.current_speed or 0
        local speed_diff = math.abs(ai_data.target_speed - current_speed)
        
        if speed_diff > 0.1 then
            -- Mudanças graduais para economia
            local change_rate = 0.05
            if ai_data.target_speed > current_speed then
                ai_data.target_speed = current_speed + change_rate
            else
                ai_data.target_speed = current_speed - change_rate
            end
        end
        
        -- Evitar acelerações desnecessárias
        if not ai_data.sensor_data.front or ai_data.sensor_data.front.clear then
            ai_data.target_speed = math.min(ai_data.target_speed, 0.8) -- Velocidade econômica
        end
    end
end

-- Sistema principal que integra todos os comportamentos avançados
function processAdvancedAI(vehicle, ai_data)
    -- Aplicar todos os sistemas de IA avançada
    
    -- 1. Processar intersecções
    processIntersectionBehavior(vehicle, ai_data)
    
    -- 2. Adaptar à condições climáticas/hora
    adaptSpeedForConditions(vehicle, ai_data)
    
    -- 3. Comunicação entre veículos
    processVehicleToVehicleCommunication(vehicle, ai_data)
    
    -- 4. Aprender padrões de rota
    learnRoutePatterns(vehicle, ai_data)
    applyLearnedBehavior(vehicle, ai_data)
    
    -- 5. Detectar situações especiais
    if detectSpecialSituations(vehicle, ai_data) then
        return -- Se situação especial, não aplicar outros comportamentos
    end
    
    -- 6. Adaptar ao tipo de via
    adaptBehaviorToRoadType(vehicle, ai_data)
    
    -- 7. Comportamento de comboio para veículos pesados
    processPlatooningBehavior(vehicle, ai_data)
    
    -- 8. Otimização de combustível
    optimizeForFuelEfficiency(vehicle, ai_data)
end

-- Atualizar o sistema principal de IA para incluir comportamentos avançados
local original_processVehicleAI = processVehicleAI
processVehicleAI = function(vehicle, ai_data)
    -- Executar IA básica
    original_processVehicleAI(vehicle, ai_data)
    
    -- Executar IA avançada
    processAdvancedAI(vehicle, ai_data)
end

-- Sistema de debug para monitoramento da IA (opcional)
function debugAIStatus()
    local total_vehicles = 0
    local by_behavior = {normal = 0, aggressive = 0, cautious = 0}
    local by_category = {NORMAL = 0, HEAVY = 0, SPORTS = 0, MOTORCYCLE = 0}
    
    for vehicle, ai_data in pairs(vehicle_ai) do
        if isElement(vehicle) then
            total_vehicles = total_vehicles + 1
            by_behavior[ai_data.behavior] = (by_behavior[ai_data.behavior] or 0) + 1
            by_category[ai_data.category] = (by_category[ai_data.category] or 0) + 1
        end
    end
    
    ---outputDebugString("=== STATUS DA IA DE TRÁFEGO ===")
    ---outputDebugString("Total de veículos com IA: " .. total_vehicles)
    ---outputDebugString("Comportamentos - Normal: " .. by_behavior.normal .. ", Agressivo: " .. by_behavior.aggressive .. ", Cauteloso: " .. by_behavior.cautious)
    ---outputDebugString("Categorias - Normal: " .. by_category.NORMAL .. ", Pesado: " .. by_category.HEAVY .. ", Esportivo: " .. by_category.SPORTS .. ", Moto: " .. by_category.MOTORCYCLE)
end

-- Timer opcional para debug (descomente se quiser monitorar)
-- setTimer(debugAIStatus, 30000, 0)
