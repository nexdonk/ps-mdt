local resourceName = tostring(GetCurrentResourceName())

-- Acquire frameworks DEFENSIVELY. This file previously did an unguarded
-- exports['qb-core']:GetCoreObject() at load, which crashed the whole script on
-- ESX / non-QB servers. Both lookups are now optional.
local okQB, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
if not okQB then QBCore = nil end

local ESX
if GetResourceState('es_extended') == 'started' then
    local okESX, obj = pcall(function() return exports['es_extended']:getSharedObject() end)
    if okESX then ESX = obj end
end

-- Impound locations - override in config if needed
local ImpoundLocations = Config.ImpoundLocations or {
    [1] = vector4(409.09, -1623.37, 29.29, 232.07),
    [2] = vector4(-436.42, 5982.29, 31.34, 136.0),
}

-- Apply damage to vehicle based on stored damage values
local function doCarDamage(currentVehicle, veh)
    local smash = false
    local damageOutside = false
    local damageOutside2 = false
    local engine = (veh.engine or 1000.0) + 0.0
    local body = (veh.body or 1000.0) + 0.0

    if engine < 200.0 then engine = 200.0 end
    if engine > 1000.0 then engine = 950.0 end
    if body < 150.0 then body = 150.0 end
    if body < 950.0 then smash = true end
    if body < 920.0 then damageOutside = true end
    if body < 920.0 then damageOutside2 = true end

    Wait(100)
    SetVehicleEngineHealth(currentVehicle, engine)

    if smash then
        for i = 0, 4 do
            SmashVehicleWindow(currentVehicle, i)
        end
    end

    if damageOutside then
        SetVehicleDoorBroken(currentVehicle, 1, true)
        SetVehicleDoorBroken(currentVehicle, 6, true)
        SetVehicleDoorBroken(currentVehicle, 4, true)
    end

    if damageOutside2 then
        for i = 1, 4 do
            SetVehicleTyreBurst(currentVehicle, i, false, 990.0)
        end
    end

    if body < 1000 then
        SetVehicleBodyHealth(currentVehicle, 985.1)
    end
end

-- Common finishing touches once the vehicle entity exists.
local function finishSpawn(veh, data, coords)
    if not veh or veh == 0 then
        ps.notify('Failed to spawn impound vehicle', 'error')
        return
    end
    SetVehicleNumberPlateText(veh, data.plate)
    SetEntityHeading(veh, coords.w or 0.0)

    -- Set fuel
    local fuelExport = Config.Fuel or 'LegacyFuel'
    if GetResourceState(fuelExport) == 'started' then
        pcall(function()
            exports[fuelExport]:SetFuel(veh, data.fuel or 100.0)
        end)
    end

    -- Apply damage
    doCarDamage(veh, data)

    -- Give keys to owner (vehiclekeys event is a no-op if the resource isn't present)
    pcall(function()
        TriggerEvent('vehiclekeys:client:SetOwner', GetVehicleNumberPlateText(veh))
    end)

    SetVehicleEngineOn(veh, true, true)
end

-- Native spawn fallback for servers without a framework spawn helper.
local function nativeSpawnVehicle(model, coords, cb)
    local hash = model
    if type(hash) == 'string' then hash = GetHashKey(hash) end
    RequestModel(hash)
    local timeout = 0
    while not HasModelLoaded(hash) and timeout < 100 do
        Wait(50)
        timeout = timeout + 1
    end
    if not HasModelLoaded(hash) then
        ps.notify('Failed to load vehicle model', 'error')
        return
    end
    local veh = CreateVehicle(hash, coords.x, coords.y, coords.z, coords.w or 0.0, true, false)
    SetModelAsNoLongerNeeded(hash)
    if cb then cb(veh) end
end

-- Spawn vehicle at impound location (framework-aware)
local function TakeOutImpound(data, garageIndex)
    local coords = ImpoundLocations[garageIndex]
    if not coords then
        ps.notify('Invalid impound location', 'error')
        return
    end

    local model = data.vehicle
    -- ESX often stores the model as a numeric hash (possibly as a string).
    if type(model) == 'string' and tonumber(model) then
        model = tonumber(model)
    end

    if QBCore and QBCore.Functions and QBCore.Functions.SpawnVehicle then
        -- QBCore / Qbox: spawn then restore stored mods via qb-garage.
        QBCore.Functions.SpawnVehicle(data.vehicle, function(veh)
            QBCore.Functions.TriggerCallback('qb-garage:server:GetVehicleProperties', function(properties)
                if properties then
                    QBCore.Functions.SetVehicleProperties(veh, properties)
                end
                finishSpawn(veh, data, coords)
            end, data.plate)
        end, coords, true)
    elseif ESX and ESX.Game and ESX.Game.SpawnVehicle then
        -- ESX: spawn by model. Stored mods are not restored here (server/garage
        -- specific); the vehicle spawns with the correct plate at the lot.
        ESX.Game.SpawnVehicle(model, vector3(coords.x, coords.y, coords.z), coords.w or 0.0, function(veh)
            finishSpawn(veh, data, coords)
        end)
    else
        nativeSpawnVehicle(model, coords, function(veh)
            finishSpawn(veh, data, coords)
        end)
    end
end

-- Event: Vehicle released from impound, spawn it
RegisterNetEvent(resourceName .. ':client:TakeOutImpound', function(data)
    if not data then return end

    local pos = GetEntityCoords(PlayerPedId())
    local garageIndex = data.currentSelection or 1
    local impoundCoords = ImpoundLocations[garageIndex]

    if not impoundCoords then
        ps.notify('Invalid impound location', 'error')
        return
    end

    local takeDist = vector3(impoundCoords.x, impoundCoords.y, impoundCoords.z)
    if #(pos - takeDist) <= 15.0 then
        TakeOutImpound(data, garageIndex)
    else
        ps.notify('You are too far away from the impound location!', 'error')
    end
end)

-- Also listen for the v1 event name for backwards compatibility
RegisterNetEvent('ps-mdt:client:TakeOutImpound', function(data)
    TriggerEvent(resourceName .. ':client:TakeOutImpound', data)
end)
