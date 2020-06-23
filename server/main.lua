ESX = nil

TriggerEvent('esx:getSharedObject', function(obj) ESX = obj end)


RegisterCommand('comserv', function(source, args, user)
	local sourcexPlayer = ESX.GetPlayerFromId(source)

	if havePermission(sourcexPlayer) then
		if args[1] and GetPlayerName(args[1]) ~= nil and tonumber(args[2]) then
			TriggerEvent('esx_communityservice:sendToCommunityService', tonumber(args[1]), tonumber(args[2]))
		else
			TriggerClientEvent('chat:addMessage', source, { args = { _U('system_msn'), _U('invalid_player_id_or_actions') } } )
		end
	else
		TriggerClientEvent('chat:addMessage', source, { args = { _U('system_msn'), _U('insufficient_permissions') } })
	end
end, true, { 
		help = _U('give_player_community'), validate= true, arguments = {
			{name = "id", help = _U('target_id'), type = 'player'},
			{name = "actions", help = _U('action_count_suggested'), type = 'number'}
		}
	}
)

RegisterCommand('endcomserv', function(source, args, user)
	local sourcexPlayer = ESX.GetPlayerFromId(source)

	if havePermission(sourcexPlayer) then
		if args[1] then
			if GetPlayerName(args[1]) ~= nil then
				TriggerEvent('esx_communityservice:endCommunityServiceCommand', tonumber(args[1]))
			else
				TriggerClientEvent('chat:addMessage', source, { args = { _U('system_msn'), _U('invalid_player_id')  } } )
			end
		else
			TriggerEvent('esx_communityservice:endCommunityServiceCommand', source)
		end
	else
		TriggerClientEvent('chat:addMessage', source, { args = { _U('system_msn'), _U('insufficient_permissions') } })
	end
end, true, {
	help = _U('unjail_people'), validate = true,  arguments = {
			{ name = "id", help = _U('target_id'), type = 'player'}
		}
	}
)

RegisterServerEvent('esx_communityservice:endCommunityServiceCommand')
AddEventHandler('esx_communityservice:endCommunityServiceCommand', function(source)
	if source ~= nil then
		releaseFromCommunityService(source)
	end
end)

-- unjail after time served
RegisterServerEvent('esx_communityservice:finishCommunityService')
AddEventHandler('esx_communityservice:finishCommunityService', function()
	releaseFromCommunityService(source)
end)

RegisterServerEvent('esx_communityservice:completeService')
AddEventHandler('esx_communityservice:completeService', function()

	local _source = source
	local identifier = GetPlayerIdentifiers(_source)[1]

	MySQL.Async.fetchAll('SELECT * FROM communityservice WHERE identifier = @identifier', {
		['@identifier'] = identifier
	}, function(result)

		if result[1] then
			MySQL.Async.execute('UPDATE communityservice SET actions_remaining = actions_remaining - 1 WHERE identifier = @identifier', {
				['@identifier'] = identifier
			})
		else
			print ("ESX_CommunityService :: Problem matching player identifier in database to reduce actions.")
		end
	end)
end)

RegisterServerEvent('esx_communityservice:extendService')
AddEventHandler('esx_communityservice:extendService', function()

	local _source = source
	local identifier = GetPlayerIdentifiers(_source)[1]

	MySQL.Async.fetchAll('SELECT * FROM communityservice WHERE identifier = @identifier', {
		['@identifier'] = identifier
	}, function(result)

		if result[1] then
			MySQL.Async.execute('UPDATE communityservice SET actions_remaining = actions_remaining + @extension_value WHERE identifier = @identifier', {
				['@identifier'] = identifier,
				['@extension_value'] = Config.ServiceExtensionOnEscape
			})
		else
			print ("ESX_CommunityService :: Problem matching player identifier in database to reduce actions.")
		end
	end)
end)

RegisterServerEvent('esx_communityservice:sendToCommunityService')
AddEventHandler('esx_communityservice:sendToCommunityService', function(target, actions_count)

	local identifier = GetPlayerIdentifiers(target)[1]

	MySQL.Async.fetchAll('SELECT * FROM communityservice WHERE identifier = @identifier', {
		['@identifier'] = identifier
	}, function(result)
		if result[1] then
			MySQL.Async.execute('UPDATE communityservice SET actions_remaining = @actions_remaining WHERE identifier = @identifier', {
				['@identifier'] = identifier,
				['@actions_remaining'] = actions_count
			})
		else
			MySQL.Async.execute('INSERT INTO communityservice (identifier, actions_remaining) VALUES (@identifier, @actions_remaining)', {
				['@identifier'] = identifier,
				['@actions_remaining'] = actions_count
			})
		end
	end)

	TriggerClientEvent('chat:addMessage', -1, { args = { _U('judge'), _U('comserv_msg', GetPlayerName(target), actions_count) }, color = { 147, 196, 109 } })
	TriggerClientEvent('esx_policejob:unrestrain', target)
	TriggerClientEvent('esx_communityservice:inCommunityService', target, actions_count)
end)

RegisterServerEvent('esx_communityservice:checkIfSentenced')
AddEventHandler('esx_communityservice:checkIfSentenced', function()
	local _source = source -- cannot parse source to client trigger for some weird reason
	local identifier = GetPlayerIdentifiers(_source)[1] -- get steam identifier

	MySQL.Async.fetchAll('SELECT * FROM communityservice WHERE identifier = @identifier', {
		['@identifier'] = identifier
	}, function(result)
		if result[1] ~= nil and result[1].actions_remaining > 0 then
			--TriggerClientEvent('chat:addMessage', -1, { args = { _U('judge'), _U('jailed_msg', GetPlayerName(_source), ESX.Math.Round(result[1].jail_time / 60)) }, color = { 147, 196, 109 } })
			TriggerClientEvent('esx_communityservice:inCommunityService', _source, tonumber(result[1].actions_remaining))
		end
	end)
end)

function releaseFromCommunityService(target)

	local identifier = GetPlayerIdentifiers(target)[1]
	MySQL.Async.fetchAll('SELECT * FROM communityservice WHERE identifier = @identifier', {
		['@identifier'] = identifier
	}, function(result)
		if result[1] then
			MySQL.Async.execute('DELETE from communityservice WHERE identifier = @identifier', {
				['@identifier'] = identifier
			})

			TriggerClientEvent('chat:addMessage', -1, { args = { _U('judge'), _U('comserv_finished', GetPlayerName(target)) }, color = { 147, 196, 109 } })
		end
	end)

	TriggerClientEvent('esx_communityservice:finishCommunityService', target)
end

function havePermission(xPlayer, exclude)	-- you can exclude rank(s) from having permission to specific commands 	[exclude only take tables]
	if exclude and type(exclude) ~= 'table' then exclude = nil;print("^3[esx_admin] ^1ERROR ^0exclude argument is not table..^0") end	-- will prevent from errors if you pass wrong argument

	local playerGroup = xPlayer.getGroup()
	for k,v in pairs(Config.adminRanks) do
		if v == playerGroup then
			if not exclude then
				return true
			else
				for a,b in pairs(exclude) do
					if b == v then
						return false
					end
				end
				return true
			end
		end
	end
	return false
end