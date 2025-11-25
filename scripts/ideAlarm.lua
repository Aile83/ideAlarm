--[[
ideAlarm.lua
Please read: https://github.com/dewgew/ideAlarm/wiki
Do not change anything in this file.
--]]

local alarm = require "ideAlarmModule"
local triggerDevices = alarm.triggerDevices()

-- Initialisation des données
local data = {}
data['nagEvent'] = {history = true, maxItems = 1}

-- Historique pour chaque zone
for i = 1, alarm.qtyAlarmZones() do
	data['nagZ'..tostring(i)] = {initial=0}
end

-- Historique pour chaque capteur dans chaque zone
for i, alarmZone in ipairs(alarm.zones()) do
	for sensorName, _ in pairs(alarmZone.sensors) do
		local varName = 'tripped_'..sensorName:gsub("%s+", "_")
		data[varName] = {initial = 0}  -- timestamp initial = 0
	end
end

-- Historique pour chaque device trigger
for i, dev in ipairs(triggerDevices) do
	local devName = (type(dev) == "table" and dev.name) or tostring(dev)
	local varName = 'trigger_'..devName:gsub("%s+", "_")
	data[varName] = {initial = 0}  -- état initial = 0
	data['triggerCount_'..devName:gsub("%s+", "_")] = {initial = 0}  -- compteur initial = 0
end

return {
	active = true,
	logging = {
		level = alarm.loggingLevel(domoticz), -- Can be set in the configuration file
		marker = alarm.version()
	},
	on = {
		devices = triggerDevices,
		security = {domoticz.SECURITY_ARMEDAWAY, domoticz.SECURITY_ARMEDHOME, domoticz.SECURITY_DISARMED},
		timer = alarm.timerTriggers()
	},
	data = data,
	execute = function(domoticz, item)
		-- Appel de l'exécution principale de l'alarme
		domoticz.log('Déclenchement par '..	(item.isDevice and (item.name..', état : '..item.state) or
											(item.isTimer and ('timer : '..item.trigger)  or
											(item.isSecurity and 'Domoticz Security' or 'unknown'))), domoticz.LOG_INFO)
		alarm.execute(domoticz, item)
	end
}
