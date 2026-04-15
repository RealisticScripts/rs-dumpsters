local currentVersion = 'v1.0.0'

local function fetchLatestVersion(callback)
    PerformHttpRequest('https://api.github.com/repos/RealisticScripts/rs-dumpsters/releases/latest', function(statusCode, response)
        if statusCode == 200 then
            local data = json.decode(response)
            if data and data.tag_name then
                callback(data.tag_name)
            else
                print('[rs-dumpsters] Failed to fetch the latest version')
            end
        else
            print(('[rs-dumpsters] HTTP request failed with status code: %s'):format(statusCode))
        end
    end, 'GET')
end

local function checkForUpdates()
    fetchLatestVersion(function(latestVersion)
        if currentVersion ~= latestVersion then
            print('[rs-dumpsters] A new version of the script is available!')
            print(('[rs-dumpsters] Current version: %s'):format(currentVersion))
            print(('[rs-dumpsters] Latest version: %s'):format(latestVersion))
            print('[rs-dumpsters] Please update the script from: https://github.com/RealisticScripts/rs-dumpsters')
        else
            print('[rs-dumpsters] Your script is up to date!')
        end
    end)
end

checkForUpdates()

local ResourceName = GetCurrentResourceName()
local InventoryBackend = nil
local QBCore = nil
local RegisteredStashes = {}
local DumpsterCooldowns = {}
local DumpsterOccupants = {}
local PlayerOccupancy = {}
local PersistedStashes = {}
local PersistenceState = {
    attempted = false,
    ready = false,
    warned = false
}

local function debugPrint(message, data)
    if not Config.Debug then return end

    if data ~= nil then
        print(('[%s][SERVER] %s %s'):format(ResourceName, message, json.encode(data)))
        return
    end

    print(('[%s][SERVER] %s'):format(ResourceName, message))
end

local function sendClientNotify(target, description, notifyType)
    TriggerClientEvent('rs-dumpsters:client:notify', target, description, notifyType)
end

local function getPlayerIdentifier(source)
    return GetPlayerIdentifierByType(source, 'license') or GetPlayerIdentifierByType(source, 'steam') or GetPlayerIdentifierByType(source, 'discord') or 'unknown'
end

local function round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor((value * power) + 0.5) / power
end

local function normalizeDumpsterPayload(payload)
    if type(payload) ~= 'table' or type(payload.coords) ~= 'table' then
        return nil
    end

    local model = tonumber(payload.model)
    local x = tonumber(payload.coords.x)
    local y = tonumber(payload.coords.y)
    local z = tonumber(payload.coords.z)

    if not model or not x or not y or not z then
        return nil
    end

    return {
        model = model,
        coords = {
            x = round(x, 2),
            y = round(y, 2),
            z = round(z, 2)
        }
    }
end

local function buildDumpsterId(payload)
    local normalized = normalizeDumpsterPayload(payload)
    if not normalized then return nil end

    return ('dumpster_%s_%s_%s_%s'):format(
        normalized.model,
        normalized.coords.x,
        normalized.coords.y,
        normalized.coords.z
    ):gsub('[-.]', '_')
end

local function hasDatabaseLayer()
    return type(MySQL) == 'table' and type(MySQL.query) == 'table' and type(MySQL.query.await) == 'function'
end

local function trackPersistedStash(stashId, payload)
    local normalized = normalizeDumpsterPayload(payload)
    if not stashId or not normalized then return end

    PersistedStashes[stashId] = {
        model = normalized.model,
        coords = {
            x = normalized.coords.x,
            y = normalized.coords.y,
            z = normalized.coords.z
        }
    }
end

local function registerBackendStash(stashId)
    if RegisteredStashes[stashId] then return true end

    if InventoryBackend == 'ox_inventory' then
        exports.ox_inventory:RegisterStash(stashId, Config.StashLabel, Config.StashSlots, Config.StashMaxWeight, nil, nil, nil)
        RegisteredStashes[stashId] = true
        return true
    end

    if InventoryBackend == 'qb-inventory' then
        exports['qb-inventory']:CreateInventory(stashId, {
            label = Config.StashLabel,
            maxweight = Config.StashMaxWeight,
            slots = Config.StashSlots
        })
        RegisteredStashes[stashId] = true
        return true
    end

    return false
end

local function ensurePersistedStashesRegistered()
    if not InventoryBackend then return end

    local restored = 0

    for stashId in pairs(PersistedStashes) do
        if not RegisteredStashes[stashId] and registerBackendStash(stashId) then
            restored = restored + 1
        end
    end

    if restored > 0 then
        debugPrint('Registered persisted dumpster stashes for active inventory backend', {
            backend = InventoryBackend,
            restored = restored
        })
    end
end

local function initialisePersistence()
    if PersistenceState.ready then
        return true
    end

    PersistenceState.attempted = true

    if not hasDatabaseLayer() then
        if not PersistenceState.warned then
            PersistenceState.warned = true
            debugPrint('Database layer not detected; dumpster stash persistence registry is unavailable until MySQL is ready')
        end
        return false
    end

    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS rs_dumpsters_stashes (
                stash_id VARCHAR(128) NOT NULL,
                model BIGINT NOT NULL,
                x DECIMAL(10,2) NOT NULL,
                y DECIMAL(10,2) NOT NULL,
                z DECIMAL(10,2) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (stash_id)
            )
        ]])

        local rows = MySQL.query.await('SELECT stash_id, model, x, y, z FROM rs_dumpsters_stashes') or {}
        for i = 1, #rows do
            PersistedStashes[rows[i].stash_id] = {
                model = tonumber(rows[i].model) or rows[i].model,
                coords = {
                    x = tonumber(rows[i].x) or rows[i].x,
                    y = tonumber(rows[i].y) or rows[i].y,
                    z = tonumber(rows[i].z) or rows[i].z
                }
            }
        end

        PersistenceState.ready = true
        debugPrint('Dumpster stash persistence initialised', { loaded = #rows })
    end)

    if not ok then
        PersistenceState.ready = false
        debugPrint('Failed to initialise dumpster stash persistence', { error = tostring(err) })
        return false
    end

    ensurePersistedStashesRegistered()
    return true
end

local function persistDumpsterStash(payload)
    local normalized = normalizeDumpsterPayload(payload)
    if not normalized then
        return nil, false
    end

    local stashId = buildDumpsterId(normalized)
    trackPersistedStash(stashId, normalized)

    if not PersistenceState.ready then
        initialisePersistence()
    end

    if not PersistenceState.ready then
        return stashId, false
    end

    local ok, err = pcall(function()
        MySQL.query.await([=[
            INSERT INTO rs_dumpsters_stashes (stash_id, model, x, y, z)
            VALUES (?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE
                model = VALUES(model),
                x = VALUES(x),
                y = VALUES(y),
                z = VALUES(z),
                updated_at = CURRENT_TIMESTAMP
        ]=], {
            stashId,
            normalized.model,
            normalized.coords.x,
            normalized.coords.y,
            normalized.coords.z
        })
    end)

    if not ok then
        debugPrint('Failed to persist dumpster stash registry record', {
            stashId = stashId,
            error = tostring(err)
        })
        return stashId, false
    end

    return stashId, true
end

local function detectInventory()
    if GetResourceState('ox_inventory') == 'started' then
        InventoryBackend = 'ox_inventory'
        debugPrint('Detected ox_inventory backend')
        ensurePersistedStashesRegistered()
        return
    end

    if GetResourceState('qb-inventory') == 'started' and GetResourceState('qb-core') == 'started' then
        QBCore = exports['qb-core']:GetCoreObject()
        InventoryBackend = 'qb-inventory'
        debugPrint('Detected qb-inventory backend')
        ensurePersistedStashesRegistered()
        return
    end

    InventoryBackend = nil
    debugPrint('No supported inventory backend detected')
end

local function addInventoryItem(source, itemName, amount)
    if InventoryBackend == 'ox_inventory' then
        local success = exports.ox_inventory:AddItem(source, itemName, amount)
        return success == true or success == amount
    end

    if InventoryBackend == 'qb-inventory' then
        return exports['qb-inventory']:AddItem(source, itemName, amount, false, false, 'rs-dumpsters:loot')
    end

    return false
end

local function canCarryInventoryItem(source, itemName, amount)
    if InventoryBackend == 'ox_inventory' then
        local canCarry = exports.ox_inventory:CanCarryItem(source, itemName, amount)
        return canCarry == true
    end

    if InventoryBackend == 'qb-inventory' then
        return exports['qb-inventory']:CanAddItem(source, itemName, amount)
    end

    return false
end

local function ensureStashRegistered(stashId)
    return registerBackendStash(stashId)
end

local function openStash(source, stashId)
    if InventoryBackend == 'ox_inventory' then
        exports.ox_inventory:forceOpenInventory(source, 'stash', stashId)
        return true
    end

    if InventoryBackend == 'qb-inventory' then
        exports['qb-inventory']:OpenInventory(source, stashId, {
            label = Config.StashLabel,
            maxweight = Config.StashMaxWeight,
            slots = Config.StashSlots
        })
        return true
    end

    return false
end

local function sendDiscordLog(title, description, fields, color)
    if not Config.DiscordWebhook or Config.DiscordWebhook == '' then return end

    local embed = {
        {
            title = title,
            description = description,
            color = color or 3145656,
            fields = fields or {},
            footer = {
                text = ('%s | %s'):format(ResourceName, os.date('%Y-%m-%d %H:%M:%S'))
            }
        }
    }

    PerformHttpRequest(Config.DiscordWebhook, function() end, 'POST', json.encode({ username = 'rs-dumpsters', embeds = embed }), {
        ['Content-Type'] = 'application/json'
    })
end

local function rollLoot()
    local totalWeight = 0
    for i = 1, #Config.LootTable do
        totalWeight = totalWeight + (Config.LootTable[i].chance or 0)
    end

    local failThreshold = totalWeight + Config.LootFailChance
    local roll = math.random(1, failThreshold)

    if roll > totalWeight then
        return nil
    end

    local cumulative = 0
    for i = 1, #Config.LootTable do
        cumulative = cumulative + (Config.LootTable[i].chance or 0)
        if roll <= cumulative then
            local entry = Config.LootTable[i]
            return entry, math.random(entry.amount.min, entry.amount.max)
        end
    end

    return nil
end

local function clearOccupancyForSource(source)
    local dumpsterId = PlayerOccupancy[source]
    if not dumpsterId then return end

    PlayerOccupancy[source] = nil
    DumpsterOccupants[dumpsterId] = nil
end

local function bootstrapPersistenceAndInventory()
    if GetResourceState('oxmysql') ~= 'started' then
        debugPrint('oxmysql is not started; auto SQL and dumpster stash registry persistence are unavailable')
    end

    if type(MySQL) == 'table' and type(MySQL.ready) == 'function' then
        MySQL.ready(function()
            initialisePersistence()
            detectInventory()
        end)
        return
    end

    initialisePersistence()
    detectInventory()
end

CreateThread(function()
    Wait(500)
    bootstrapPersistenceAndInventory()
end)

AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= ResourceName and resourceName ~= 'ox_inventory' and resourceName ~= 'qb-inventory' and resourceName ~= 'qb-core' and resourceName ~= 'oxmysql' then return end

    SetTimeout(500, function()
        if resourceName == ResourceName or resourceName == 'oxmysql' then
            bootstrapPersistenceAndInventory()
            return
        end

        detectInventory()
    end)
end)

RegisterNetEvent('rs-dumpsters:server:lootDumpster', function(payload)
    local src = source

    payload = normalizeDumpsterPayload(payload)
    if not payload then
        sendClientNotify(src, 'Invalid dumpster payload received.', 'error')
        return
    end

    if not InventoryBackend then
        sendClientNotify(src, 'No supported inventory backend is running.', 'error')
        return
    end

    local dumpsterId = buildDumpsterId(payload)
    local cooldownExpires = DumpsterCooldowns[dumpsterId]

    if cooldownExpires and cooldownExpires > os.time() then
        sendClientNotify(src, ('This dumpster has already been searched. Try again in %ss.'):format(cooldownExpires - os.time()), 'warning')
        return
    end

    local entry, amount = rollLoot()
    DumpsterCooldowns[dumpsterId] = os.time() + Config.LootCooldownSeconds

    if not entry then
        sendClientNotify(src, 'You searched the dumpster but found nothing useful.', 'inform')
        debugPrint('Dumpster search returned no loot', { source = src, dumpsterId = dumpsterId })

        sendDiscordLog(
            'Dumpster Loot',
            'A dumpster was searched with no reward.',
            {
                { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(src) or 'Unknown', src), inline = true },
                { name = 'Identifier', value = getPlayerIdentifier(src), inline = false },
                { name = 'Dumpster', value = dumpsterId, inline = false }
            },
            8359053
        )
        return
    end

    if not canCarryInventoryItem(src, entry.item, amount) then
        DumpsterCooldowns[dumpsterId] = nil
        sendClientNotify(src, 'You do not have enough inventory space for that loot.', 'error')
        return
    end

    local added = addInventoryItem(src, entry.item, amount)
    if not added then
        DumpsterCooldowns[dumpsterId] = nil
        sendClientNotify(src, 'Failed to add the loot item. Check your item registry.', 'error')
        debugPrint('Failed to add loot item', { source = src, item = entry.item, amount = amount, backend = InventoryBackend })
        return
    end

    sendClientNotify(src, ('You found %sx %s.'):format(amount, entry.item), 'success')
    debugPrint('Loot awarded', { source = src, item = entry.item, amount = amount, dumpsterId = dumpsterId })

    sendDiscordLog(
        'Dumpster Loot',
        'A player looted a dumpster.',
        {
            { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(src) or 'Unknown', src), inline = true },
            { name = 'Identifier', value = getPlayerIdentifier(src), inline = false },
            { name = 'Dumpster', value = dumpsterId, inline = false },
            { name = 'Loot', value = ('%sx %s'):format(amount, entry.item), inline = true },
            { name = 'Inventory', value = InventoryBackend, inline = true }
        },
        5763719
    )
end)

RegisterNetEvent('rs-dumpsters:server:openStash', function(payload)
    local src = source

    payload = normalizeDumpsterPayload(payload)
    if not payload then
        sendClientNotify(src, 'Invalid dumpster payload received.', 'error')
        return
    end

    if not InventoryBackend then
        sendClientNotify(src, 'No supported inventory backend is running.', 'error')
        return
    end

    local stashId, persisted = persistDumpsterStash(payload)

    if not ensureStashRegistered(stashId) then
        sendClientNotify(src, 'Failed to register the dumpster stash.', 'error')
        return
    end

    if not openStash(src, stashId) then
        sendClientNotify(src, 'Failed to open the dumpster stash.', 'error')
        return
    end

    debugPrint('Opened dumpster stash', {
        source = src,
        stashId = stashId,
        backend = InventoryBackend,
        persisted = persisted
    })

    sendDiscordLog(
        'Dumpster Stash',
        'A player opened a dumpster stash.',
        {
            { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(src) or 'Unknown', src), inline = true },
            { name = 'Identifier', value = getPlayerIdentifier(src), inline = false },
            { name = 'Stash', value = stashId, inline = false },
            { name = 'Inventory', value = InventoryBackend, inline = true },
            { name = 'Persistent Registry', value = persisted and 'Yes' or 'Pending / unavailable', inline = true }
        },
        3447003
    )
end)

RegisterNetEvent('rs-dumpsters:server:enterDumpster', function(payload)
    local src = source

    payload = normalizeDumpsterPayload(payload)
    if not payload then
        sendClientNotify(src, 'Invalid dumpster payload received.', 'error')
        return
    end

    local dumpsterId = buildDumpsterId(payload)
    local occupiedBy = DumpsterOccupants[dumpsterId]

    if occupiedBy and occupiedBy ~= src then
        sendClientNotify(src, 'Someone is already hiding in that dumpster.', 'error')
        return
    end

    if PlayerOccupancy[src] and PlayerOccupancy[src] ~= dumpsterId then
        clearOccupancyForSource(src)
    end

    DumpsterOccupants[dumpsterId] = src
    PlayerOccupancy[src] = dumpsterId

    TriggerClientEvent('rs-dumpsters:client:hideApproved', src, {
        id = dumpsterId,
        coords = payload.coords,
        model = payload.model
    })

    debugPrint('Player entered dumpster', { source = src, dumpsterId = dumpsterId })

    sendDiscordLog(
        'Dumpster Hide',
        'A player hid inside a dumpster.',
        {
            { name = 'Player', value = ('%s (%s)'):format(GetPlayerName(src) or 'Unknown', src), inline = true },
            { name = 'Identifier', value = getPlayerIdentifier(src), inline = false },
            { name = 'Dumpster', value = dumpsterId, inline = false }
        },
        10181046
    )
end)

RegisterNetEvent('rs-dumpsters:server:leaveDumpster', function()
    local src = source
    local dumpsterId = PlayerOccupancy[src]

    if not dumpsterId then return end

    clearOccupancyForSource(src)
    debugPrint('Player left dumpster', { source = src, dumpsterId = dumpsterId })
end)

AddEventHandler('playerDropped', function()
    clearOccupancyForSource(source)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= ResourceName then return end

    for source, dumpsterId in pairs(PlayerOccupancy) do
        TriggerClientEvent('rs-dumpsters:client:forceLeaveDumpster', source, 'The dumpster system stopped and released your hide state.')
        debugPrint('Force released player occupancy on resource stop', { source = source, dumpsterId = dumpsterId })
    end
end)
