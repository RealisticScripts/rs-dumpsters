local ResourceName = GetCurrentResourceName()
local HiddenState = {
    active = false,
    dumpsterId = nil,
    entity = nil,
    coords = nil,
    heading = nil,
    camera = nil
}

local TargetBackend = nil
local DumpsterModelLookup = {}

for i = 1, #Config.DumpsterModels do
    DumpsterModelLookup[joaat(Config.DumpsterModels[i])] = true
end

local function debugPrint(message, data)
    if not Config.Debug then return end

    if data ~= nil then
        print(('[%s][CLIENT] %s %s'):format(ResourceName, message, json.encode(data)))
        return
    end

    print(('[%s][CLIENT] %s'):format(ResourceName, message))
end

local function notify(description, notifyType)
    lib.notify({
        title = Config.NotificationTitle,
        description = description,
        type = notifyType or 'inform'
    })
end

local function round(value, decimals)
    local power = 10 ^ (decimals or 0)
    return math.floor((value * power) + 0.5) / power
end

local function getDumpsterPayload(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local model = GetEntityModel(entity)
    if not DumpsterModelLookup[model] then return nil end

    local coords = GetEntityCoords(entity)

    return {
        model = model,
        coords = {
            x = round(coords.x, 2),
            y = round(coords.y, 2),
            z = round(coords.z, 2)
        }
    }
end

local function canInteractWithDumpster(entity)
    if HiddenState.active then return false end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return false end

    local model = GetEntityModel(entity)
    if not DumpsterModelLookup[model] then return false end

    local playerCoords = GetEntityCoords(PlayerPedId())
    local entityCoords = GetEntityCoords(entity)
    return #(playerCoords - entityCoords) <= Config.InteractionDistance
end

local function deleteHideCamera()
    if HiddenState.camera and DoesCamExist(HiddenState.camera) then
        RenderScriptCams(false, true, 250, true, true)
        DestroyCam(HiddenState.camera, false)
    end

    HiddenState.camera = nil
end

local function getDumpsterOffset(entity, forwardDistance, height, lateralDistance)
    return GetOffsetFromEntityInWorldCoords(entity, lateralDistance or 0.0, forwardDistance, height or 0.0)
end

local function getDumpsterInteriorOffset(entity)
    return GetOffsetFromEntityInWorldCoords(entity, 0.0, 0.0, Config.HideEnterOffset.z)
end

local function getGroundAdjustedCoords(coords)
    if not coords then return nil end

    local foundGround, groundZ = GetGroundZFor_3dCoord(coords.x, coords.y, coords.z + 1.0, false)
    if foundGround then
        return vec3(coords.x, coords.y, groundZ + 0.03)
    end

    return vec3(coords.x, coords.y, coords.z)
end

local function isExitSpotUsable(coords)
    local adjusted = getGroundAdjustedCoords(coords)
    if not adjusted then
        return false, nil
    end

    local occupied = IsPositionOccupied(adjusted.x, adjusted.y, adjusted.z, 0.65, false, true, false, false, false, 0, false)
    return not occupied, adjusted
end

local function createHideCamera(entity)
    deleteHideCamera()

    local camCoords = getDumpsterOffset(entity, -3.55, 1.45, 0.0)
    local lookCoords = getDumpsterOffset(entity, -0.10, 0.95, 0.0)
    local camera = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)

    SetCamCoord(camera, camCoords.x, camCoords.y, camCoords.z)
    PointCamAtCoord(camera, lookCoords.x, lookCoords.y, lookCoords.z)
    SetCamFov(camera, 58.0)
    SetCamActive(camera, true)
    RenderScriptCams(true, true, 250, true, true)

    HiddenState.camera = camera
end

local function findExitCoords(entity)
    local entityCoords = GetEntityCoords(entity)
    local candidateOffsets = {
        { forward = -1.55, lateral = 0.0 },
        { forward = -1.95, lateral = 0.0 },
        { forward = 0.0, lateral = -1.25 },
        { forward = 0.0, lateral = 1.25 },
        { forward = 1.55, lateral = 0.0 }
    }

    for i = 1, #candidateOffsets do
        local candidate = getDumpsterOffset(entity, candidateOffsets[i].forward, Config.HideExitOffset.z, candidateOffsets[i].lateral)
        local usable, adjusted = isExitSpotUsable(candidate)
        if usable then
            return adjusted
        end
    end

    return vec3(entityCoords.x, entityCoords.y, entityCoords.z + Config.HideExitOffset.z)
end

local function setPlayerHidden(state, entity, payload)
    local ped = PlayerPedId()

    if state then
        local dumpsterCoords = GetEntityCoords(entity)
        local interiorCoords = getDumpsterInteriorOffset(entity)

        HiddenState.active = true
        HiddenState.dumpsterId = payload.id
        HiddenState.entity = entity
        HiddenState.coords = dumpsterCoords
        HiddenState.heading = GetEntityHeading(entity)

        SetEntityCoordsNoOffset(ped, interiorCoords.x, interiorCoords.y, interiorCoords.z, false, false, false)
        SetEntityHeading(ped, HiddenState.heading + Config.HideHeadingOffset)
        FreezeEntityPosition(ped, true)
        SetEntityVisible(ped, false, false)
        SetEntityCollision(ped, false, false)
        SetEntityInvincible(ped, true)
        createHideCamera(entity)

        if GetResourceState('ox_target') == 'started' then
            exports.ox_target:disableTargeting(true)
        end

        notify(('You are hiding inside the dumpster. Press [%s] to get out.'):format('E'), 'success')
        debugPrint('Player entered dumpster hide state', payload)
        return
    end

    if not HiddenState.active then return end

    local exitEntity = HiddenState.entity and DoesEntityExist(HiddenState.entity) and HiddenState.entity or nil
    local exitCoords = exitEntity and findExitCoords(exitEntity) or (HiddenState.coords and vec3(HiddenState.coords.x, HiddenState.coords.y, HiddenState.coords.z + Config.HideExitOffset.z)) or GetEntityCoords(ped)
    local exitHeading = exitEntity and (GetEntityHeading(exitEntity) + 180.0) or GetEntityHeading(ped)

    deleteHideCamera()
    SetEntityCoordsNoOffset(ped, exitCoords.x, exitCoords.y, exitCoords.z, false, false, false)
    SetEntityHeading(ped, exitHeading)
    FreezeEntityPosition(ped, false)
    SetEntityVisible(ped, true, false)
    SetEntityCollision(ped, true, true)
    SetEntityInvincible(ped, false)

    if GetResourceState('ox_target') == 'started' then
        exports.ox_target:disableTargeting(false)
    end

    HiddenState.active = false
    HiddenState.dumpsterId = nil
    HiddenState.entity = nil
    HiddenState.coords = nil
    HiddenState.heading = nil
    HiddenState.camera = nil

    notify('You climbed out of the dumpster.', 'inform')
    debugPrint('Player exited dumpster hide state')
end

local function requestLoot(entity)
    if not canInteractWithDumpster(entity) then
        notify('You are too far away from the dumpster.', 'error')
        return
    end

    local payload = getDumpsterPayload(entity)
    if not payload then
        notify('Unable to identify that dumpster.', 'error')
        return
    end

    TriggerServerEvent('rs-dumpsters:server:lootDumpster', payload)
end

local function requestStash(entity)
    if not canInteractWithDumpster(entity) then
        notify('You are too far away from the dumpster.', 'error')
        return
    end

    local payload = getDumpsterPayload(entity)
    if not payload then
        notify('Unable to identify that dumpster.', 'error')
        return
    end

    TriggerServerEvent('rs-dumpsters:server:openStash', payload)
end

local function requestHide(entity)
    if not canInteractWithDumpster(entity) then
        notify('You are too far away from the dumpster.', 'error')
        return
    end

    local payload = getDumpsterPayload(entity)
    if not payload then
        notify('Unable to identify that dumpster.', 'error')
        return
    end

    TriggerServerEvent('rs-dumpsters:server:enterDumpster', payload)
end

local function registerOxTarget()
    exports.ox_target:addModel(Config.DumpsterModels, {
        {
            name = 'rs_dumpsters_loot',
            icon = 'fa-solid fa-magnifying-glass',
            label = 'Loot Dumpster',
            distance = Config.TargetDistance,
            canInteract = function(entity, distance)
                return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
            end,
            onSelect = function(data)
                requestLoot(data.entity)
            end
        },
        {
            name = 'rs_dumpsters_stash',
            icon = 'fa-solid fa-box-open',
            label = 'Open Dumpster Stash',
            distance = Config.TargetDistance,
            canInteract = function(entity, distance)
                return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
            end,
            onSelect = function(data)
                requestStash(data.entity)
            end
        },
        {
            name = 'rs_dumpsters_hide',
            icon = 'fa-solid fa-person-shelter',
            label = 'Hide In Dumpster',
            distance = Config.TargetDistance,
            canInteract = function(entity, distance)
                return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
            end,
            onSelect = function(data)
                requestHide(data.entity)
            end
        }
    })

    TargetBackend = 'ox_target'
    debugPrint('Registered ox_target interactions')
end

local function registerQbTarget()
    exports['qb-target']:AddTargetModel(Config.DumpsterModels, {
        options = {
            {
                num = 1,
                type = 'client',
                event = 'rs-dumpsters:client:noop',
                icon = 'fas fa-magnifying-glass',
                label = 'Loot Dumpster',
                action = function(entity)
                    requestLoot(entity)
                end,
                canInteract = function(entity, distance)
                    return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
                end
            },
            {
                num = 2,
                type = 'client',
                event = 'rs-dumpsters:client:noop',
                icon = 'fas fa-box-open',
                label = 'Open Dumpster Stash',
                action = function(entity)
                    requestStash(entity)
                end,
                canInteract = function(entity, distance)
                    return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
                end
            },
            {
                num = 3,
                type = 'client',
                event = 'rs-dumpsters:client:noop',
                icon = 'fas fa-person-shelter',
                label = 'Hide In Dumpster',
                action = function(entity)
                    requestHide(entity)
                end,
                canInteract = function(entity, distance)
                    return distance <= Config.TargetDistance and canInteractWithDumpster(entity)
                end
            }
        },
        distance = Config.TargetDistance
    })

    TargetBackend = 'qb-target'
    debugPrint('Registered qb-target interactions')
end

local function normalizeTargetSystem(value)
    if value == 'qb-target' or value == 'qb_target' then
        return 'qb-target'
    end

    if value == 'ox_target' or value == 'ox-target' then
        return 'ox_target'
    end

    return nil
end

local function registerTargeting()
    local targetSystem = normalizeTargetSystem(Config.TargetSystem)

    if not targetSystem then
        debugPrint('Invalid Config.TargetSystem value', { configured = Config.TargetSystem })
        return
    end

    if GetResourceState(targetSystem) ~= 'started' then
        debugPrint('Configured target resource is not started', { configured = targetSystem })
        return
    end

    if targetSystem == 'ox_target' then
        registerOxTarget()
        return
    end

    if targetSystem == 'qb-target' then
        registerQbTarget()
        return
    end
end

RegisterNetEvent('rs-dumpsters:client:noop', function()
    -- qb-target requires an event field even when action is used.
end)

RegisterNetEvent('rs-dumpsters:client:notify', function(description, notifyType)
    notify(description, notifyType)
end)

RegisterNetEvent('rs-dumpsters:client:hideApproved', function(payload)
    local entity = nil
    local searchCoords = vec3(payload.coords.x, payload.coords.y, payload.coords.z)

    for i = 1, #Config.DumpsterModels do
        local found = GetClosestObjectOfType(searchCoords.x, searchCoords.y, searchCoords.z, Config.SearchRadius, joaat(Config.DumpsterModels[i]), false, false, false)
        if found and found ~= 0 and DoesEntityExist(found) then
            entity = found
            break
        end
    end

    if not entity or entity == 0 then
        TriggerServerEvent('rs-dumpsters:server:leaveDumpster')
        notify('The dumpster could not be found.', 'error')
        return
    end

    setPlayerHidden(true, entity, payload)
end)

RegisterNetEvent('rs-dumpsters:client:forceLeaveDumpster', function(reason)
    setPlayerHidden(false)

    if reason then
        notify(reason, 'warning')
    end
end)

CreateThread(function()
    Wait(500)
    registerTargeting()
end)

CreateThread(function()
    while true do
        if HiddenState.active then
            DisableAllControlActions(0)
            EnableControlAction(0, 245, true)
            EnableControlAction(0, 249, true)
            EnableControlAction(0, Config.HideExitControl, true)

            if IsDisabledControlJustPressed(0, Config.HideExitControl) then
                TriggerServerEvent('rs-dumpsters:server:leaveDumpster')
                setPlayerHidden(false)
            end

            Wait(0)
        else
            Wait(500)
        end
    end
end)

if Config.Debug then
    local function drawText3D(coords, text)
        local onScreen, screenX, screenY = World3dToScreen2d(coords.x, coords.y, coords.z)
        if not onScreen then return end

        SetTextScale(0.30, 0.30)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextCentre(true)
        SetTextOutline()
        SetTextEntry('STRING')
        AddTextComponentString(text)
        DrawText(screenX, screenY)
    end

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            local playerCoords = GetEntityCoords(ped)
            local closestEntity = nil
            local closestDistance = 10.0

            for i = 1, #Config.DumpsterModels do
                local entity = GetClosestObjectOfType(playerCoords.x, playerCoords.y, playerCoords.z, 10.0, joaat(Config.DumpsterModels[i]), false, false, false)
                if entity and entity ~= 0 and DoesEntityExist(entity) then
                    local distance = #(playerCoords - GetEntityCoords(entity))
                    if distance < closestDistance then
                        closestDistance = distance
                        closestEntity = entity
                    end
                end
            end

            if closestEntity then
                local coords = GetEntityCoords(closestEntity)
                DrawMarker(2, coords.x, coords.y, coords.z + 1.58, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.12, 0.12, 0.12, 0, 180, 255, 180, false, false, false, true, nil, nil, false)
                drawText3D(coords + vec3(0.0, 0.0, 1.78), ('[DEBUG] %s | %.2fm'):format(GetEntityModel(closestEntity), closestDistance))
                Wait(0)
            else
                Wait(500)
            end
        end
    end)
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= ResourceName then return end

    if HiddenState.active then
        setPlayerHidden(false)
    end
end)
