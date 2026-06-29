Config = {}
ps = exports.ps_lib:init()

-- Basic Settings
Config.Debug = false -- Enable/disable debug mode (boolean)
Config.OnlyShowOnDuty = true -- Only allow the MDT to be opened when on duty (boolean)

-- Civilian Access Settings
Config.CivilianAccess = {
    enabled = true,   -- Allow civilians to open the MDT (profile + legislation view only)
    command = true,   -- Allow /mdt command for civilians
    showWarrants = true, -- Show active warrants on civilian profile
    showBolos = true,    -- Show active BOLOs on civilian profile
}

-- Time and Date Settings
Config.DateTime = {
    GameTime = true, -- If set to true, the game time will be used instead of the server time (boolean)
    TimeFormat = '24', -- Format for displaying time ('24' or '12')
    DateFormat = "MM-DD-YYYY" -- Format for displaying date (string: "MM-DD-YYYY", "DD-MM-YYYY", or "YYYY-MM-DD")
}

-- Department data sharing
Config.Sharing = {
    -- Mutual Sharing (Bidirectional)
    -- All departments in this group can see each other's data
    Mutual = {
        types = {
            'reports',
            'bodycams',
            'evidence',
            'bolos',
            'warrants'
        },
        departments = {
            'lspd',
            'bcso',
            'sahp'
        }
    },

    -- One-Way Sharing (Unidirectional)
    -- Viewers can see target department data, but not vice versa
    OneWay = {
        { -- Example: FIB and GOV 
            viewers = {
                'fib',
                'gov'
            },
            targets = {
                'lspd',
                'bcso',
                'sahp'
            },
            types = {
                'reports',
                'bodycams',
                'evidence',
                'bolos',
                'warrants',
            }
        },
    },
}

-- Keybinds
Config.Keys = {
    -- https://docs.fivem.net/docs/game-references/controls/ | Default QWERTY
    OpenMDT = {
        enabled = true, -- Enable/disable keybind (boolean)
        key = 'F11', -- Key to open MDT (string)
    },
}

-- Commands
Config.Commands = {
    Open = {
        enabled = true, -- Enable/disable command (boolean)
        command = 'mdt', -- Command to open MDT (string)
    },
    MessageOfTheDay = {
        enabled = true, -- Enable/disable command (boolean)
        command = 'motd', -- Command to set message of the day (string)
    },
}

-- Dispatch Settings
Config.Dispatch = {
    Resource = 'ps-dispatch',
    FilterByJob = true,
}

-- ============================================================================
--  Config.Housing — property/housing database integration for the MDT
-- ============================================================================
--  The MDT only ever calls Housing.GetCountsByOwners / GetByOwner / GetById
--  (server/backend/housing.lua). Those helpers build their queries from the
--  preset selected here, so no other file needs to know which housing script
--  is running.
--
--  HOW TO PICK A SYSTEM:
--    system = 'auto'  (default) -> the MDT scans AutoDetect below and uses the
--                                  first preset whose resource is 'started'.
--    system = 'qb-houses' (or any Presets key) -> force that exact preset and
--                                  skip auto-detection.
--    enabled = false  -> housing is silently disabled (no queries, no errors;
--                        the MDT just reports zero properties everywhere).
--
--  PRESET SHAPES (see housing.lua):
--    TABLE-based (preferred — works offline, no script dependency):
--      { table, columns = { owner, id, name, coords, keyholders },
--        join = { table, on = { left, right }, columns = { name, coords, ... } } }
--      Any column you omit is treated as NULL. `join` is optional and only used
--      by two-table systems (ownership row + a separate locations/catalog row).
--    EXPORT-based (only when there is no stable table — paid/encrypted scripts):
--      { export = { resource, countFn?, listFn?, getFn? } }
--      Missing functions degrade to empty/zero gracefully.
--
--  SECURITY: every table/column name below is validated (^[%w_]+$) and
--  backtick-quoted by housing.lua before it touches SQL. Owner values are
--  always bound through ? placeholders. Keep names to letters/digits/underscore.
Config.Housing = {
    enabled = true,
    system  = 'auto',

    -- resource folder name -> preset key. Ordered so the most specific /
    -- least-ambiguous schema wins when several happen to be present.
    AutoDetect = {
        ['ps-housing']             = 'ps-housing',
        ['qbx_properties']         = 'qbx_properties',
        ['qb-houses']              = 'qb-houses',
        ['qs-housing']             = 'qs-housing',
        ['origen_housing']         = 'origen_housing',
        ['bcs_housing']            = 'bcs_housing',
        ['loaf_housing']           = 'loaf_housing',
        ['esx_property']           = 'esx_property',
        ['esx_realestateagentjob'] = 'esx_realestateagentjob',
        ['nory_houses']            = 'nory_houses',
    },

    Presets = {
        -- qb-houses (QBCore). Ownership in player_houses; label/coords in
        -- houselocations (join on player_houses.house = houselocations.name).
        ['qb-houses'] = {
            table   = 'player_houses',
            columns = {
                owner      = 'citizenid',  -- ESX forks populate `identifier` instead
                id         = 'id',
                name       = 'house',      -- internal key; label comes from the join
                keyholders = 'keyholders', -- JSON array of identifiers
            },
            join = {
                table   = 'houselocations',
                on      = { left = 'house', right = 'name' },
                columns = { name = 'label', coords = 'coords' }, -- coords is JSON text
            },
        },

        -- ps-housing / ps-realtor (Project Sloth, QBCore/Qbox). Single table.
        -- No label column (derive from street) and no flat coords (parse door_data JSON).
        ['ps-housing'] = {
            table   = 'properties',
            columns = {
                owner      = 'owner_citizenid',
                id         = 'property_id',
                name       = 'street',      -- combine with region client-side for full address
                coords     = 'door_data',   -- JSON {x,y,z,h,length,width}
                keyholders = 'has_access',  -- JSON array of citizenids
            },
        },

        -- qbx_properties (Qbox). Single table; coords + keyholders are JSON.
        ['qbx_properties'] = {
            table   = 'properties',
            columns = {
                owner      = 'owner',
                id         = 'id',
                name       = 'property_name',
                coords     = 'coords',      -- JSON {x,y,z[,w]}
                keyholders = 'keyholders',  -- JSON object/array of citizenids
            },
        },

        -- qs-housing (Quasar). Inherits the qb-houses schema (player_houses +
        -- houselocations). VERIFY: encrypted source; on ESX builds the owner
        -- column is `identifier`, not `citizenid` — switch owner below if needed.
        ['qs-housing'] = {
            table   = 'player_houses',
            columns = {
                owner      = 'citizenid',
                id         = 'id',
                name       = 'house',
                keyholders = 'keyholders',
            },
            join = {
                table   = 'houselocations',
                on      = { left = 'house', right = 'name' },
                columns = { name = 'label', coords = 'coords' },
            },
        },

        -- esx_property (ESX). Ownership in owned_properties; label/coords in the
        -- `properties` catalog (join on name). No keyholders concept in vanilla.
        ['esx_property'] = {
            table   = 'owned_properties',
            columns = {
                owner = 'owner',  -- ESX identifier
                id    = 'id',
                name  = 'name',   -- internal name; friendly label comes from the join
            },
            join = {
                table   = 'properties',
                on      = { left = 'name', right = 'name' },
                columns = { name = 'label', coords = 'entering' }, -- entering is JSON {x,y,z,h}
            },
        },

        -- esx_realestateagentjob (ESX). Data actually lives in esx_property's
        -- owned_properties + properties tables (same schema as above).
        ['esx_realestateagentjob'] = {
            table   = 'owned_properties',
            columns = {
                owner = 'owner',  -- ESX identifier
                id    = 'id',
                name  = 'name',
            },
            join = {
                table   = 'properties',
                on      = { left = 'name', right = 'name' },
                columns = { name = 'label', coords = 'entering' },
            },
        },

        -- loaf_housing (loaf-scripts). Ownership only in loaf_properties.
        -- VERIFY: label/coords live in loaf_housing's Lua config (not SQL) and
        -- keyholders live in a separate resource (loaf_keysystem.loaf_keys),
        -- so only id + counts are available from SQL. owner is the ESX
        -- identifier (QBCore builds use citizenid).
        ['loaf_housing'] = {
            table   = 'loaf_properties',
            columns = {
                owner = 'owner',
                id    = 'propertyid',
            },
        },

        -- origen_housing (ESX/QBCore/Custom). VERIFY: framework SQL mirrors the
        -- qb-houses layout (player_houses + houselocations); on ESX the owner
        -- column is `identifier`. The script also exposes
        -- exports.origen_housing:getOwnedHouses(id) if you prefer an export
        -- preset instead of these tables.
        ['origen_housing'] = {
            table   = 'player_houses',
            columns = {
                owner      = 'citizenid',
                id         = 'id',
                name       = 'house',
                keyholders = 'keyholders',
            },
            join = {
                table   = 'houselocations',
                on      = { left = 'house', right = 'name' },
                columns = { name = 'label', coords = 'coords' },
            },
        },

        -- nory_houses. VERIFY: no public source — table/column names are
        -- best-guess conventions. Open the resource's .sql before relying on
        -- this; owner may be citizenid (QB) or identifier (ESX).
        ['nory_houses'] = {
            table   = 'nory_houses',
            columns = {
                owner      = 'owner',
                id         = 'id',
                name       = 'label',
                coords     = 'coords',
                keyholders = 'keyholders',
            },
        },

        -- bcs_housing (Bagus Code Studio) — PAID/encrypted, no stable table.
        -- EXPORT-based: GetOwnedHomes returns an array of Home objects
        -- (h.identifier, h.properties.name, h.properties.entry); keyholders are
        -- fetched separately. VERIFY: GetOwnedHomes may expect a player SOURCE
        -- rather than a citizenid/identifier — confirm against the install.
        ['bcs_housing'] = {
            export = {
                resource = 'bcs_housing',
                listFn   = 'GetOwnedHomes', -- (ownerOrSource) -> Home[]
                -- countFn omitted -> module counts #list
                -- getFn   omitted -> GetById returns nil for this system
            },
        },
    },
}

-- ============================================================================
--  Config.Phone — phone/number/email/SMS/mail integration for the MDT
-- ============================================================================
--  The MDT only ever calls the Phone helpers (server/backend/phone.lua):
--    Phone.GetNumber / GetNumbersByOwners / GetEmail / SendSms / SendMail.
--  Those build their behaviour from the preset selected here.
--
--  HOW TO PICK A SYSTEM:
--    system = 'auto' (default) -> scans AutoDetect and uses the first preset
--                                 whose resource is 'started'; if nothing
--                                 matches it falls back to the 'default' preset
--                                 (QBCore players.charinfo phone).
--    system = 'lb-phone' (or any Presets key) -> force that exact preset.
--    enabled = false -> phone integration silently off (numbers fall back to
--                       whatever the SQL already provides; no errors).
--
--  PRESET FIELDS (see phone.lua):
--    numberSource = 'charinfo' -> read players.charinfo JSON.
--                                  fields: table (def 'players'),
--                                  ownerColumn (def 'citizenid'),
--                                  column (def 'charinfo'), path (def '$.phone').
--                                  Batched with one JSON_EXTRACT IN(...) query.
--    numberSource = 'table'    -> { table, ownerColumn, numberColumn }. IN(...).
--    numberSource = 'esx'      -> read users.phone_number by identifier. IN(...).
--    numberSource = 'export'   -> { export = { resource, getNumberFn } }; per-id.
--    Optional sub-configs (each degrades to nil/false when absent or failing):
--      email = { table, ownerColumn, emailColumn }          -- table lookup
--           or { export = { resource, getEmailFn } }        -- getEmailFn(number)
--      sms   = { export = { resource, sendFn } }            -- sendFn(from,to,body)
--           or { event  = { name, args } }                  -- TriggerEvent(name, unpack(args))
--      mail  = { export = { resource, sendFn } }            -- sendFn(citizenid, opts)
--           or { event  = { name } }
--
--  SECURITY: table/column names are validated (^[%w_]+$) and backtick-quoted by
--  phone.lua; owner/number values are always bound via ? placeholders.
Config.Phone = {
    enabled = true,
    system  = 'auto',

    -- resource folder name -> preset key. Most specific first.
    AutoDetect = {
        ['lb-phone']           = 'lb-phone',
        ['qs-smartphone-pro']  = 'qs-smartphone',
        ['qs-smartphone']      = 'qs-smartphone',
        ['qs-smartphone-lite'] = 'qs-smartphone',
        ['gksphone']           = 'gksphone',
        ['yseries']            = 'yseries',
        ['roadphone-pro']      = 'roadphone',
        ['roadphone']          = 'roadphone',
        ['high-phone']         = 'high-phone',
        ['npwd']               = 'npwd',
        ['okokphone']          = 'okokphone',
        ['esx_phone']          = 'esx_phone',
        ['qb-phone']           = 'qb-phone',
    },

    Presets = {
        -- Default fallback: QBCore players.charinfo JSON ($.phone). Used when
        -- 'auto' resolves nothing. Keep this even on ESX — it is harmless if the
        -- column is missing (the query simply returns no rows).
        ['default'] = {
            numberSource = 'charinfo',
            table        = 'players',
            ownerColumn  = 'citizenid',
            column       = 'charinfo',
            path         = '$.phone',
        },

        -- qb-phone (QBCore). Number in players.charinfo. No email concept.
        -- Mail via offline export; no clean single-SMS API (omitted).
        ['qb-phone'] = {
            numberSource = 'charinfo',
            table        = 'players',
            ownerColumn  = 'citizenid',
            column       = 'charinfo',
            path         = '$.phone',
            mail = {
                export = { resource = 'qb-phone', sendFn = 'sendNewMailToOffline' }, -- (citizenid, {sender,subject,message})
            },
        },

        -- lb-phone (LB Scripts). Export-driven; works offline by identifier.
        ['lb-phone'] = {
            numberSource = 'export',
            export = { resource = 'lb-phone', getNumberFn = 'GetEquippedPhoneNumber' }, -- (citizenid) -> number
            email  = { export = { resource = 'lb-phone', getEmailFn = 'GetEmailAddress' } }, -- (number) -> email
            sms    = { export = { resource = 'lb-phone', sendFn = 'SendMessage' } },      -- (from, to, body)
            mail   = { export = { resource = 'lb-phone', sendFn = 'SendMail' } },         -- ({to,sender,subject,message})
        },

        -- npwd (Project Error). Number on the framework player table.
        -- VERIFY: bridged installs may remap to players/citizenid; default ESX
        -- config is users/identifier/phone_number.
        ['npwd'] = {
            numberSource = 'table',
            table        = 'users',
            ownerColumn  = 'identifier',
            numberColumn = 'phone_number',
            -- VERIFY: npwd's emitMessage takes a single OBJECT arg
            -- ({senderNumber,targetNumber,message}), not positional (from,to,body).
            sms = { export = { resource = 'npwd', sendFn = 'emitMessage' } },
            -- no email / mail support in npwd
        },

        -- gksphone (gkshop). Export-driven; offline by owner key.
        -- VERIFY: GetPhoneDataBySetupOwner returns a TABLE (read .phone_number),
        -- not a plain number string.
        ['gksphone'] = {
            numberSource = 'export',
            export = { resource = 'gksphone', getNumberFn = 'GetPhoneDataBySetupOwner' }, -- (ownerKey) -> {phone_number=...}
            sms  = { export = { resource = 'gksphone', sendFn = 'SendMessage' } },         -- (fromNumber, toNumber, message)
            mail = { export = { resource = 'gksphone', sendFn = 'SendNewMailOffline' } },  -- (ownerKey, {sender,subject,message,...})
        },

        -- yseries (TeamsGG YSeries / "yflip"). Export-driven.
        -- VERIFY: identifier lookup only resolves the player's PRIMARY phone.
        -- VERIFY: SendMail signature is (email, receiverType, receiver) — not the
        -- (citizenid, opts) shape, so the mail export may need a custom adapter.
        ['yseries'] = {
            numberSource = 'export',
            export = { resource = 'yseries', getNumberFn = 'GetPhoneNumberByIdentifier' }, -- (identifier) -> number
            sms  = { export = { resource = 'yseries', sendFn = 'SendMessageTo' } },         -- (from, to, message, attachments)
            mail = { export = { resource = 'yseries', sendFn = 'SendMail' } },              -- VERIFY arg shape
        },

        -- roadphone (RoadShop) — PAID/closed. Export-driven; offline by identifier.
        ['roadphone'] = {
            numberSource = 'export',
            export = { resource = 'roadphone', getNumberFn = 'getNumberFromIdentifier' }, -- (identifier) -> number
            -- VERIFY: sendMessage is documented as a CLIENT export; no server-only
            -- SMS export. May need to resolve target source first.
            sms  = { export = { resource = 'roadphone', sendFn = 'sendMessage' } },        -- (phoneNumber, message)
            mail = { export = { resource = 'roadphone', sendFn = 'sendMailOffline' } },    -- (identifier, {sender,subject,message})
        },

        -- high-phone (High Scripts) — PAID/escrow.
        -- VERIFY: getPlayerPhoneNumber takes a server SOURCE and is ONLINE-ONLY;
        -- there is no documented offline-by-identifier number lookup, so offline
        -- citizens will resolve to nil. Schema (hphone_*) columns are unknown.
        ['high-phone'] = {
            numberSource = 'export',
            export = { resource = 'high-phone', getNumberFn = 'getPlayerPhoneNumber' }, -- VERIFY: (source) online only
            email  = { export = { resource = 'high-phone', getEmailFn = 'getOfflinePlayerMailAccount' } }, -- VERIFY: (identifier) -> account
            sms    = { export = { resource = 'high-phone', sendFn = 'sendMessage' } },  -- VERIFY: takes {sender,recipient,content}
            mail   = { export = { resource = 'high-phone', sendFn = 'sendMail' } },     -- VERIFY: takes {sender,recipients,subject,content}
        },

        -- qs-smartphone (Quasar). Reads the framework player record.
        -- ESX (this project): users.phone_number by identifier. On QBCore use the
        -- 'default' charinfo preset instead. send APIs are PRO-only + online-only.
        ['qs-smartphone'] = {
            numberSource = 'esx',
            -- VERIFY: send exports exist only on qs-smartphone-pro and target an
            -- ONLINE player source, so offline delivery is not supported.
            sms  = { export = { resource = 'qs-smartphone-pro', sendFn = 'sendNewMessageFromApp' } }, -- (source, number, msg, app)
            mail = { export = { resource = 'qs-smartphone-pro', sendFn = 'sendNewMail' } },           -- (source, {sender,subject,message})
            -- no email-address resolution in qs-smartphone
        },

        -- esx_phone (official ESX phone). Number in users.phone_number.
        -- No email / mail. SMS via server event.
        ['esx_phone'] = {
            numberSource = 'esx',
            -- TriggerEvent('esx_phone:send', toNumber, body[, anon, position]).
            -- VERIFY: 'from' is derived from the calling source, not passed.
            sms = { event = { name = 'esx_phone:send', args = { 'to', 'body' } } },
        },

        -- okokphone (okokScripts) — PAID, multi-framework.
        -- VERIFY: NOTHING below is confirmed. No public docs/source expose the
        -- export names, event names or SQL schema. Open the installed resource
        -- (fxmanifest.lua + server/*.lua exports + sql/*.sql) and fill in
        -- getNumberFn / sms / mail before relying on this preset. As shipped it
        -- degrades to nil/false (no number, no send) rather than erroring.
        ['okokphone'] = {
            numberSource = 'export',
            export = { resource = 'okokphone' }, -- VERIFY: getNumberFn unknown — left unset
        },
    },
}

-- Wolfknight Plate Reader Settings
Config.UseWolfknightRadar = true -- Enable/disable Wolfknight radar integration
Config.WolfknightNotifyTime = 5000 -- Duration (ms) for plate reader notifications
Config.PlateScanForDriversLicense = true -- Check driver's license on plate scan

-- Fingerprint Settings
Config.FingerprintAutoFilled = false -- Auto-populate fingerprints on citizen profiles (if false, officers must manually add fingerprints)

-- Fingerprint Scan Integration
Config.FingerprintScan = {
    enabled = false,                                         -- Enable fingerprint scan trigger from MDT
    officerEvent = 'police:client:showFingerprint',          -- Client event triggered on the officer
    suspectEvent = 'police:client:showFingerprint',          -- Client event triggered on the suspect
}

-- Fuel Resource Name
Config.Fuel = 'LegacyFuel' -- Fuel resource name for vehicle fuel management

-- Weapon Registration
Config.RegisterWeaponsAutomatically = true -- Auto-register weapons on purchase (ox_inventory and qb-inventory/qb-weapons)
Config.RegisterCreatedWeapons = false -- Also auto-register weapons on item creation (ox_inventory only)

-- Impound Locations (vector4: x, y, z, heading)
Config.ImpoundLocations = {
    [1] = vector4(409.09, -1623.37, 29.29, 232.07), -- LSPD Impound
    [2] = vector4(-436.42, 5982.29, 31.34, 136.0),  -- Paleto Impound
}

-- Job Settings
-- NOTE (ESX): ESX jobs have no native "type" field. MDT access is granted by
-- matching the job NAME against the lists below (Config.PoliceJobs / DojJobs /
-- MedicalJobs), so make sure your ESX LEO/EMS/DOJ job names are listed here.
-- For job-type checks elsewhere, also map your ESX job names -> type in
-- ps_lib/Config.lua -> Config.ESXJobTypes.
Config.PoliceJobType = "leo"
Config.PoliceJobs = {
    'police',
    'lspd',
    'bcso',
    'sahp',
    'fib',
    'gov'
}

Config.DojJobType = "doj"
Config.DojJobs = {
    'lawyer',
    'judge',
}

Config.MedicalJobType = "ems"
Config.MedicalJobs = {
    'ambulance',
}

Config.Uploads = {
    MaxBytes = 5242880, -- 5 MB
    RateLimitPerMinute = 10, -- Max uploads per player per minute (0 = unlimited)
    AllowedAttachmentTypes = {
        'image/jpeg',
        'image/png',
        'image/webp',
        'application/pdf'
    },
    AllowedEvidenceImageTypes = {
        'image/jpeg',
        'image/png',
        'image/webp'
    }
}

-- Pagination Limits
Config.Pagination = {
    Citizens = 20, -- Citizens per page
    CitizenSearch = 20, -- Max citizen search results
    Cases = 20, -- Cases per page
}

-- Fine Processing
Config.Fines = {
    MaxAmount = 100000,   -- Maximum fine amount ($) to prevent economy exploits
    CooldownMs = 30000,   -- Anti-spam cooldown between fines (milliseconds)
}

-- Warrant Defaults
Config.Warrants = {
    DefaultExpiryDays = 7, -- Default warrant expiry when no date is provided
}

-- Dashboard Cache TTLs (seconds)
Config.CacheTTL = {
    ReportStats = 30,
    ActiveUnits = 10,
    UsageMetrics = 60,
}

-- Tablet Animation
Config.Animation = {
    Dict = 'amb@world_human_tourist_map@male@base',
    Name = 'base',
}

-- Mugshot Camera
Config.MugshotCamera = {
    DefaultFov = 50.0,
    FovMin = 15.0,
    FovMax = 80.0,
    FovSpeed = 5.0,
}

-- Security Camera Viewer
Config.CameraViewer = {
    RotationSpeed = 0.15,
    ZoomClamp = { min = 0.25, max = 10.0 },
    StartingZoom = 3.0,
    ZoomStep = 0.1,
    FovMin = 10.0,
    FovMax = 100.0,
    FovStep = 2.0,
}

-- Management permissions and defaults (per job grade)
Config.ManagementPermissions = {
    -- Citizens
    'citizens_search',
    'citizens_edit_licenses',
    -- BOLOs
    'bolos_view',
    'bolos_create',
    -- Vehicles
    'vehicles_search',
    'vehicles_edit_dmv',
    -- Weapons
    'weapons_search',
    -- Cases
    'cases_view',
    'cases_create',
    'cases_edit',
    'cases_delete',
    -- Evidence
    'evidence_view',
    'evidence_create',
    'evidence_transfer',
    'evidence_upload',
    -- Reports
    'reports_view',
    'reports_create',
    'reports_delete',
    -- Warrants
    'warrants_view',
    'warrants_issue',
    'warrants_close',
    -- Charges
    'charges_view',
    'charges_edit',
    -- Dispatch
    'dispatch_attach',
    'dispatch_route',
    -- Cameras & Bodycams
    'cameras_view',
    'bodycams_view',
    -- Notes
    'notes_edit_department',
    -- Roster
    'roster_manage_certifications',
    'roster_manage_officers',
    -- PPR
    'ppr_view',
    'ppr_manage',
    -- FTO
    'fto_view',
    'fto_manage',
    -- Management
    'management_permissions',
    'management_bulletins',
    'management_activity',
}

-- Framework auto-detection (used for sensible per-framework defaults below).
local IsESX = GetResourceState('es_extended') == 'started'

-- Bodycam Settings (override defaults if needed, remove to use built-in defaults)
-- The defaults below auto-switch based on the detected framework:
--   QBCore/Qbox -> listens to the native QBCore duty event.
--   ESX         -> uses ps_lib ('pslib') mode. ESX has NO native server-side
--                  duty event, so to auto-create bodycams on duty changes you
--                  must TriggerEvent('ps_lib:server:dutyChanged', src, jobName, onDuty)
--                  from your duty/job system. Bodycam VIEWING works regardless.
Config.Bodycam = {
    DutyEvent = IsESX and 'ps_lib:server:dutyChanged' or 'QBCore:Server:OnJobUpdate',
    DutyEventMode = IsESX and 'pslib' or 'qbcore',
    MultiJobDutyEvent = 'ps-multijob:server:dutyChanged',
    DutyResource = IsESX and 'es_extended' or 'qb-core',
    MultiJobResource = 'ps-multijob',
}

-- Sentencing / Jail integration.
-- The MDT "Send to Jail" action writes 'injail' / 'criminalrecord' metadata
-- (works on QBCore/Qbox/ESX) and then triggers your jail script:
--   ClientEvent  -> TriggerClientEvent on the target (QBCore default below).
--   ServerEvent  -> optional server event for ESX jail scripts
--                   (e.g. 'esx_jail:sendToJail') -> TriggerEvent(ServerEvent, src, time).
--   TimeMultiplier -> converts the MDT sentence (months) into your jail's unit
--                     (e.g. set to 60 if your jail expects seconds).
Config.Jail = {
    ClientEvent = IsESX and '' or 'police:client:SendToJail',
    ServerEvent = nil,
    TimeMultiplier = 1,
}

-- Optional defaults for role permissions by job/grade
-- Example:
-- Config.PermissionDefaults = {
--     police = {
--         ['0'] = { 'access_reports' },
--         ['1'] = { 'access_reports', 'view_bodycams' },
--     }
-- }
Config.PermissionDefaults = Config.PermissionDefaults or {}

-- HIGHLY recommended not tuse this natively. Use FiveManage for this.
-- Activity Tracking - Controls which actions are logged to the audit trail
-- Categories can be toggled on/off from the Settings page in the MDT
-- These are the DEFAULT values; runtime changes are stored in the mdt_settings table
Config.AuditTracking = {
    authentication = true,   -- Login/logout events
    reports = true,          -- Report create, update, delete
    cases = true,            -- Case CRUD, officer assignments, attachments
    evidence = true,         -- Evidence CRUD, transfers, images
    warrants = true,         -- Warrant issued/closed
    vehicles = true,         -- Vehicle updates, impound/release
    weapons = true,          -- Weapon create, update, delete
    charges = true,          -- Fines processed, charges updated
    searches = false,        -- Citizen/player/officer searches (high volume)
    dispatch = true,         -- Signal 100 activate/deactivate
    officers = true,         -- Callsign changes
    sentencing = true,       -- Jail sentencing
    arrests = true,          -- Arrest logging
    icu = true,              -- ICU record deletion
    cameras = true,          -- Security camera access
    bodycams = true,         -- Officer bodycam access
}

-- Camera models available for static camera placement
Config.CameraModels = {
    ['security_cam_01'] = 'v_serv_securitycam_1a',
    ['security_cam_02'] = 'v_serv_securitycam_03',
    ['security_cam_03'] = 'ba_prop_battle_cctv_cam_01a',
    ['security_cam_04'] = 'prop_cctv_cam_06a',
    ['security_cam_05'] = 'ba_prop_battle_cctv_cam_01b',
    ['security_cam_06'] = 'prop_cctv_cam_01b',
    ['security_cam_07'] = 'ch_prop_ch_cctv_cam_02a',
    ['security_cam_08'] = 'prop_cctv_cam_04c',
    ['security_cam_09'] = 'prop_cctv_cam_03a',
    ['security_cam_10'] = 'ch_prop_ch_cctv_cam_01a',
    ['security_cam_11'] = 'prop_cctv_cam_01a',
    ['security_cam_12'] = 'prop_cctv_cam_05a',
    ['security_cam_13'] = 'prop_cctv_cam_07a',
    ['security_cam_14'] = 'prop_cctv_cam_04b',
    ['security_cam_15'] = 'tr_prop_tr_camhedz_cctv_01a',
    ['security_cam_16'] = 'prop_cctv_cam_02a',
    ['security_cam_17'] = 'prop_cctv_cam_04a',
    ['cctv_cam_01'] = 'm24_1_prop_m24_1_carrier_bank_cctv_02',
    ['cctv_cam_02'] = 'xm_prop_x17_cctv_01a',
    ['cctv_cam_03'] = 'prop_cctv_pole_02',
    ['cctv_cam_04'] = 'm24_1_prop_m24_1_carrier_bank_cctv_01',
    ['cctv_cam_05'] = 'prop_cctv_pole_04',
    ['cctv_cam_06'] = 'xm_prop_x17_server_farm_cctv_01',
    ['cctv_cam_07'] = 'prop_cctv_pole_03',
    ['cctv_cam_08'] = 'p_cctv_s',
    ['cctv_cam_09'] = 'hei_prop_bank_cctv_02',
}
