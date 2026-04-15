fx_version 'cerulean'
game 'gta5'
lua54 'yes'

author 'Realistic Scripts'
name 'rs-dumpsters'
description 'Realistic dumpster script for FiveM.'
version 'v1.0.0'
repository 'https://github.com/RealisticScripts/rs-dumpsters'
license 'MIT'

dependency 'ox_lib'
dependency 'oxmysql'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server.lua'
}

client_scripts {
    'client.lua'
}
