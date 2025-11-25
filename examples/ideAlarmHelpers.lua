--[[
Modifiez ce fichier selon vos besoins
Placez ce fichier dans le dossier des scripts dzVents sous le nom ideAlarmConfig.lua
Voir https://github.com/dewgew/ideAlarm/wiki
Après modification, vérifiez toujours qu’il s’agit d’un LUA valide sur http://codepad.org/ (Marquez votre collage comme "Private" !!!)
--]]

local _C = {}

-- Fonctions d’aide personnalisées ideAlarm. Ces fonctions seront appelées si elles existent.

_C.helpers = {

	alarmZoneNormal = function(domoticz, alarmZone)
		-- Etat normal, pas d'alarme
	end,

	alarmZoneArming = function(domoticz, alarmZone)
		-- Vous pouvez définir une action ici.
		-- Cette fonction sera appelée lors de l’armement en attendant le délai de sortie.
		-- Si le délai de sortie est de 0 seconde, cette fonction ne sera pas appelée.
	end,

	alarmZoneTripped = function(domoticz, alarmZone)
		-- Un capteur a été déclenché mais il n’y a pas encore d’alerte.
		-- Nous devons informer la personne ayant déclenché le capteur afin
		-- qu’elle puisse désarmer l’alarme avant expiration du délai
		-- et avant qu’une alerte ne soit déclenchée.
		-- Dans cet exemple, on allume les lumières de la cuisine si le nom
		-- de la zone est 'Maison', mais on pourrait aussi faire parler Domoticz
		-- ou effectuer une autre action.

		local msg = ''
		local trippedSensors = alarmZone.trippedSensors(domoticz, 5) -- Capteurs actuellement déclenchés
		for _, sensor in ipairs(trippedSensors) do
			if msg ~= '' then msg = msg..', ' end
			msg = msg..'Déclenchement '..sensor.name..' dans '..alarmZone.name
			domoticz.log(msg, domoticz.LOG_INFO)
		end
		domoticz.notify(msg, msg ,domoticz.PRIORITY_HIGH)

		if alarmZone.name == 'Maison' then
			-- domoticz.devices('Eclairage cuisine').switchOn()
		end
	end,

	alarmZoneError = function(domoticz, alarmZone)
		-- Une erreur s’est produite pour une zone d’alarme.
		-- Peut-être qu’une porte était ouverte lors de la tentative d’armement.
		msg = os.date("%X")..' Erreur sur la zone '..alarmZone.name
		domoticz.notify(msg, msg ,domoticz.PRIORITY_HIGH)
	end,

	alarmZoneArmingWithTrippedSensors = function(domoticz, alarmZone, armingMode)
		-- Des capteurs déclenchés ont été détectés lors de l’armement.
		-- Si canArmWithTrippedSensors = true dans le fichier de configuration,
		-- l’armement continue ; sinon, alarmZoneError sera appelée et l’armement sera annulé.
		local msg = ''
		local isArming = true
		local trippedSensors = alarmZone.trippedSensors(domoticz, 0, armingMode, isArming)
		for _, sensor in ipairs(trippedSensors) do
			if msg ~= '' then msg = msg..', ' end
			msg = msg..sensor.name
		end
		if msg ~= '' then
			msg = os.date("%X")..' : sections ouvertes dans '..alarmZone.name..'. '..msg
			domoticz.notify(msg, msg, domoticz.PRIORITY_HIGH)
		end
	end,

	alarmZoneAlert = function(domoticz, alarmZone, testMode)
		local msg = os.date("%X")..' : INTRUSION zone '..alarmZone.name..' !!!\n'
		local oneMinute = 60
		for _, sensor in ipairs(alarmZone.trippedSensors(domoticz, oneMinute)) do
			msg = msg..sensor.lastUpdate.raw:match('%d%d:%d%d:%d%d')..' : activation '..sensor.name..' '
		end

		if not testMode then
			domoticz.notify(msg, msg, domoticz.PRIORITY_HIGH)
		else
			-- Mode test actif : on affiche un message dans le log au lieu de notifier
			domoticz.log('(MODE TEST ACTIF) '..msg, domoticz.LOG_INFO)
		end
	end,

	alarmArmingModeChanged = function(domoticz, alarmZone)
		-- Le mode d’armement de la zone a changé.
		-- On peut vouloir être informé de ce changement.
		local zoneName = alarmZone.name
		local armingMode = alarmZone.armingMode(domoticz)
		msg = os.date("%X")..' : Zone '..zoneName.." "..armingMode
		domoticz.notify(msg,msg,domoticz.PRIORITY_HIGH)
		-- On peut achetee un Fibaro Wall Plug 2 et le configurer pour s'allumer en rouge quand OFF,
		-- et vert quand ON : il peut servir d’indicateur d’état de l’alarme.
		if armingMode == domoticz.SECURITY_DISARMED then
			domoticz.devices('Alarme active').switchOff() -- Voyant vert ON
		else
			domoticz.devices('Alarme active').switchOn()  -- Voyant rouge ON
		end
	end,

	alarmNagOpenSensors = function(domoticz, alarmZone, nagSensors, lastValue)
		-- Signale les capteurs encore ouverts dans la zone.
		if #nagSensors == 0 and lastValue > 0 then
			domoticz.log('Toutes les sections ouvertes sont désormais fermées', domoticz.LOG_INFO)
		elseif #nagSensors > 0 then
			local msg = ''
			for _, sensor in ipairs(nagSensors) do
				if msg ~= '' then msg = msg..' and ' end
				msg = msg..sensor.name
			end
			msg = 'Section ouvertes dans la zone '..alarmZone.name..'. '..msg
			domoticz.log(msg, domoticz.LOG_INFO)
		end
	end,

	alarmOpenSensorsAllZones = function(domoticz, alarmZones)
		-- Active une lampe rouge s’il y a des capteurs ouverts dans 'Maison'
		for _, alarmZone in ipairs(alarmZones) do
			if alarmZone.name == 'Maison' then
				if (alarmZone.openSensorCount > 0) then
					domoticz.devices('Lampe rouge').switchOn()
				elseif (alarmZone.openSensorCount == 0) then
					-- domoticz.devices('Lampe rouge').switchOff()
				end
			end
		end
	end,

}

return _C
