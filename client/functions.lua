-- Dispatch Functions --

-- Get Recent Dispatch Calls
function GetRecentDispatch()
    local resourceName = tostring(GetCurrentResourceName())
    local ok, result = pcall(function()
        return ps.callback(resourceName .. ':server:getRecentDispatches')
    end)
    if ok and result then
        return result
    end
    return {}
end

local function bootstrapProfile()
    -- Ensure an MDT profile exists for this character on (re)spawn.
    pcall(function() ps.callback('ps-mdt:hasProfile') end)
end

-- QBCore / Qbox
AddEventHandler('QBCore:Client:OnPlayerLoaded', bootstrapProfile)
-- ESX
AddEventHandler('esx:playerLoaded', bootstrapProfile)