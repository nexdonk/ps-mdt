local resourceName = tostring(GetCurrentResourceName())
-- Optional: only used as a fallback for qb-inventory radio-possession checks.
local okQB, QBCore = pcall(function() return exports['qb-core']:GetCoreObject() end)
if not okQB then QBCore = nil end

--- Resolve the live server id for a citizen identifier across frameworks.
--- QBCore/Qbox players expose PlayerData.source, ESX exposes .source. The
--- ps.getSource bridge already normalises this, but we fall back defensively.
local function resolveSource(cid)
    if not cid then return nil end
    local src = ps.getSource and ps.getSource(cid)
    if src then return src end
    local player = ps.getPlayerByIdentifier(cid)
    if not player then return nil end
    return player.source or (player.PlayerData and player.PlayerData.source)
end

-- Get player source ID by citizenId
ps.registerCallback(resourceName .. ':server:GetPlayerSourceId', function(source, targetCitizenId)
    if not targetCitizenId then return nil end
    local src = resolveSource(targetCitizenId)
    if not src then
        ps.notify(source, 'Citizen seems asleep / missing', 'error')
        return nil
    end
    return src
end)

-- Set Callsign
ps.registerCallback(resourceName .. ':server:setCallsign', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local cid = payload.citizenid or payload.cid
    local newCallsign = payload.callsign or payload.newcallsign

    if not cid or not newCallsign then
        return { success = false, message = 'Missing citizen ID or callsign' }
    end

    local targetSrc = resolveSource(cid)
    -- Persist to the MDT profile regardless of online state so the callsign is
    -- retained for offline officers / rosters.
    MySQL.update.await('UPDATE mdt_profiles SET callsign = ? WHERE citizenid = ?', { newCallsign, cid })

    if targetSrc then
        -- Mirror onto the live framework metadata (QBCore/Qbox/ESX) when online.
        ps.setMetadata(targetSrc, 'callsign', newCallsign)
        TriggerClientEvent(resourceName .. ':client:updateCallsign', targetSrc, newCallsign)
    end

    if ps.auditLog then
        ps.auditLog(src, 'callsign_changed', 'officer', cid, { callsign = newCallsign })
    end

    return { success = true, message = 'Callsign updated to ' .. newCallsign }
end)

-- Set Radio Frequency
ps.registerCallback(resourceName .. ':server:setRadio', function(source, payload)
    local src = source
    if not CheckAuth(src) then return { success = false, message = 'Unauthorized' } end

    payload = payload or {}
    local cid = payload.citizenid or payload.cid
    local newRadio = payload.radio or payload.newradio

    if not cid or not newRadio then
        return { success = false, message = 'Missing citizen ID or radio frequency' }
    end

    local targetSource = resolveSource(cid)
    if not targetSource then
        return { success = false, message = 'Officer must be online' }
    end

    -- Verify the officer actually carries a radio item, across inventories.
    local hasRadio = false
    if GetResourceState('ox_inventory') == 'started' then
        local count = exports.ox_inventory:GetItemCount(targetSource, 'radio')
        hasRadio = count and count > 0
    elseif QBCore then
        local Player = QBCore.Functions.GetPlayer(targetSource)
        hasRadio = Player and Player.Functions.GetItemByName('radio') ~= nil
    else
        -- Unknown inventory: don't block the frequency assignment.
        hasRadio = true
    end

    if not hasRadio then
        local firstname = ps.getCharInfo(targetSource, 'firstname') or ps.getPlayerName(targetSource) or 'Officer'
        return { success = false, message = firstname .. ' does not have a radio!' }
    end

    TriggerClientEvent(resourceName .. ':client:setRadio', targetSource, newRadio)
    return { success = true, message = 'Radio set to ' .. newRadio }
end)

-- Get Unit Location (GPS to officer)
ps.registerCallback(resourceName .. ':server:getUnitLocation', function(source, cid)
    if not CheckAuth(source) then return {} end
    if not cid then return {} end

    local targetSrc = resolveSource(cid)
    if targetSrc then
        local coords = GetEntityCoords(GetPlayerPed(targetSrc))
        return { x = coords.x, y = coords.y, z = coords.z }
    end

    return {}
end)
