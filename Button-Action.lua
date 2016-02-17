------------------------------------------------------------
-- Module  : Synology Surveillance Station v4.3
-- Button  : Start/Stop recording / Enable/Disable camera
------------------------------------------------------------

-- User configurable variables
local login = "Fibaro"
local password = "password"
local cameras = {0} -- {1,2,4,5,6}
local action = "start" -- start/stop/Enable/Disable

-- System variables
local debug_trace = false
error = false
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
local API_RECORD_ERROR_CODE = {
	[400] = "Execution failed.",
	[401] = "Parameter invalid.",
	[402] = "Camera disabled."
}
local API_CAMERA_ERROR_CODE = {
	[117] = "Not Enough Permission or access denied.",
	[400] = "Execution failed.",
	[401] = "Parameter invalid.",
	[402] = "Camera disabled."
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

-- Get Cameras list
local camera = false
if cameras then
	for k, v in ipairs(cameras) do
		if v > 0 then
			Message(nil, nil, false, "cameras{} exists")
			camera = true
			break
		end
	end
end
if not camera then
	local label = fibaro:get(selfID, "ui.LabelCameras.value")
	if label ~= nil and label ~= "" then
		Message(nil, nil, false, "Create cameras{}")
		cameras = json.decode(label)
	end
end
Message(nil, nil, false, "cameras{} : " .. json.encode(cameras))

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
				Message("Erreur", action.." failed", true, '<span style="color:red;">Error : API Authentication failure, '..(API_AUTH_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..'</span>')
			end
		else
			Message("Erreur", action.." failed", true, '<span style="color:red;">Error : API Authentication failure, empty response</span>')
		end			
	else
		Message("Erreur", action.." failed", true, '<span style="color:red;">Error : API Authentication failure, errorCode='..errorCode..', status='..status..'</span>')
	end
end

-- Destroy current login session
function Destroy()
	Message(nil, nil, true, "Destroy current SID")
	local payload = "/webapi/"..pathAuth.."?api=SYNO.API.Auth&method=Logout&version=2&session=SurveillanceStation&_sid="..SID
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
end

-- Start or stop external recording of a camera
function Action()
	Message(nil, nil, false, "action = "..action)
	for i = 1, #cameras do
		if action == "start" or action == "stop" then
			payload = "/webapi/"..pathRecord.."?api=SYNO.SurveillanceStation.ExternalRecording&method=Record&version=1&cameraId="..cameras[i].."&action="..action.."&_sid="..SID
		else
			payload = "/webapi/"..pathCamera.."?api=SYNO.SurveillanceStation.Camera&method="..action.."&version=3&cameraIds="..cameras[i].."&_sid="..SID
		end
		Message(nil, nil, false, payload)
		local response, status, errorCode = Synology:GET(payload)
		if tonumber(errorCode) == 0 and tonumber(status) == 200 then
			if response ~= nil and response ~= "" then
				local jsonTable = json.decode(response)
				if jsonTable.success == true then
					if action == "start" or action == "stop" then
						Message("OK", action.." OK", true, '<span style="color:green;">Synology Surveillance Station '..action..' recording for camera "'..tostring(cameras[i])..'" OK</span>')
					else
						Message("OK", action.." OK", true, '<span style="color:green;">Synology Surveillance Station '..action..' camera "'..tostring(cameras[i])..'" OK</span>')
					end
					if action == "start" then
						fibaro:setGlobal('SurvStation_Status', "Recording")
					elseif action == "stop" then
						fibaro:setGlobal('SurvStation_Status', "Enabled")
					elseif action == "Enable" then
						fibaro:setGlobal('SurvStation_Status', "Enabled")
					elseif action == "Disable" then
						fibaro:setGlobal('SurvStation_Status', "Disabled")
					end
				else
					if action == "start" or action == "stop" then
						Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' recording for camera "'..tostring(cameras[i])..'" FAILED : '..(API_RECORD_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..', '..response..'</span>')
					else
						Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' camera "'..tostring(cameras[i])..'" FAILED : '..(API_CAMERA_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..', '..response..'</span>')
					end
					if tonumber(jsonTable.error.code) == 105 then error = true end
				end
			else
				if action == "start" or action == "stop" then
					Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' recording for camera failed, empty response</span>')
				else
					Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' camera failed, empty response</span>')
				end
			end
		else
			if action == "start" or action == "stop" then
				Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' recording for camera failed, errorCode='..errorCode..', status='..status..', response='..(response or "")..'</span>')
			else
				Message("Erreur", action.." failed", true, '<span style="color:red;">Synology Surveillance Station '..action..' camera failed, errorCode='..errorCode..', status='..status..', response='..(response or "")..'</span>')
			end
		end
	end	
end

-- Only if a valid action
if action == "start" or action == "stop" or action == "Enable" or action == "Disable" then
	-- Discover available APIs and corresponding information
	fibaro:call(selfID, "setProperty", "ui.LabelStatus.value", action.."...")
	local payload = "/webapi/query.cgi?api=SYNO.API.Info&method=Query&version=1&query=SYNO.API.Auth,SYNO.SurveillanceStation.ExternalRecording,SYNO.SurveillanceStation.Camera"
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
	if tonumber(errorCode) == 0 and tonumber(status) == 200 then
		if response ~= nil and response ~= "" then
			local jsonTable = json.decode(response)
			if jsonTable.data["SYNO.API.Auth"].maxVersion >= 3 and jsonTable.data["SYNO.SurveillanceStation.Camera"].maxVersion >= 2 then
				Message(nil, nil, true, "Synology API version OK")
				pathAuth = jsonTable.data["SYNO.API.Auth"].path
				pathRecord = jsonTable.data["SYNO.SurveillanceStation.ExternalRecording"].path
				pathCamera = jsonTable.data["SYNO.SurveillanceStation.Camera"].path
				Message(nil, nil, false, "Synology API Auth path = "..pathAuth)
				Message(nil, nil, false, "Synology API Surveillance Station Record path = "..pathRecord)
				Message(nil, nil, false, "Synology API Surveillance Station Camera path = "..pathCamera)
				-- Get SID
				SID = fibaro:getGlobal('SurvStation_SID')
				if SID == nil or SID == "" then
					-- No SID, need a new one
					GetSID()
					SID = fibaro:getGlobal('SurvStation_SID')
				end
				Message(nil, nil, false, "Synology API Auth SID = "..SID)
				Action()
				if error == true then
					-- SID has expired, need a new one
					Destroy()
					GetSID()
					SID = fibaro:getGlobal('SurvStation_SID')
					Action()
				end
			else
				Message("Erreur", action.." failed", true, '<span style="color:red;">Error : Synology API version is too old : <b>DSM 4.0-2251</b> and <b>Surveillance Station 6.3</b> are required</span>')
			end
		else
			Message("Erreur", action.." failed", true, '<span style="color:red;">Error : Can not connect to Synology server, empty response</span>')
		end
	else
		Message("Erreur", action.." failed", true, '<span style="color:red;">Error : Can not connect to Synology server, errorCode='..errorCode..', status='..status..', ip='..ip..', port='..port..', payload='..payload..', response='..(response or "")..'</span>')
	end
else
	Message("Erreur", action.." failed", true, '<span style="color:red;">Error : "'..action..'" is not a valid action</span>')
end
