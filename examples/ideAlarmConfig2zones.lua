--[[
Modifiez ce fichier selon vos besoins.
Placez ce fichier dans le dossier des scripts dzVents sous le nom ideAlarmConfig.lua
Voir https://github.com/dewgew/ideAlarm/wiki
Après modification, vérifiez toujours que le code est valide en LUA sur http://codepad.org/ (Marquez votre collage comme "Privé" !!!)
--]]

local _C = {}

local SENSOR_CLASS_A = 'a' -- Le capteur peut être déclenché dans les deux modes d’armement : « Armé Présence » et « Armé Absence ».
local SENSOR_CLASS_B = 'b' -- Le capteur peut être déclenché uniquement en mode « Armé Absence ».

--[[
-------------------------------------------------------------------------------
NE RIEN MODIFIER AU-DESSUS DE CETTE LIGNE
-------------------------------------------------------------------------------
--]]

_C.ALARM_TEST_MODE = false -- si ALARM_TEST_MODE est défini sur true, cela empêche l’alarme sonore de se déclencher

-- Intervalle de vérification du script pour rappeler qu’une porte est ouverte
_C.NAG_SCRIPT_TRIGGER_INTERVAL = {'every minute'} -- Chaque minute
-- Intervalle de répétition des rappels
_C.NAG_INTERVAL_SECONDS = 300 -- toutes les 5 minutes

-- Nombre de secondes avant réarmement de l'alarme
_C.ALARM_REARM_SECONDS = 0

--	Décommentez les 3 lignes ci-dessous pour remplacer le niveau de journalisation par défaut
--	_C.loggingLevel = function(domoticz)
--		return domoticz.LOG_INFO -- Sélectionnez l’un de LOG_DEBUG, LOG_INFO, LOG_ERROR, LOG_FORCE pour modifier le niveau de log du système
--	end

--	Si vous avez nommé votre panneau de sécurité Domoticz autrement que "Security Panel",
--	décommentez la ligne ci-dessous pour spécifier le nom.
_C.SECURITY_PANEL_NAME = 'Panneau de sécurité'

_C.ALARM_ZONES = {
	-- Début de la configuration de la première zone d’alarme
	{
		name='Maison',
		armingModeTextDevID=81,					-- Périphérique texte d’armement alarme Maison
		statusTextDevID=85,						-- Périphérique texte de statut alarme Maison
		entryDelay=15,							-- Délai d’entrée avant déclenchement (en secondes)
		exitDelay=5,							-- Délai de sortie avant activation (en secondes)
		alarmLastUpdateSensor=999999,			-- Dernière mise à jour d'une zone
		alarmAlertMaxSeconds = 30,				-- Durée maximale de l’alerte pour cette zone
		alertDevices = {'Sirène'},				-- Dispositifs déclenchés lors d’une alerte
		sensors = {
			['Capteur entrée'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 60, ['triggerCountSensor'] = 3, ['enabled'] = false},
			['Capteur antivol entrée'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Porte d\'entrée'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Capteur séjour'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 15, ['triggerCountSensor'] = 2, ['enabled'] = true},
			['Caméra Séjour'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 20, ['triggerCountSensor'] = 2, ['enabled'] = true},
			['Porte buanderie'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Capteur buanderie'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Détecteur de fumée RDC'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Détecteur de fumée étage'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
		},
		armAwayToggleBtn='Alarme Maison en absence',   -- Bouton pour activer l’alarme en mode absence
		armHomeToggleBtn='Bouton alarme en présence',  -- Bouton pour activer l’alarme en mode présence
		mainZone = true,			 -- Zone principale du système
		canArmWithTrippedSensors = true, -- Autoriser l’armement même si un capteur est actif
		syncWithDomoSec = true, -- Une seule zone peut être synchronisée avec le panneau de sécurité intégré de Domoticz
	},
	-- Fin de la configuration de la première zone d’alarme

	{
		name='Annexe',
		armingModeTextDevID=82,
		statusTextDevID=86,
		entryDelay=15,
		exitDelay=20,
		alarmLastUpdateSensor=999999,
		alarmAlertMaxSeconds = 120,
		alertDevices = {'Eclairage annexe'},
		sensors = {
			['Capteur Nord'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 90, ['triggerCountSensor'] = 3, ['enabled'] = true},
			['Capteur antivol Nord'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Caméra Annexe'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
			['Caméra Extérieure Annexe'] = {['class'] = SENSOR_CLASS_B, ['nag'] = true, ['nagTimeoutSecs'] = 5, ['armWarn'] = true, ['triggerDurationSensor'] = 60, ['triggerCountSensor'] = 3, ['enabled'] = false},
			['Porte garage'] = {['class'] = SENSOR_CLASS_A, ['nag'] = true, ['nagTimeoutSecs'] = 300, ['armWarn'] = true, ['triggerDurationSensor'] = 0, ['triggerCountSensor'] = 1, ['enabled'] = true},
		},
		armAwayToggleBtn='Alarme en absence',
		armHomeToggleBtn='Alarme en présence',
		mainZone = false,
		canArmWithTrippedSensors = true,
		syncWithDomoSec = false, -- Une seule zone peut être synchronisée avec le panneau de sécurité intégré de Domoticz
	},
	-- Fin de la configuration de la deuxième zone d’alarme
}

return _C

