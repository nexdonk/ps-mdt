--[[
    server/backend/phone.lua

    Centralised phone / number / email / SMS / mail access for the MDT.

    Every phone resource (lb-phone, qb-phone, npwd, gksphone, qs-smartphone,
    esx_phone, ...) stores a player's number differently — some in the
    framework player record (players.charinfo / users.phone_number), some in a
    dedicated table, and some only behind an export. Instead of hard-coding one
    of those, the MDT reads `Config.Phone` (see config.lua) and resolves its
    behaviour from the mapping defined there.

    The rest of the MDT only ever calls the helpers exposed here and never
    touches the phone tables / exports directly:

        Phone.GetNumber(citizenid)
            -> "5551234" | nil

        Phone.GetNumbersByOwners(citizenids)         (batched where possible)
            -> { [citizenid] = "5551234", ... }

        Phone.GetEmail(citizenid)
            -> "name@host.io" | nil

        Phone.SendSms(citizenid, fromNumber, body)
            -> true | false

        Phone.SendMail(citizenid, { subject, message, sender })
            -> true | false

    Every operation degrades gracefully: a missing table, a missing export or a
    misconfigured preset results in nil / false / {} and at most a ps.warn —
    never a SCRIPT ERROR.

    To switch phone systems you normally only change `Config.Phone.system`
    (or leave it on 'auto' to detect the running resource automatically).
--]]

Phone = Phone or {}

local resolvedSchema = nil
local schemaChecked = false

-- Only allow plain SQL identifiers (letters, digits, underscore). Table and
-- column names from the config are interpolated directly into the query
-- string, so this guards against a misconfigured Config.Phone turning into
-- SQL injection or a malformed query. JSON paths and bound values never go
-- through here — they ride on ? placeholders.
local function validIdent(name)
    return type(name) == 'string' and name ~= '' and name:match('^[%w_]+$') ~= nil
end

-- Quote a (pre-validated) identifier.
local function qq(name)
    return '`' .. name .. '`'
end

local function disable(reason)
    print(('[ps-mdt] [phone] %s — the phone feature is disabled. Check Config.Phone.'):format(reason))
    return nil
end

-- Run a SELECT, returning nil on error (handles a missing table gracefully).
local function safe(query, params)
    local ok, rows = pcall(MySQL.query.await, query, params)
    if not ok then
        if ps and ps.warn then ps.warn('[phone] Query failed: ' .. tostring(rows)) end
        return nil
    end
    return rows
end

-- Call an export method by dynamic name, emulating the colon syntax
-- (exports[res]:fn(...)) so it works for any resource. Returns
-- (false) on any failure / stopped resource, or (true, returnValue) on success.
-- Wrapped in pcall so a wrong signature degrades instead of erroring.
local function callExport(resource, fn, ...)
    if type(resource) ~= 'string' or type(fn) ~= 'string' then return false end
    if GetResourceState(resource) ~= 'started' then return false end
    local args = { ... }
    local exp = exports[resource]
    local ok, ret = pcall(function() return exp[fn](exp, table.unpack(args)) end)
    if not ok then
        if ps and ps.warn then
            ps.warn(('[phone] export %s:%s failed: %s'):format(resource, fn, tostring(ret)))
        end
        return false
    end
    return true, ret
end

-- Resolve a single number from a number-providing export. Most phones return a
-- plain string/number, but some (e.g. gksphone GetPhoneDataBySetupOwner) return
-- a table — in that case we read the .phone_number field off it.
local function resolveExportNumber(exp, ownerKey)
    if not exp or not exp.getNumberFn then return nil end
    local ok, ret = callExport(exp.resource, exp.getNumberFn, ownerKey)
    if not ok or ret == nil then return nil end
    if type(ret) == 'table' then
        local n = ret.phone_number or ret.number or ret.phoneNumber
        if n ~= nil and n ~= '' then return tostring(n) end
        return nil
    end
    if ret == '' then return nil end
    return tostring(ret)
end

-- Resolve the active schema from Config.Phone once and cache the result.
-- Returns nil when phone is disabled or no preset resolves (the MDT then simply
-- falls back to whatever number the SQL already provides instead of erroring).
local function getSchema()
    if schemaChecked then return resolvedSchema end
    schemaChecked = true
    resolvedSchema = nil

    local cfg = Config.Phone
    if type(cfg) ~= 'table' then return nil end   -- not configured -> silently off
    if cfg.enabled == false then return nil end   -- explicitly disabled -> silently off

    -- Resolve the system key. 'auto' (or nil) scans AutoDetect and uses the
    -- first preset whose resource is started, falling back to the 'default'
    -- charinfo preset when nothing matches. Note: AutoDetect is a map, so the
    -- scan order is not guaranteed — force `system` if you run several phones.
    local systemKey = cfg.system
    if systemKey == nil or systemKey == 'auto' then
        systemKey = nil
        if type(cfg.AutoDetect) == 'table' then
            for resource, presetKey in pairs(cfg.AutoDetect) do
                if GetResourceState(resource) == 'started' then
                    systemKey = presetKey
                    break
                end
            end
        end
        if systemKey == nil then systemKey = 'default' end
    end

    local preset = cfg.Presets and cfg.Presets[systemKey]
    if type(preset) ~= 'table' then
        return disable(('Unknown phone system "%s"'):format(tostring(systemKey)))
    end

    local schema = { system = systemKey }

    -- ---- number source ----------------------------------------------------
    -- Any source that fails validation simply leaves schema.numberSource unset:
    -- number lookups then return nil while sms/mail can still work on their own.
    local src = preset.numberSource
    if src == 'charinfo' then
        local t     = preset.table       or 'players'
        local owner = preset.ownerColumn or 'citizenid'
        local col   = preset.column      or 'charinfo'
        if validIdent(t) and validIdent(owner) and validIdent(col) then
            schema.numberSource = 'charinfo'
            schema.table        = t
            schema.ownerColumn  = owner
            schema.column       = col
            schema.path         = type(preset.path) == 'string' and preset.path or '$.phone'
        else
            print('[ps-mdt] [phone] Invalid "charinfo" number source — number lookups disabled.')
        end
    elseif src == 'table' then
        if validIdent(preset.table) and validIdent(preset.ownerColumn) and validIdent(preset.numberColumn) then
            schema.numberSource = 'table'
            schema.table        = preset.table
            schema.ownerColumn  = preset.ownerColumn
            schema.numberColumn = preset.numberColumn
        else
            print('[ps-mdt] [phone] Invalid "table" number source — number lookups disabled.')
        end
    elseif src == 'esx' then
        -- ESX: users.phone_number keyed by identifier (all fixed identifiers).
        schema.numberSource = 'esx'
        schema.table        = 'users'
        schema.ownerColumn  = 'identifier'
        schema.numberColumn = 'phone_number'
    elseif src == 'export' then
        local exp = preset.export
        if type(exp) == 'table' and type(exp.resource) == 'string' then
            -- getNumberFn may be absent (e.g. okokphone, unverified) — number
            -- lookups then no-op while sms/mail can still operate.
            schema.numberSource = 'export'
            schema.export       = { resource = exp.resource, getNumberFn = exp.getNumberFn }
        else
            print('[ps-mdt] [phone] Invalid "export" number source — number lookups disabled.')
        end
    elseif src ~= nil then
        print(('[ps-mdt] [phone] Unknown numberSource "%s" — number lookups disabled.'):format(tostring(src)))
    end

    -- ---- email (optional) -------------------------------------------------
    if type(preset.email) == 'table' then
        local e = preset.email
        if type(e.export) == 'table' and type(e.export.resource) == 'string'
            and type(e.export.getEmailFn) == 'string' then
            schema.email = { kind = 'export', resource = e.export.resource, getEmailFn = e.export.getEmailFn }
        elseif validIdent(e.table) and validIdent(e.ownerColumn) and validIdent(e.emailColumn) then
            schema.email = { kind = 'table', table = e.table, ownerColumn = e.ownerColumn, emailColumn = e.emailColumn }
        else
            print('[ps-mdt] [phone] Invalid "email" config in phone preset — email lookups disabled.')
        end
    end

    -- ---- sms (optional) ---------------------------------------------------
    if type(preset.sms) == 'table' then
        local s = preset.sms
        if type(s.export) == 'table' and type(s.export.resource) == 'string'
            and type(s.export.sendFn) == 'string' then
            schema.sms = { kind = 'export', resource = s.export.resource, sendFn = s.export.sendFn }
        elseif type(s.event) == 'table' and type(s.event.name) == 'string' then
            schema.sms = { kind = 'event', name = s.event.name, args = type(s.event.args) == 'table' and s.event.args or {} }
        else
            print('[ps-mdt] [phone] Invalid "sms" config in phone preset — SMS sending disabled.')
        end
    end

    -- ---- mail (optional) --------------------------------------------------
    if type(preset.mail) == 'table' then
        local m = preset.mail
        if type(m.export) == 'table' and type(m.export.resource) == 'string'
            and type(m.export.sendFn) == 'string' then
            schema.mail = { kind = 'export', resource = m.export.resource, sendFn = m.export.sendFn }
        elseif type(m.event) == 'table' and type(m.event.name) == 'string' then
            schema.mail = { kind = 'event', name = m.event.name }
        else
            print('[ps-mdt] [phone] Invalid "mail" config in phone preset — mail sending disabled.')
        end
    end

    resolvedSchema = schema
    return resolvedSchema
end

--- Map of citizenid -> phone number for the given citizenids. Batched into a
--- single query for the charinfo / table / esx sources; export sources loop
--- one call per id. Owners with no number are simply absent from the result.
--- @param citizenids string[]
--- @return table<string, string>
function Phone.GetNumbersByOwners(citizenids)
    local out = {}
    local schema = getSchema()
    if not schema or type(citizenids) ~= 'table' or #citizenids == 0 then
        return out
    end

    local src = schema.numberSource

    if src == 'charinfo' then
        local placeholders = {}
        for i = 1, #citizenids do placeholders[i] = '?' end
        local owner = qq(schema.ownerColumn)
        -- JSON path is bound as a value so it never needs identifier validation.
        local sql = ('SELECT %s AS owner, JSON_UNQUOTE(JSON_EXTRACT(%s, ?)) AS number FROM %s WHERE %s IN (%s)'):format(
            owner, qq(schema.column), qq(schema.table), owner, table.concat(placeholders, ',')
        )
        local params = { schema.path }
        for i = 1, #citizenids do params[#params + 1] = citizenids[i] end
        local rows = safe(sql, params) or {}
        for _, row in ipairs(rows) do
            if row.owner ~= nil and row.number ~= nil and row.number ~= '' then
                out[row.owner] = tostring(row.number)
            end
        end

    elseif src == 'table' or src == 'esx' then
        local placeholders = {}
        for i = 1, #citizenids do placeholders[i] = '?' end
        local owner = qq(schema.ownerColumn)
        local sql = ('SELECT %s AS owner, %s AS number FROM %s WHERE %s IN (%s)'):format(
            owner, qq(schema.numberColumn), qq(schema.table), owner, table.concat(placeholders, ',')
        )
        local rows = safe(sql, citizenids) or {}
        for _, row in ipairs(rows) do
            if row.owner ~= nil and row.number ~= nil and row.number ~= '' then
                out[row.owner] = tostring(row.number)
            end
        end

    elseif src == 'export' then
        for i = 1, #citizenids do
            local id = citizenids[i]
            local num = resolveExportNumber(schema.export, id)
            if num then out[id] = num end
        end
    end

    return out
end

--- A single citizen's phone number, or nil.
--- @param citizenid string
--- @return string|nil
function Phone.GetNumber(citizenid)
    local schema = getSchema()
    if not schema or not citizenid then return nil end
    if schema.numberSource == 'export' then
        return resolveExportNumber(schema.export, citizenid)
    end
    local map = Phone.GetNumbersByOwners({ citizenid })
    return map[citizenid]
end

--- A citizen's email address, or nil when not supported / not found.
--- @param citizenid string
--- @return string|nil
function Phone.GetEmail(citizenid)
    local schema = getSchema()
    if not schema or not citizenid or not schema.email then return nil end
    local e = schema.email

    if e.kind == 'table' then
        local sql = ('SELECT %s AS email FROM %s WHERE %s = ? LIMIT 1'):format(
            qq(e.emailColumn), qq(e.table), qq(e.ownerColumn)
        )
        local ok, row = pcall(MySQL.single.await, sql, { citizenid })
        if not ok then
            if ps and ps.warn then ps.warn('[phone] GetEmail failed: ' .. tostring(row)) end
            return nil
        end
        if row and row.email ~= nil and row.email ~= '' then return tostring(row.email) end
        return nil

    elseif e.kind == 'export' then
        -- getEmailFn is keyed by the player's NUMBER, so resolve that first.
        local number = Phone.GetNumber(citizenid)
        if not number then return nil end
        local ok, ret = callExport(e.resource, e.getEmailFn, number)
        if ok and ret ~= nil and ret ~= '' then return tostring(ret) end
        return nil
    end

    return nil
end

--- Send an SMS to a citizen from `fromNumber`. Returns false (never errors)
--- when SMS isn't supported, the target has no number, or the send fails.
--- @param citizenid string
--- @param fromNumber string
--- @param body string
--- @return boolean
function Phone.SendSms(citizenid, fromNumber, body)
    local schema = getSchema()
    if not schema or not citizenid or not schema.sms then return false end

    local toNumber = Phone.GetNumber(citizenid)
    if not toNumber then return false end

    local s = schema.sms
    if s.kind == 'export' then
        -- Standard positional signature: sendFn(from, to, body).
        local ok = callExport(s.resource, s.sendFn, fromNumber, toNumber, body)
        return ok == true

    elseif s.kind == 'event' then
        -- args is an ordered list of value keys mapped to positional TriggerEvent
        -- arguments (e.g. esx_phone:send -> { 'to', 'body' }).
        local valueByKey = { from = fromNumber, to = toNumber, body = body }
        local n = #s.args
        local args = {}
        for i = 1, n do args[i] = valueByKey[s.args[i]] end
        local ok = pcall(TriggerEvent, s.name, table.unpack(args, 1, n))
        return ok == true
    end

    return false
end

--- Send mail to a citizen. opts = { subject, message, sender }. Returns false
--- (never errors) when mail isn't supported or the send fails.
--- @param citizenid string
--- @param opts table
--- @return boolean
function Phone.SendMail(citizenid, opts)
    local schema = getSchema()
    if not schema or not citizenid or not schema.mail then return false end
    opts = type(opts) == 'table' and opts or {}

    local m = schema.mail
    if m.kind == 'export' then
        local payload = { sender = opts.sender, subject = opts.subject, message = opts.message }
        local ok
        if m.resource == 'lb-phone' then
            -- lb-phone SendMail takes a single object that carries the target
            -- number itself: SendMail({ to, sender, subject, message }).
            payload.to = Phone.GetNumber(citizenid)
            ok = callExport(m.resource, m.sendFn, payload)
        else
            -- qb-phone / gksphone style: sendFn(citizenid, { sender, subject, message }).
            ok = callExport(m.resource, m.sendFn, citizenid, payload)
        end
        return ok == true

    elseif m.kind == 'event' then
        local ok = pcall(TriggerEvent, m.name, citizenid, {
            sender  = opts.sender,
            subject = opts.subject,
            message = opts.message,
        })
        return ok == true
    end

    return false
end
