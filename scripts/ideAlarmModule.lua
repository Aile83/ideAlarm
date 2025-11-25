--[[
ideAlarm.lua
Please read: https://github.com/dewgew/ideAlarm/wiki
Copyright (C) 2017  BakSeeDaa
		This program is free software: you can redistribute it and/or modify
		it under the terms of the GNU General Public License as published by
		the Free Software Foundation, either version 3 of the License, or
		(at your option) any later version.
		This program is distributed in the hope that it will be useful,
		but WITHOUT ANY WARRANTY; without even the implied warranty of
		MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
		GNU General Public License for more details.
		You should have received a copy of the GNU General Public License
		along with this program.  If not, see <http://www.gnu.org/licenses
--]]

local config = require "ideAlarmConfig"
local custom = require "ideAlarmHelpers"

local scriptVersion = '3.2.0'
local ideAlarm = {}

-- Possible Zone statuses
local ZS_NORMAL = 'Normal'
ideAlarm.ZS_NORMAL = ZS_NORMAL
local ZS_ARMING = 'Arming'
ideAlarm.ZS_ARMING = ZS_ARMING
local ZS_ALERT = 'Alert'
ideAlarm.ZS_ALERT = ZS_ALERT
local ZS_ERROR = 'Error'
ideAlarm.ERROR = ZS_ERROR
local ZS_TRIPPED = 'Tripped'
ideAlarm.TRIPPED = ZS_TRIPPED
local ZS_TIMED_OUT = 'Timed out'
ideAlarm.ZS_TIMED_OUT = ZS_TIMED_OUT

local SECURITY_PANEL_NAME = config.SECURITY_PANEL_NAME or 'Security Panel' 

local SENSOR_CLASS_A = 'a' -- Sensor active in both arming modes. E.g. "Armed Home" and "Armed Away".
ideAlarm.SENSOR_CLASS_A = SENSOR_CLASS_A
local SENSOR_CLASS_B = 'b' -- Sensor active in arming mode "Armed Away" only.
ideAlarm.SENSOR_CLASS_B = SENSOR_CLASS_B

local function isActive(sensor)
	if sensor.switchType == 'Door Lock' then return (not sensor.active) end
	-- Cas particulier du capteur de sabotage Lidl : nValue est à 1 mais sensor.active à false ! ===> on utiliser sensor.state == 'Tamper'
	if string.gsub(sensor.state, "%s+", "") == 'Tamper' then return sensor.nValue == 1 else return sensor.active end
end

local function callIfDefined(f)
	return function(...)
		local error, result = pcall(custom.helpers[f], ...)
		if error then -- f exists and is callable
			return result
		end
	end
end

--- Initialize the alarm zones table with config values and some additional functions 
local function initAlarmZones()
	local zones = {}
	for i, alarmZone in ipairs(config.ALARM_ZONES) do

		alarmZone.zoneNumber = i

		alarmZone.armingMode =
		--- Gets the arming mode for the zone 
		-- @param domoticz The Domoticz object
		-- @return String. One of domoticz.SECURITY_DISARMED, domoticz.SECURITY_ARMEDAWAY
		-- and domoticz.SECURITY_ARMEDHOME
		function(domoticz)
			return(domoticz.devices(alarmZone.armingModeTextDevID).state)
		end

		alarmZone.status =
		--- Gets the alarm zone's status 
		-- @param domoticz The Domoticz object
		-- @return String. One of alarm.ZS_NORMAL, alarm.ZS_ARMING, alarm.ZS_ALERT, alarm.ERROR,
		-- alarm.ZS_TRIPPED or alarm.ZS_TIMED_OUT
		function(domoticz)
			return(domoticz.devices(alarmZone.statusTextDevID).state)
		end

		alarmZone.isArmed =
		--- Returns true if the zone is armed 
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function(domoticz)
			return(alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED)  
		end

		alarmZone.isArmedHome =
		--- Returns true if the zone is armed home
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function(domoticz)
			return(alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDHOME)  
		end

		alarmZone.isArmedAway =
		--- Returns true if the zone is armed away 
		-- @param domoticz The Domoticz object
		-- @return Boolean
		function (domoticz)
			return(alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDAWAY)  
		end

		alarmZone.trippedSensors =
		--- Gets all tripped sensor devices for the zone 
		-- @param domoticz The Domoticz object
		-- @param secs Integer 0-9999 Number of seconds that the sensor must have been updated within.
		-- A 0 value will return sensor devices who are currently tripped. 
		-- @param armingMode String One of domoticz.SECURITY_ARMEDAWAY, domoticz.SECURITY_ARMEDHOME or domoticz.SECURITY_DISARMED
		-- A sensor is regarded to be tripped only in the context of an arming mode. Defaults to the zones current arming mode. 
		-- @param isArming Boolean. In an arming scenario we don't want to include sensors that are set not to warn when arming.
		-- @return Table with tripped Domoricz devices
		function(domoticz, secs, armingMode, isArming)
			secs = secs or 60
			armingMode = armingMode or alarmZone.armingMode(domoticz)
			isArming = isArming or false
			local trippedSensors = {}
			if armingMode == domoticz.SECURITY_DISARMED then return trippedSensors end
			-- Get a list of all open and active sensors for this zone
			for sensorName, sensorConfig in pairs(alarmZone.sensors) do
				local sensor = domoticz.devices(sensorName)
				if ((secs > 0  and sensor.lastUpdate.secondsAgo <= secs) or
				    (secs == 0 and isActive(sensor))) then
					local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
					if includeSensor and isArming then includeSensor = sensorConfig.armWarn end
					if includeSensor then
						includeSensor = (armingMode == domoticz.SECURITY_ARMEDAWAY) or
										(armingMode == domoticz.SECURITY_ARMEDHOME and sensorConfig.class ~= SENSOR_CLASS_B)
					end 
					if includeSensor then
						table.insert(trippedSensors, sensor)
					end
				end
			end
			return trippedSensors
		end

		alarmZone._updateZoneStatus =
		---Function to set the alarm zones status
		-- @param domoticz The Domoticz object
		-- @param newStatus Text (Optional) The new status to set.
		-- @param delay Integer (Optional) Delay in seconds.
		-- One of alarm.ZS_NORMAL, alarm.ZS_ARMING, alarm.ZS_ALERT, alarm.ERROR,
		-- alarm.ZS_TRIPPED or alarm.ZS_TIMED_OUT. Defaults to alarm.ZS_NORMAL
		-- @return Nil
		function(domoticz, newStatus, delay)
			newStatus = newStatus or ZS_NORMAL
			delay = delay or 0
			if (newStatus ~= ZS_NORMAL) and (newStatus ~= ZS_ARMING) and (newStatus ~= ZS_ALERT) and (newStatus ~= ZS_ERROR) and (newStatus ~= ZS_TRIPPED) and (newStatus ~= ZS_TIMED_OUT) then
				domoticz.log('Statut invalide pour la zone '..alarmZone.name, domoticz.LOG_ERROR)
				newStatus = ZS_ERROR
				delay = 0
			end

			if alarmZone.status(domoticz) ~= newStatus then
				domoticz.devices(alarmZone.statusTextDevID).updateText(newStatus).afterSec(delay)
				domoticz.log("Mise à jour de la zone "..alarmZone.name..(delay>0 and ' dans '..delay..' secondes' or ' immédiatement')..' avec le statut '..newStatus, domoticz.LOG_INFO)
			end
		end

		alarmZone.disArmZone =
		--- Disarms the zone unless it's already disarmed.
		-- @param domoticz The Domoticz object
		-- @return Nil
		function(domoticz)
			if alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED then
				domoticz.log('Zone '..alarmZone.name..' : '..alarmZone.armingMode(domoticz), domoticz.LOG_INFO)
				domoticz.devices(alarmZone.armingModeTextDevID).updateText(domoticz.SECURITY_DISARMED)
			end
		end

		alarmZone.armZone =
		--- Arms a zone to the given arming mode after an optional delay.
		-- Arming a zone also resets it's status
		-- @param domoticz The Domoticz object
		-- @param z integer/string/table (Optional) The zone to look up. 
		-- @param armingMode String. The new arming mode to set.
		-- Should be one of domoticz.SECURITY_ARMEDAWAY and domoticz.SECURITY_ARMEDHOME
		-- @param delay Integer. (Optional) Number of seconds to delay the arming action. Defaults to the
		-- zone objects defined exit delay. 
		-- @return Nil
		function(domoticz, armingMode, delay)
			delay = delay or (armingMode == domoticz.SECURITY_ARMEDAWAY and alarmZone.exitDelay or 0)
			armingMode = armingMode or domoticz.SECURITY_ARMEDAWAY
			if (armingMode ~= domoticz.SECURITY_ARMEDAWAY)
			and (armingMode ~= domoticz.SECURITY_ARMEDHOME) then
				domoticz.log('Tentative pour activer un mode d\'armement invalide dans la zone '..alarmZone.name, domoticz.LOG_ERROR)
				return
			end 
			if alarmZone.armingMode(domoticz) ~= armingMode then
				local isArming = true
				local trippedSensors = alarmZone.trippedSensors(domoticz, 0, armingMode, isArming)
				if (#trippedSensors > 0) then
					callIfDefined('alarmZoneArmingWithTrippedSensors')(domoticz, alarmZone, armingMode)
					if not alarmZone.canArmWithTrippedSensors then
						local msg = ''
						for _, sensor in ipairs(trippedSensors) do
							if msg ~= '' then msg = msg..' and ' end
							msg = msg..sensor.name
						end
						domoticz.log('An arming attempt has been made with tripped sensor(s) in zone: '
							..alarmZone.name..'. Tripped sensor(s): '..msg..'.', domoticz.LOG_ERROR)
						alarmZone._updateZoneStatus(domoticz, ZS_ERROR)
						return
					end
				end
				if delay > 0 then
					alarmZone._updateZoneStatus(domoticz, ZS_ARMING)
				end
				domoticz.log(alarmZone.name..' : '..armingMode..(delay>0 and ' avec un délai de '..delay..' secondes' or ' immediatement'), domoticz.LOG_INFO)
				domoticz.devices(alarmZone.armingModeTextDevID).updateText(armingMode).afterSec(delay)
			end
		end

		alarmZone.toggleArmingMode =
		---Function to toggle the zones arming mode between 'Disarmed' and armType
		function(domoticz, armingMode)
			armingMode = armingMode or domoticz.SECURITY_DISARMED 
			local newArmingMode
			newArmingMode = (alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED and domoticz.SECURITY_DISARMED or armingMode)

			if newArmingMode == domoticz.SECURITY_DISARMED then
				alarmZone.disArmZone(domoticz)
			else
				alarmZone.armZone(domoticz, newArmingMode)
			end
		end

		alarmZone.sensorConfig =
		--- Looks up and returns the sensor configuration object by given sensor name.
		-- Generates an error if a sensor can not be found.
		-- @param sensorName String. The sensor to look up.
		-- @return The sensor object table
		function(sName)
			for sensorName, sensorConf in pairs(alarmZone.sensors) do
				if sensorName == sName then return sensorConf end
			end
			print('Error: Can\'t find a sensor with name: \''..sName..'\' defined in '..alarmZone.name..'.')
		end

		table.insert(zones, alarmZone)
	end
	return zones
end

--- The alarm zones table 
local alarmZones = initAlarmZones()

--- Looks up the zone object for a zone given by name or index.
-- If a zone object is given it will just return it.
-- Generates an error if a zone given by name can not be found.
-- @param z (integer/string/table (Optional) The zone to look up.
-- If not given, the ideAlarm main zone will be used.
-- @return The Zone table
function ideAlarm.zones(z)
	local function mainZoneIndex()
		for index, z in ipairs(alarmZones) do
			if z.mainZone then return index end
		end
		return(nil)
	end
	z = z or mainZoneIndex()
	if type(z) == 'number' then
		return(alarmZones[z])
	elseif type(z) == 'string' then
		for _, zone in ipairs(alarmZones) do
			if zone.name == z then return zone end
		end
		print('Error: Can\'t find an alarm zone with name: \''..z..'\' in the configuration.')
	elseif type(z) == 'table' then
		return(z)
	end
end

local function toggleSirens(domoticz, device, alertingZones)
	local allAlertDevices = {}

	-- Étape 1 : initialisation des états à Off pour tous les devices de toutes les zones
	for _, alarmZone in ipairs(alarmZones) do
		local maxSec = alarmZone.alarmAlertMaxSeconds or 180
		for _, alertDevice in ipairs(alarmZone.alertDevices or {}) do
			allAlertDevices[alertDevice] = {
				state = 'Off',
				maxSeconds = maxSec
			}
		end
	end

	-- Étape 2 : activer les devices pour les zones en alerte
	for _, zoneNumber in ipairs(alertingZones) do
		local alarmZone = ideAlarm.zones(zoneNumber)
		local msg = os.date("%X") .. ' : ACTIVATION DE LA SIRENE sur ' .. alarmZone.name
		domoticz.notify(msg, msg, domoticz.PRIORITY_HIGH)

		for _, alertDevice in ipairs(alarmZone.alertDevices or {}) do
			if not config.ALARM_TEST_MODE then
				-- On met à jour l’état sur 'On' et la durée max spécifique à cette zone
				allAlertDevices[alertDevice] = {
					state = 'On',
					maxSeconds = alarmZone.alarmAlertMaxSeconds or 180
				}
			end
		end
	end

	-- Étape 3 : appliquer les changements sur les devices
	for alertDevice, info in pairs(allAlertDevices) do
		local dev = domoticz.devices(alertDevice)
		if dev ~= nil and dev.state ~= info.state then
			dev.toggleSwitch().silent()
			if info.state == 'On' and info.maxSeconds > 0 then
				dev.switchOff().afterSec(info.maxSeconds).silent()
				domoticz.log('SIRENE '..alertDevice..' : extinction auto dans '..info.maxSeconds..' secondes', domoticz.LOG_INFO)
			end
		end
	end
end

local function onToggleButton(domoticz, device)
	-- Checking if the toggle buttons have been pressed
	for _, alarmZone in ipairs(alarmZones) do
		if device.active and (device.name == alarmZone.armAwayToggleBtn or device.name == alarmZone.armHomeToggleBtn) then
			local armType
			if device.name == alarmZone.armAwayToggleBtn then
				armType = domoticz.SECURITY_ARMEDAWAY
			else
				armType = domoticz.SECURITY_ARMEDHOME
			end
			domoticz.log(armType.. ' Alarm mode toggle button for zone "'..alarmZone.name..'" was pushed.', domoticz.LOG_INFO)
			alarmZone.toggleArmingMode(domoticz, armType)
		end
	end
end

local function onStatusChange(domoticz, device)
	local alertingZones = {}

	for i, alarmZone in ipairs(alarmZones) do
		local zoneStatus = alarmZone.status(domoticz)
		domoticz.log('Traitement des changements d\'état de l\'alarme pour la zone '..alarmZone.name..' : '..tostring(zoneStatus), domoticz.LOG_INFO)

		if device.id == alarmZone.statusTextDevID then
			if zoneStatus == ZS_NORMAL then
				callIfDefined('alarmZoneNormal')(domoticz, alarmZone)
			elseif zoneStatus == ZS_ARMING then
				callIfDefined('alarmZoneArming')(domoticz, alarmZone)
			elseif zoneStatus == ZS_ALERT then
				callIfDefined('alarmZoneAlert')(domoticz, alarmZone, config.ALARM_TEST_MODE)
				table.insert(alertingZones, i)
			elseif zoneStatus == ZS_ERROR then
				callIfDefined('alarmZoneError')(domoticz, alarmZone)
			elseif zoneStatus == ZS_TRIPPED then
				callIfDefined('alarmZoneTripped')(domoticz, alarmZone)
			elseif zoneStatus == ZS_TIMED_OUT then
				if alarmZone.armingMode(domoticz) ~= domoticz.SECURITY_DISARMED then alarmZone._updateZoneStatus(domoticz, ZS_ALERT) end
			end
		end
	end

	toggleSirens(domoticz, device, alertingZones)
end

local function onArmingModeChange(domoticz, device)
	-- Loop through the Zones
	-- Check if any alarm zones arming mode changed
	local zonesToSyncCheck = 0

	for _, alarmZone in ipairs(alarmZones) do
		-- Deal with arming mode changes
		-- E.g. the text device text for arming mode has changed
		if (device.id == alarmZone.armingModeTextDevID) then
			domoticz.devices(alarmZone.statusTextDevID).cancelQueuedCommands()
			domoticz.log(alarmZone.name..' cancelled queued commands if any', domoticz.LOG_INFO)
			alarmZone._updateZoneStatus(domoticz, ZS_NORMAL) -- Always set to normal when arming mode changes
			callIfDefined('alarmArmingModeChanged')(domoticz, alarmZone)

			local armingMode = alarmZone.armingMode(domoticz)
			if alarmZone.syncWithDomoSec then
				zonesToSyncCheck = zonesToSyncCheck + 1
				if zonesToSyncCheck > 1 then
					domoticz.log('Configuration file error. Only a single zone can be set up to synchronize with the Domoticz\'s security panel.', domoticz.LOG_ERROR)
					return
				end
			end
			if armingMode ~= domoticz.security then
				domoticz.log('Synchronisation du panneau de sécurité avec la zone '..alarmZone.name, domoticz.LOG_INFO)
				if armingMode == domoticz.SECURITY_DISARMED then
					domoticz.devices(SECURITY_PANEL_NAME).disarm()
				elseif armingMode == domoticz.SECURITY_ARMEDHOME then
					domoticz.devices(SECURITY_PANEL_NAME).armHome()
				elseif armingMode == domoticz.SECURITY_ARMEDAWAY then
					domoticz.devices(SECURITY_PANEL_NAME).armAway()
				end
			end
		end
	end
end

local function onSensorChange(domoticz, device)

	for _, zone in ipairs(alarmZones) do
		local cfg = zone.sensors[device.name]
		if cfg then
			local enabled = type(cfg.enabled) == 'function' and cfg.enabled(domoticz) or cfg.enabled
			local mode = zone.armingMode(domoticz)
			
			if enabled and (mode == domoticz.SECURITY_ARMEDAWAY or (mode == domoticz.SECURITY_ARMEDHOME and cfg.class == SENSOR_CLASS_A)) then
				local trig = 'trigger_'..device.name:gsub("%s+", "_")
				local trigCount = 'triggerCount_'..device.name:gsub("%s+", "_")
				local now = os.time()

				if isActive(device) then
					-- Comptage déclenchements
					local lastTrig = domoticz.data[trig] or 0
					local count = domoticz.data[trigCount] or 0

					-- Reset si délai dépassé
					if now - lastTrig > (cfg.triggerDurationSensor or 10) then
						domoticz.log(string.format("%s : reset du compteur (%d déclenchements en %d s, insuffisant)",device.name, count, now - lastTrig), domoticz.LOG_FORCE)
						count = 0
					end

					count = count + 1
					domoticz.data[trigCount] = count
					domoticz.data[trig] = now
					domoticz.log(string.format("%s déclenché à %s dans la zone %s (%d/%d)",device.name, os.date("%X"), zone.name, domoticz.data[trigCount], cfg.triggerCountSensor,0), domoticz.LOG_FORCE)

					-- Filtrage anti-faux-positifs : nombre de déclenchements + durée minimale
					local activeTime = device.lastUpdate.secondsAgo or 0
					local minTime = cfg.minActivationTime or 0  -- en secondes

					if domoticz.data[trigCount] >= cfg.triggerCountSensor then -- and activeTime >= minTime then
						domoticz.data[trigCount] = 0
						zone._updateZoneStatus(domoticz, ZS_ALERT, 0)
						if domoticz.devices(zone.statusTextDevID).text == ZS_ALERT then 
							domoticz.log('Alarme de la zone '..zone.name..' déjà activée. On ne la relance pas.',domoticz.LOG_FORCE)
						end
					end
				end
			end
		end
	end
end

local function onSecurityChange(domoticz, item)
	-- Domoticz built in Security state has changed, shall we sync the new arming mode to any zone?

	local zonesToSyncCheck = 0
	for i, alarmZone in ipairs(alarmZones) do
		if alarmZone.syncWithDomoSec then
			zonesToSyncCheck = zonesToSyncCheck + 1
			if zonesToSyncCheck > 1 then
				domoticz.log('Configuration file error. Only a single zone can be set up to synchronize with the Domoticz\'s security panel.', domoticz.LOG_ERROR)
				return
			end
		end
		local newArmingMode = item.trigger
		if alarmZone.armingMode(domoticz) ~= newArmingMode then
			domoticz.log('Zone principale : '..newArmingMode, domoticz.LOG_INFO)
			domoticz.log('Synchronisation avec la zone '..alarmZone.name, domoticz.LOG_INFO)
			if newArmingMode == domoticz.SECURITY_DISARMED then
				alarmZone.disArmZone(domoticz)
			else
				alarmZone.armZone(domoticz, newArmingMode)
			end
		end
	end
end

--- Checks how many open sensors there are in each zone.
-- Inserts the NbCapteursOuverts item into each alarmZone object
-- If defined, calls the ideAlarm custom helper function alarmOpenSensorsAllZones
-- @param domoticz The Domoticz object
-- @return Nil
local function countOpenSensors(domoticz, item)
	for i, alarmZone in ipairs(alarmZones) do
		local NbCapteursOuverts = 0
		local NbCapteursFermes = 0
		alarmZone.openSensorsTxt = ''
		alarmZone.closeSensorsTxt = ''
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName)
			if sensor then
				alarmZone.alarmLastUpdateSensor = math.min(alarmZone.alarmLastUpdateSensor, sensor.lastUpdate.secondsAgo)
				local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
				if includeSensor and sensorConfig.nag and isActive(sensor) then
					NbCapteursOuverts = NbCapteursOuverts + 1
					alarmZone.openSensorsTxt = alarmZone.openSensorsTxt..sensorName..'-'
				else
					NbCapteursFermes = NbCapteursFermes + 1
					alarmZone.closeSensorsTxt = alarmZone.closeSensorsTxt..sensorName..'-'
				end
				if sensor.lastUpdate.secondsAgo < 300 then
					domoticz.log('Capteurs récemment activés : '..alarmZone.name..' ('..sensor.name..' - '..alarmZone.alarmLastUpdateSensor..' secondes)', domoticz.LOG_INFO)
				end
			end
		end

		if NbCapteursOuverts ~= 0 then
			alarmZone.openSensorsTxt  = string.sub(alarmZone.openSensorsTxt,1, string.len(alarmZone.openSensorsTxt)-1)
			alarmZone.closeSensorsTxt = string.sub(alarmZone.closeSensorsTxt,1,string.len(alarmZone.closeSensorsTxt)-1)
			domoticz.log(NbCapteursOuverts..' capteur(s) ouvert(s) dans Zone '..alarmZone.name..' : '..alarmZone.openSensorsTxt, domoticz.LOG_INFO)
			domoticz.log(NbCapteursFermes ..' capteur(s) fermé(s) dans Zone ' ..alarmZone.name..' : '..alarmZone.closeSensorsTxt..' (inactif(s) depuis '..alarmZone.alarmLastUpdateSensor..' secondes)', domoticz.LOG_INFO)
		else
			NbCapteursOuverts = 0
		end

		dureeSansMvt = string.format("%02dh%02d:%02d", math.floor(alarmZone.alarmLastUpdateSensor/3600), math.floor(alarmZone.alarmLastUpdateSensor/60)%60, alarmZone.alarmLastUpdateSensor%60)

		domoticz.log(alarmZone.name..' - '..tostring(alarmZone.status(domoticz))..' : '..tostring(NbCapteursOuverts)..' capteurs actifs'..
									 ' - pas de mouvement depuis ' ..dureeSansMvt..' secondes ', domoticz.LOG_INFO)
		if alarmZone.status(domoticz) ~= ZS_NORMAL and alarmZone.alarmLastUpdateSensor > alarmZone.alarmAlertMaxSeconds and NbCapteursOuverts == 0 then
			-- Reset the alert and re-arm the zone
			msg = os.date("%X")..' : aucun capteur ouvert dans la zone '..alarmZone.name..
								 ' depuis plus de '..alarmZone.alarmLastUpdateSensor..' secondes ==> arrêt de la sirène et réarmement après '..config.ALARM_REARM_SECONDS..' secondes'
			domoticz.notify(msg, msg, domoticz.PRIORITY_HIGH)
			alarmZone._updateZoneStatus(domoticz, ZS_NORMAL,config.ALARM_REARM_SECONDS)
			alarmZone.alarmLastUpdateSensor = 999999
		end
		for _, alertDevice in ipairs(alarmZone.alertDevices) do
			domoticz.log('Etat de l\'alarme zone '..alarmZone.name..' : '..domoticz.devices(alertDevice).state, domoticz.LOG_INFO)
		end
		if alarmZone.status(domoticz) ~= ZS_NORMAL then
			msg = os.date("%X")..' : UNE DETECTION A EU LIEU DANS LA ZONE '..alarmZone.name..' !!!'
--			domoticz.notify(msg, msg, domoticz.PRIORITY_HIGH)
		end
	end
	callIfDefined('alarmOpenSensorsAllZones')(domoticz, alarmZones)
end

--- Nags periodically about open sensors 
-- @param domoticz The Domoticz object
-- @param item
-- @return Nil
local function nagCheck(domoticz, item)
	-- You just came here to nag about open doors, didn't you?
	local nagEventData = domoticz.data.nagEvent
	local nagEventItem = nagEventData.getLatest()
	if not nagEventItem then
		nagEventData.add('dzVents rocks!1')
		nagEventItem = nagEventData.getLatest()
	end

	if item.isTimer then
		-- Triggered by a timer event
		-- First check if we have nagged recently.
		local lastNagSecondsAgo = nagEventItem.time.secondsAgo
		if lastNagSecondsAgo < ideAlarm.nagInterval() then
			return
		end
	end

	local zonesNagSensors = {}
	local totalSensors = 0
	for _, alarmZone in ipairs(alarmZones) do
		local nagSensors = {}
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName)
			if sensor then
				local includeSensor = (type(sensorConfig.enabled) == 'function') and sensorConfig.enabled(domoticz) or sensorConfig.enabled
				if includeSensor then
					includeSensor = ((alarmZone.armingMode(domoticz) == domoticz.SECURITY_DISARMED) 
						or (alarmZone.armingMode(domoticz) == domoticz.SECURITY_ARMEDHOME and sensorConfig.class == SENSOR_CLASS_B))
				end
				local secondsAgo = sensor.lastUpdate.secondsAgo
				if includeSensor and sensorConfig.nag and isActive(sensor) and secondsAgo >= sensorConfig.nagTimeoutSecs then
					-- Capteur actif depuis trop longtemps
					table.insert(nagSensors, sensor)
					totalSensors = totalSensors + 1
				end
			end
		end
		table.insert(zonesNagSensors, nagSensors)
	end
	
	-- Exit if triggered by device and not all sections in all zones are closed/off 
	if totalSensors > 0 and item.isDevice then return end

	local hasNagged = false
	for i, nagSensors in ipairs(zonesNagSensors) do
		local lastValue = domoticz.data['nagZ'..tostring(i)]
		if #nagSensors > 0 then hasNagged = true end
		if (#nagSensors > 0) or (#nagSensors == 0 and lastValue > 0) then 
			callIfDefined('alarmNagOpenSensors')(domoticz, alarmZones[i], nagSensors, lastValue)
		end
		domoticz.data['nagZ'..tostring(i)] = #nagSensors
	end

	if hasNagged then
		nagEventData.add('dzVents rocks!2') -- Reset
	end
end

function ideAlarm.execute(domoticz, item)

	local devTriggerSpecific

	-- What caused this script to trigger?
	if item.isDevice then
		for _, alarmZone in ipairs(alarmZones) do
			if item.deviceSubType == 'Text' then
				if item.id == alarmZone.statusTextDevID then
					devTriggerSpecific = 'status' -- Alarm Zone Status change
					break
				elseif item.id == alarmZone.armingModeTextDevID then
					devTriggerSpecific = 'armingMode' -- Alarm Zone Arming Mode change
					break
				end
			elseif item.active and (item.name == alarmZone.armAwayToggleBtn or item.name == alarmZone.armHomeToggleBtn) then
				devTriggerSpecific = 'toggleSwitch'
				break
			end
		end
		devTriggerSpecific = devTriggerSpecific or 'sensor'
	end

	if item.isDevice then
		if devTriggerSpecific == 'toggleSwitch' then
			onToggleButton(domoticz, item)
			return
		elseif devTriggerSpecific == 'status' then
			onStatusChange(domoticz, item)
			return
		elseif devTriggerSpecific == 'armingMode' then
			onArmingModeChange(domoticz, item)
			return
		elseif devTriggerSpecific == 'sensor' then
			if isActive(item) then
				onSensorChange(domoticz, item)	-- Only Open or On states are of interest
			else
				nagCheck(domoticz, item)		-- Only Closed or Off states are of interest
			end
			countOpenSensors(domoticz,item)
			return
		end
	elseif item.isSecurity then
		onSecurityChange(domoticz, item)
	elseif item.isTimer then
		nagCheck(domoticz, item)
	end

	countOpenSensors(domoticz, item)

end

function ideAlarm.version()
	return('ideAlarm V'..scriptVersion)
end

--- Lists all defined alarm zones and sensors
-- @param domoticz (Table). The domoticz table object.
-- @return (String) The listing string.
function ideAlarm.statusAll(domoticz)
	local statusTxt = '\n\n'..ideAlarm.version()..'\nListing alarm zones and sensors:\n\n'
	for i, alarmZone in ipairs(alarmZones) do
		statusTxt = statusTxt..'Zone #'..tostring(i)..': '..alarmZone.name
			..((alarmZone.mainZone) and ' (Main Zone) ' or '')
			..((alarmZone.syncWithDomoSec) and ' (Sync with Domoticz\'s Security Panel) ' or '')
			..', '..alarmZone.armingMode(domoticz)
			..', '..alarmZone.status(domoticz)..'\n===========================================\n'
		-- List all sensors for this zone
		for sensorName, sensorConfig in pairs(alarmZone.sensors) do
			local sensor = domoticz.devices(sensorName) 
			local isEnabled
			if type(sensorConfig.enabled) == 'function' then
				isEnabled = sensorConfig.enabled(domoticz)
			else
				isEnabled = sensorConfig.enabled
			end
			statusTxt = statusTxt..sensor.name
				..(isEnabled and ': Enabled,' or ': Disabled,')
				..(isActive(sensor) and ' Tripped' or ' Not tripped')..'\n'
		end
		statusTxt = statusTxt..'\n'
	end
	return statusTxt
end

function ideAlarm.testAlert(domoticz)

	if config.ALARM_TEST_MODE then
		domoticz.log('Can not test alerts when ALARM_TEST_MODE is enabled in configuration file.' , domoticz.LOG_ERROR)
		return false
	end

	local allAlertDevices = {}

	for _, alarmZone in ipairs(alarmZones) do
		for _, alertDevice in ipairs(alarmZone.alertDevices) do
			allAlertDevices[alertDevice] = 'On'
		end
	end

	local tempMessage = ideAlarm.statusAll(domoticz)
	callIfDefined('alarmAlertMessage')(domoticz, tempMessage, config.ALARM_TEST_MODE)
	domoticz.log(tempMessage, domoticz.LOG_FORCE)

	for alertDevice, _ in pairs(allAlertDevices) do
		domoticz.log(alertDevice, domoticz.LOG_FORCE)
		domoticz.devices(alertDevice).switchOn().silent()
		domoticz.devices(alertDevice).switchOff().afterSec(5).silent()
	end

	return true
end

--- Get the quantity of defined ideAlarm zones
-- @return Integer
function ideAlarm.qtyAlarmZones()
	return(#alarmZones)
end

--- Get the timer triggers
-- @return table
function ideAlarm.timerTriggers()
	local nagTriggerInterval = config.NAG_SCRIPT_TRIGGER_INTERVAL or {'every minute'}
	return nagTriggerInterval
end

--- Get the logging level if defined in config file.
-- @return integer
function ideAlarm.loggingLevel(domoticz)
	return (config.loggingLevel ~= nil and config.loggingLevel(domoticz) or nil)
end

--- Get the nag interval
-- @return integer
function ideAlarm.nagInterval()
	return (config.NAG_INTERVAL_SECONDS or 360)
end

--- Get all devices that ideAlarm shall trigger upon
-- @return The trigger devices table
function ideAlarm.triggerDevices()
	local tDevs = {}
	for _, alarmZone in ipairs(alarmZones) do
		if alarmZone.armAwayToggleBtn ~= '' then table.insert(tDevs, alarmZone.armAwayToggleBtn) end
		if alarmZone.armHomeToggleBtn ~= '' then table.insert(tDevs, alarmZone.armHomeToggleBtn) end
		table.insert(tDevs, alarmZone.statusTextDevID)
		table.insert(tDevs, alarmZone.armingModeTextDevID)
		-- We don't have a domoticz object at this stage. Otherwise we could check the arming mode and insert
		-- only the trigger devices relevant to the alarm zones current arming mode
		for sensorName, _ in pairs(alarmZone.sensors) do
			table.insert(tDevs, sensorName)
		end
	end

	return(tDevs)
end

return ideAlarm
