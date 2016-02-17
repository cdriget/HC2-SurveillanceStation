--------------------------------------------------
-- Module  : Synology Surveillance Station v4.3
-- Button  : List cameras
--------------------------------------------------

-- User configurable variables
login = "Fibaro"
password = "password"

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
local API_CAMERA_ERROR_CODE = {
	[400] = "Execution failed.",
	[401] = "Parameter invalid.",
	[402] = "Camera disabled."
}
local API_PTZ_ERROR_CODE = {
	[400] = "Execution failed.",
	[401] = "Parameter invalid.",
	[402] = "Camera disabled."
}
local cameras = {}

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

-- Get list of all cameras
function List()
	local payload = "/webapi/"..pathCamera.."?api=SYNO.SurveillanceStation.Camera&method=List&version=4&_sid="..SID
	Message(nil, nil, false, payload)
	local response, status, errorCode = Synology:GET(payload)
	if tonumber(errorCode) == 0 and tonumber(status) == 200 then
		if response ~= nil and response ~= "" then
			local jsonTable = json.decode(response)
			if jsonTable.success == true then
				Message(nil, nil, true, 'Synology Surveillance Station number of cameras = '..tostring(jsonTable.data.total))

				if jsonTable.data.total > 0 then

					-- Display all cameras
					for i = 1, #jsonTable.data.cameras do
						Message(nil, nil, true, '<span style="color:green;">Found camera <b>'..jsonTable.data.cameras[i].name..'</b> ID=<b>'..jsonTable.data.cameras[i].id..'</b> Vendor=<b>'..jsonTable.data.cameras[i].vendor..'</b> Model=<b>'..jsonTable.data.cameras[i].model..'</b> Enabled=<b>'..tostring(jsonTable.data.cameras[i].enabled)..'</b> address='..jsonTable.data.cameras[i].host..'</span>')
						table.insert(cameras, jsonTable.data.cameras[i].id)

						-- List all presets of the PTZ camera
						payload = "/webapi/"..pathPTZ.."?api=SYNO.SurveillanceStation.PTZ&method=ListPreset&version=1&cameraId="..jsonTable.data.cameras[i].id.."&_sid="..SID
						Message(nil, nil, false, payload)
						response, status, errorCode = Synology:GET(payload)
						if tonumber(errorCode) == 0 and tonumber(status) == 200 then
							if response ~= nil and response ~= "" then
								local jsonTable2 = json.decode(response)
								if jsonTable2.success == true then
									if jsonTable2.data.total > 0 then
										for j = 1, #jsonTable2.data.presets do
											Message(nil, nil, true, '<span style="color:yellow;">Found PTZ preset <b>'..jsonTable2.data.presets[j].name..'</b> ID=<b>'..jsonTable2.data.presets[j].id..'</b></span>          ')
										end
									else
										Message(nil, nil, true, '<span style="color:blue;">Found no PTZ preset</span>          ')
									end
								else
									Message(nil, nil, true, '<span style="color:red;">Error : Synology Surveillance Station list PTZ presets failed, '..(API_PTZ_ERROR_CODE[tonumber(jsonTable2.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable2.error.code)] or "???")..', '..response..'</span>')
									if tonumber(jsonTable2.error.code) == 105 then error = true end	
								end
							else
								Message(nil, nil, true, '<span style="color:red;">Error : Synology Surveillance Station list PTZ presets failed, empty response</span>')
							end
						else
							Message(nil, nil, true, '<span style="color:red;">Synology Surveillance Station list PTZ presets failed, errorCode='..errorCode..', status='..status..'</span>')
						end

						-- List all patrols of the PTZ camera
						payload = "/webapi/"..pathPTZ.."?api=SYNO.SurveillanceStation.PTZ&method=ListPatrol&version=1&cameraId="..jsonTable.data.cameras[i].id.."&_sid="..SID
						response, status, errorCode = Synology:GET(payload)
						if tonumber(errorCode) == 0 and tonumber(status) == 200 then
							if response ~= nil and response ~= "" then
								local jsonTable2 = json.decode(response)
								if jsonTable2.success == true then
									if jsonTable2.data.total > 0 then
										for j = 1, #jsonTable2.data.patrols do
											Message(nil, nil, true, '<span style="color:blue;">Found PTZ patrol <b>'..jsonTable2.data.patrols[j].name..'</b> ID=<b>'..jsonTable2.data.patrols[j].id..'</b></span>          ')
										end
									else
										Message(nil, nil, true, '<span style="color:blue;">Found no PTZ patrol</span>          ')
									end
								else
									Message(nil, nil, true, '<span style="color:red;">Error : Synology Surveillance Station list PTZ patrols failed, '..(API_PTZ_ERROR_CODE[tonumber(jsonTable2.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable2.error.code)] or "???")..', '..response..'</span>')
									if tonumber(jsonTable2.error.code) == 105 then error = true end	
								end
							else
								Message(nil, nil, true, '<span style="color:red;">Error : Synology Surveillance Station list PTZ patrols failed, empty response</span>')
							end
						else
							Message(nil, nil, true, '<span style="color:red;">Synology Surveillance Station list PTZ patrols failed, errorCode='..errorCode..', status='..status..'</span>')
						end
					end
					-- Update Cameras Label with discovered IDs
					fibaro:call(selfID, "setProperty", "ui.LabelCameras.value", json.encode(cameras))
					Message("OK", "List OK", false, nil)
				else
					Message("Erreur", "List Failed", true, '<span style="color:red;">Found no Camera</span>')
				end
			else
				Message("Erreur", "List Failed", true, '<span style="color:red;">Error : Synology Surveillance Station list cameras failed, '..(API_CAMERA_ERROR_CODE[tonumber(jsonTable.error.code)] or API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..', '..response..'</span>')
				if tonumber(jsonTable.error.code) == 105 then error = true end	
			end
		else
			Message("Erreur", "List Failed", true, '<span style="color:red;">Error : Synology Surveillance Station list cameras failed, empty response</span>')
		end
	else
		Message("Erreur", "List Failed", true, '<span style="color:red;">Synology Surveillance Station list cameras failed, errorCode='..errorCode..', status='..status..', response='..(response or "")..'</span>')
	end
end
						
-- Discover available APIs and corresponding information
fibaro:call(selfID, "setProperty", "ui.LabelStatus.value", "List...")
local payload = "/webapi/query.cgi?api=SYNO.API.Info&method=Query&version=1&query=SYNO.API.Auth,SYNO.SurveillanceStation.Camera,SYNO.SurveillanceStation.PTZ"
Message(nil, nil, false, payload)
local response, status, errorCode = Synology:GET(payload)
if tonumber(errorCode) == 0 and tonumber(status) == 200 then
	if response ~= nil and response ~= "" then
		local jsonTable = json.decode(response)
		if jsonTable.data["SYNO.API.Auth"].maxVersion >= 2 and jsonTable.data["SYNO.SurveillanceStation.Camera"].maxVersion >= 4 and jsonTable.data["SYNO.SurveillanceStation.PTZ"].maxVersion >= 1 then
			Message(nil, nil, true, "Synology API version OK")
			pathAuth = jsonTable.data["SYNO.API.Auth"].path
			pathCamera = jsonTable.data["SYNO.SurveillanceStation.Camera"].path
			pathPTZ = jsonTable.data["SYNO.SurveillanceStation.PTZ"].path
			Message(nil, nil, false, "Synology API Auth path = "..pathAuth)
			Message(nil, nil, false, "Synology API Surveillance Station Camera path = "..pathCamera)
			Message(nil, nil, false, "Synology API Surveillance Station PTZ path = "..pathPTZ)
			-- Get SID
			SID = fibaro:getGlobal('SurvStation_SID')
			if SID == nil or SID == "" then
				-- No SID, need a new one
				GetSID()
				SID = fibaro:getGlobal('SurvStation_SID')
			end
			Message(nil, nil, false, "Synology API Auth SID = "..SID)
			List()
			if error == true then
				-- SID has expired, need a new one
				Destroy()
				GetSID()
				SID = fibaro:getGlobal('SurvStation_SID')
				List()
			end
		else
			Message("Erreur", "List Failed", true, '<span style="color:red;">Error : Synology API version is too old : <b>DSM 4.0-2251</b> and <b>Surveillance Station 6.3</b> are required</span>')
		end
	else
		Message("Erreur", "List Failed", true, '<span style="color:red;">Error : Can not connect to Synology server, empty response</span>')
	end
else
	Message("Erreur", "List Failed", true, '<span style="color:red;">Error : Can not connect to Synology server, errorCode='..errorCode..', status='..status..', ip='..ip..', port='..port..', payload='..payload..', response='..(response or "")..'</span>')
end
