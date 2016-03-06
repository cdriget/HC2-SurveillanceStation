--------------------------------------------------
-- Module  : Synology Surveillance Station v4.4
-- Button  : PTZ
--------------------------------------------------

-- User configurable variables
local login = "Fibaro"
local password = "password"
local preset = 1

-- System variables
local debug_trace = false
local error = false
local selfID = fibaro:getSelfId()
local ip = fibaro:get(selfID, 'IPAddress')
local port = fibaro:get(selfID, 'TCPPort')
local Synology = Net.FHttp(ip, tonumber(port))
local API_COMMON_ERROR_CODE = {
	[100] = "Unknown error",
	[101] = "Invalid parameters",
	[102] = "API does not exist",
	[103] = "Method does not exist",
	[104] = "This API version is not supported",
	[105] = "Insufficient user privilege",
	[106] = "Connection time out",
	[107] = "Multiple login detected"
}
local API_AUTH_ERROR_CODE = {
	[100] = "Unknown error.",
	[101] = "The account parameter is not specified.",
	[400] = "Invalid password.",
	[401] = "Guest or disabled account.",
	[402] = "Permission denied.",
	[403] = "One time password not specified.",
	[404] = "One time password authenticate failed."
}
local API_PTZ_ERROR_CODE = {
	[400] = "Execution failed.",
	[401] = "Parameter invalid.",
	[402] = "Camera disabled."
}

-- Message function
function Message(log_msg, label_msg, trace, debug_msg)
	if log_msg then
		fibaro:log(log_msg)
	end
	if debug_msg and (debug_trace or trace) then
		fibaro:debug(debug_msg)
	end
	if label_msg then
		fibaro:call(selfID, "setProperty", "ui.LabelStatus.value", label_msg)
	end
end

-- Get first camera
local camera = 0
local label = fibaro:get(selfID, "ui.LabelCameras.value")
if label ~= nil and label ~= "" then
	local cameras = json.decode(label)
	if #cameras >= 1 then
		camera = cameras[1]
	end
end
if camera > 0 then
	Message(nil, nil, false, "camera : "..camera)
else
	Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : No camera</span>')
end

-- Generate new SID
function GetSID()
	-- Create new login session
	Message(nil, nil, true, "Request new SID")
	local payload = "/webapi/"..pathAuth.."?api=SYNO.API.Auth&method=Login&version=2&account="..login.."&passwd="..password.."&session=SurveillanceStation&format=sid"
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
	if tonumber(errorCode) == 0 and tonumber(status) == 200 then
		if response ~= nil and response ~= "" then
			local jsonTable = json.decode(response)
			if jsonTable.success == true then
				fibaro:setGlobal('SurvStation_SID', jsonTable.data.sid)
				Message(nil, nil, true, "Synology API Auth OK")
			else
				Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : API Authentication failure, '..(API_AUTH_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..'</span>')
			end
		else
			Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : API Authentication failure, empty response</span>')
		end			
	else
		Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : API Authentication failure, errorCode='..errorCode..', status='..status..'</span>')
	end
end

-- Destroy current login session
function Destroy()
	Message(nil, nil, true, "Destroy current SID")
	local payload = "/webapi/"..pathAuth.."?api=SYNO.API.Auth&method=Logout&version=2&session=SurveillanceStation&_sid="..SID
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
end

-- Move the camera lens to a pre-defined preset position
function PTZ()
	local payload = "/webapi/"..pathPTZ.."?api=SYNO.SurveillanceStation.PTZ&method=GoPreset&version=1&cameraId="..camera.."&presetId="..preset.."&_sid="..SID
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
	if tonumber(errorCode) == 0 and tonumber(status) == 200 then
		if response ~= nil and response ~= "" then
			local jsonTable = json.decode(response)
			if jsonTable.success == true then
				Message("OK", "PTZ OK", true, '<span style="color:green;">Synology Surveillance Station move camera "'..tostring(camera)..'" to preset "'..tostring(preset)..'" OK</span>')
			else
				Message("Erreur", "PTZ failed", true, '<span style="color:red;">Synology Surveillance Station move camera "'..tostring(camera)..'" to preset "'..tostring(preset)..'" FAILED : '..(API_PTZ_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..', '..response..'</span>')
				if tonumber(jsonTable.error.code) == 105 then error = true end	
			end
		else
			Message("Erreur", "PTZ failed", true, '<span style="color:red;">Synology Surveillance Station move camera failed, empty response</span>')
		end
	else
		Message("Erreur", "PTZ failed", true, '<span style="color:red;">Synology Surveillance Station move camera failed, errorCode='..errorCode..', status='..status..', response='..(response or "")..'</span>')
	end
end

-- Only if a valid camera
if camera > 0 then
	-- Discover available APIs and corresponding information
	fibaro:call(selfID, "setProperty", "ui.LabelStatus.value", "PTZ...")
	local payload = "/webapi/query.cgi?api=SYNO.API.Info&method=Query&version=1&query=SYNO.API.Auth,SYNO.SurveillanceStation.PTZ"
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
	if tonumber(errorCode) == 0 and tonumber(status) == 200 then
		if response ~= nil and response ~= "" then
			local jsonTable = json.decode(response)
			if jsonTable.data["SYNO.API.Auth"] ~= nil and jsonTable.data["SYNO.SurveillanceStation.PTZ"] ~= nil then
				if jsonTable.data["SYNO.API.Auth"].maxVersion >= 2 and jsonTable.data["SYNO.SurveillanceStation.PTZ"].maxVersion >= 1 then
					Message(nil, nil, true, "Synology API version OK")
					pathAuth = jsonTable.data["SYNO.API.Auth"].path
					pathPTZ = jsonTable.data["SYNO.SurveillanceStation.PTZ"].path
					Message(nil, nil, false, "Synology API Auth path = "..pathAuth)
					Message(nil, nil, false, "Synology API Surveillance Station PTZ path = "..pathPTZ)
					-- Get SID
					SID = fibaro:getGlobal('SurvStation_SID')
					if SID == nil or SID == "" then
						-- No SID, need a new one
						GetSID()
						SID = fibaro:getGlobal('SurvStation_SID')
					end
					Message(nil, nil, false, "Synology API Auth SID = "..SID)
					PTZ()
					if error == true then
						-- SID has expired, need a new one
						Destroy()
						GetSID()
						SID = fibaro:getGlobal('SurvStation_SID')
						PTZ()
					end
				else
					Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : Synology API version is too old : <b>DSM 4.0-2251</b> and <b>Surveillance Station 6.0-2337</b> are required</span>')
				end
			else
				Message("Erreur", "PTZ Failed", true, '<span style="color:red;">Error : Can not get Synology API version : Surveillance Station may be stopped</span>')
			end
		else
			Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : Can not connect to Synology server, empty response</span>')
		end
	else
		Message("Erreur", "PTZ failed", true, '<span style="color:red;">Error : Can not connect to Synology server, errorCode='..errorCode..', status='..status..', ip='..ip..', port='..port..', payload='..payload..', response='..(response or "")..'</span>')
	end
end
