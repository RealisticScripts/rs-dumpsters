Config = {}

Config.Debug = false
Config.DiscordWebhook = ''
Config.NotificationTitle = 'Dumpster'
Config.TargetSystem = 'qb-target' -- 'qb-target' or 'ox_target'
Config.LootCooldownSeconds = 300
Config.TargetDistance = 2.0
Config.InteractionDistance = 2.0
Config.SearchRadius = 2.5
Config.HideExitControl = 38 -- E
Config.HideEnterOffset = vec3(0.0, 0.0, 0.2)
Config.HideExitOffset = vec3(0.0, 0.0, 1.0)
Config.HideHeadingOffset = 180.0
Config.StashSlots = 18
Config.StashMaxWeight = 100000
Config.StashLabel = 'Dumpster Stash'
Config.LootFailChance = 30

Config.DumpsterModels = {
    'prop_dumpster_01a',
    'prop_dumpster_02a',
    'prop_dumpster_02b',
    'prop_dumpster_3a',
    'prop_dumpster_4a',
    'prop_dumpster_4b',
    'prop_skip_01a',
    'prop_skip_02a',
    'prop_skip_06a',
    'prop_skip_10a'
}

-- Keep these aligned with the item names available on your server inventory.
Config.LootTable = {
    { item = 'plastic', amount = { min = 1, max = 4 }, chance = 30 },
    { item = 'metalscrap', amount = { min = 1, max = 3 }, chance = 25 },
    { item = 'glass', amount = { min = 1, max = 3 }, chance = 15 },
    { item = 'lockpick', amount = { min = 1, max = 1 }, chance = 8 },
    { item = 'phone', amount = { min = 1, max = 1 }, chance = 5 },
    { item = 'radio', amount = { min = 1, max = 1 }, chance = 4 }
}
