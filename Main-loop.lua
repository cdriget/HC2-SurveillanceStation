--------------------------------------------------------------------------------
-- Module  : Synology Surveillance Station v4.4
-- Button  : Main loop
-- Author  : Lazer
-- History : v1    :     March 2014 : Initial release (Lazer)
--           v1.01 :     April 2014 : Minor bug fixes (Lazer)
--           v2    :       May 2014 : New main loop & PTZ Control (Lazer)
--           v2.5  :   October 2014 : Patrol (Maestrea)
--           v3    :   January 2015 : Enable/Disable (SebCbien)
--           v4    :     April 2015 : Minor bug fixes (Lazer)
--           v4.1  :    August 2015 : SID optimization (Jojo)
--           v4.2  : September 2015 : Minor bug fixes (SebCbien)
--           v4.3  :  February 2016 : Miscellaneous enhancements (Lazer)
--           v4.4  :     March 2016 : Single/multiple cameras enhancements (Lazer)
--------------------------------------------------------------------------------

-- User configurable variables
local login = "Fibaro"
local password = "password"
local cameras = {0} -- {1,2,4,5,6}
local VG_status = "SurvStation_Status"
local refresh = 10 -- seconds
local standbyIcon = 1010
local recordIcon = 1011
local disableIcon = 1029

-- System variables
local port = fibaro:get(fibaro:getSelfId(), 'TCPPort')

-- Main object
if (SurvStation == nil) then
	SurvStation = {
		-- System variables
		selfID = fibaro:getSelfId(),
		Synology = Net.FHttp(fibaro:get(fibaro:getSelfId(), 'IPAddress'), tonumber(port)),
		API_COMMON_ERROR_CODE = {
			[100] = "Unknown error",
			[101] = "Invalid parameters",
			[102] = "API does not exist",
			[103] = "Method does not exist",
			[104] = "This API version is not supported",
			[105] = "Insufficient user privilege",
			[106] = "Connection time out",
			[107] = "Multiple login detected"
		},
		API_AUTH_ERROR_CODE = {
			[100] = "Unknown error.",
			[101] = "The account parameter is not specified.",
			[400] = "Invalid password.",
			[401] = "Guest or disabled account.",
			[402] = "Permission denied.",
			[403] = "One time password not specified.",
			[404] = "One time password authenticate failed."
		},
		API_CAMERA_ERROR_CODE = {
			[117] = "Not Enough Permission or access denied.",
			[400] = "Execution failed.",
			[401] = "Parameter invalid.",
			[402] = "Camera disabled."
		},
		--CAMERA_STATUS = {
		--	[0] = "Enabled",
		--	[1] = "Disabled",
		--	[2] = "Activating",
		--	[3] = "Disabling",
		--	[4] = "Restarting",
		--	[5] = "Unknown"
		--},
		garbageExecTime = tonumber(os.time()-300),
		-- Generate new SID
		GetSID = function(self, pathAuth)
			-- Create new login session
			fibaro:debug("Request new SID")
			local payload = "/webapi/"..pathAuth.."?api=SYNO.API.Auth&method=Login&version=2&account="..login.."&passwd="..password.."&session=SurveillanceStation&format=sid"
			local response, status, errorCode = self.Synology:GET(payload)
			if tonumber(errorCode) == 0 and tonumber(status) == 200 then
				if response ~= nil and response ~= "" then
					local jsonTable = json.decode(response)
					if jsonTable.success == true then
						fibaro:setGlobal('SurvStation_SID', jsonTable.data.sid)
 					else
						fibaro:debug('<span style="color:red;">Error : API Authentication failure, '..(self.API_AUTH_ERROR_CODE[tonumber(jsonTable.error.code)] or self.API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..'</span>')
					end
				else
					fibaro:debug('<span style="color:red;">Error : API Authentication failure, empty response</span>')
				end			
			else
				fibaro:debug('<span style="color:red;">Error : API Authentication failure, errorCode='..errorCode..', status='..status..'</span>')
			end
		end,
		-- Destroy current login session
		Destroy = function(self, pathAuth, SID)
			fibaro:debug("Destroy current SID")
			local payload = "/webapi/"..pathAuth.."?api=SYNO.API.Auth&method=Logout&version=2&session=SurveillanceStation&_sid="..SID
			local response, status, errorCode = self.Synology:GET(payload)
		end,
		-- Main code
		main = function(self)
			-- Discover available APIs and corresponding information
			local payload = "/webapi/query.cgi?api=SYNO.API.Info&method=Query&version=1&query=SYNO.API.Auth,SYNO.SurveillanceStation.Camera"
			local response, status, errorCode = self.Synology:GET(payload)
			if tonumber(errorCode) == 0 and tonumber(status) == 200 then
				if response ~= nil and response ~= "" then
					local jsonTable = json.decode(response)
					if jsonTable.data["SYNO.API.Auth"] ~= nil and jsonTable.data["SYNO.SurveillanceStation.Camera"] ~= nil then
						if jsonTable.data["SYNO.API.Auth"].maxVersion >= 2 and jsonTable.data["SYNO.SurveillanceStation.Camera"].maxVersion >= 4 then
							local pathAuth = jsonTable.data["SYNO.API.Auth"].path
							local pathCamera = jsonTable.data["SYNO.SurveillanceStation.Camera"].path
							-- Get SID
							local SID = fibaro:getGlobal('SurvStation_SID')
							if SID == nil or SID == "" then
								-- No SID, need a new one
								SurvStation:GetSID(pathAuth)
								SID = fibaro:getGlobal('SurvStation_SID')
							end
							-- Get list of all cameras
							payload = "/webapi/"..pathCamera.."?api=SYNO.SurveillanceStation.Camera&method=List&version=1&_sid="..SID
							response, status, errorCode = self.Synology:GET(payload)
							if tonumber(errorCode) == 0 and tonumber(status) == 200 then
								if response ~= nil and response ~= "" then
									jsonTable = json.decode(response)
									if jsonTable.success == true then
										local recording = 0
										local disabled = 0
										local activating = 0
										local disabling = 0
										local restarting = 0
										local unknown = 0
										local enabled = 0
										if jsonTable.data.total > 0 then
											local nbcameras = #jsonTable.data.cameras
											for i = 1, nbcameras do
												local camera = false
												if cameras then
													for _, v in ipairs(cameras) do
														if v == jsonTable.data.cameras[i].id then
															camera = true
															break
														end
													end
												end
												if camera then
													-- Check current recording status
													if jsonTable.data.cameras[i].recStatus > 0 then
														fibaro:debug('<span style="color:green;">Found recording camera <b>'..jsonTable.data.cameras[i].name..'</b> ID=<b>'..jsonTable.data.cameras[i].id..'</b></span>')
														recording = recording + 1
													end
													-- Check current camera status
													if not jsonTable.data.cameras[i].enabled then
														fibaro:debug('<span style="color:blue;">Found disabled camera <b>'..jsonTable.data.cameras[i].name..'</b> ID=<b>'..jsonTable.data.cameras[i].id..'</b></span>')
														disabled = disabled + 1
													end
													if jsonTable.data.cameras[i].status == 0 then enabled = enabled + 1
													elseif jsonTable.data.cameras[i].status == 1 then disabled = disabled + 1
													elseif jsonTable.data.cameras[i].status == 2 then activating = activating + 1
													elseif jsonTable.data.cameras[i].status == 3 then disabling = disabling + 1
													elseif jsonTable.data.cameras[i].status == 4 then restarting = restarting + 1
													elseif jsonTable.data.cameras[i].status == 5 then unknown = unknown + 1
													end
												end
											end
										else
											fibaro:debug('No camera found')
										end
										-- Log camera status, update label, and change icon accordingly
										local currentIcon = fibaro:getValue(self.selfID, "currentIcon")
										local statusLabel = fibaro:get(self.selfID, "ui.LabelStatus.value")
										local SurvStation_Status = fibaro:getGlobal(VG_status)
										if recording > 0 then
											fibaro:log("Recording...")
											if tonumber(currentIcon) ~= recordIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", recordIcon)
											end
											if statusLabel ~= "Recording" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Recording\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Recording")
											end
											if SurvStation_Status ~= "Recording" then
												fibaro:setGlobal(VG_status, "Recording")
											end
										elseif disabled > 0 then
											if tonumber(currentIcon) ~= disableIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", disableIcon)
											end
											if statusLabel ~= "Disabled" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Disabled\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Disabled")
											end
											if SurvStation_Status ~= "Disabled" then
												fibaro:setGlobal(VG_status, "Disabled")
											end
										elseif disabling > 0 then
											if tonumber(currentIcon) ~= disableIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", disableIcon)
											end
											if statusLabel ~= "Disabling" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Disabling\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Disabling")
											end
											if SurvStation_Status ~= "Disabling" then
												fibaro:setGlobal(VG_status, "Disabling")
											end
										elseif activating > 0 then
											if tonumber(currentIcon) ~= disableIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", disableIcon)
											end
											if statusLabel ~= "Activating" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Activating\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Activating")
											end
											if SurvStation_Status ~= "Activating" then
												fibaro:setGlobal(VG_status, "Activating")
											end
										elseif restarting > 0 then
											if tonumber(currentIcon) ~= disableIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", disableIcon)
											end
											if statusLabel ~= "Restarting" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Restarting\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Restarting")
											end
											if SurvStation_Status ~= "Restarting" then
												fibaro:setGlobal(VG_status, "Restarting")
											end
										elseif unknown > 0 then
											if tonumber(currentIcon) ~= standbyIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", standbyIcon)
											end
											if statusLabel ~= "Unknown" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Unknown\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Unknown")
											end
											if SurvStation_Status ~= "Unknown" then
												fibaro:setGlobal(VG_status, "Unknown")
											end
										elseif enabled > 0 then
											if tonumber(currentIcon) ~= standbyIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", standbyIcon)
											end
											if statusLabel ~= "Enabled" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"Enabled\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "Enabled")
											end
											if SurvStation_Status ~= "Enabled" then
												fibaro:setGlobal(VG_status, "Enabled")
											end
										else
											if tonumber(currentIcon) ~= standbyIcon then
												fibaro:call(self.selfID, "setProperty", "currentIcon", standbyIcon)
											end
											if statusLabel ~= "???" then
												fibaro:debug("Old Label : \"" .. statusLabel .. "\" => Change to \"???\"")
												fibaro:call(self.selfID, "setProperty", "ui.LabelStatus.value", "???")
											end
											if SurvStation_Status ~= "???" then
												fibaro:setGlobal(VG_status, "???")
											end
										end
									else
										fibaro:debug('<span style="color:red;">Error : Synology Surveillance Station list cameras failed, '..(self.API_CAMERA_ERROR_CODE[tonumber(jsonTable.error.code)] or self.API_COMMON_ERROR_CODE[tonumber(jsonTable.error.code)] or "???")..'</span>')
										-- SID has expired, need a new one
										SurvStation:Destroy(pathAuth, SID)
										SurvStation:GetSID(pathAuth)
									end
								else
									fibaro:debug('<span style="color:red;">Error : Synology Surveillance Station list cameras failed, empty response</span>')
								end
							else
								fibaro:debug('<span style="color:red;">Error : Synology Surveillance Station list cameras failed, errorCode='..errorCode..', status='..status..'</span>')
							end
						else
							fibaro:debug('<span style="color:red;">Error : Synology API version is too old : <b>DSM 4.0-2251</b> and <b>Surveillance Station 6.3</b> are required</span>')
						end
					else
						fibaro:debug('<span style="color:red;">Error : Reload function into memory after a Synology restart</span>')
						SurvStation = nil
					end
				else
					fibaro:debug('<span style="color:red;">Error : Can not connect to Synology server, empty response</span>')
				end
			else
				fibaro:debug('<span style="color:red;">Error : Can not connect to Synology server, errorCode='..errorCode..', status='..status..', payload='..(payload or "")..'</span>')
			end
			-- Display LUA memory consumption every 5 minutes
			local elapsedTime = os.difftime(os.time(), self.garbageExecTime or 0)
			if (elapsedTime >= 300) then
				fibaro:debug('<span style="color:gray;">Total memory in use by Lua: ' .. string.format("%.2f", collectgarbage("count")) .. ' KB</span>')
				self.garbageExecTime = os.time()
			end
			-- Wait
			fibaro:sleep((refresh-3)*1000)
		end -- main
	} -- SurvStation
	fibaro:debug("Function successfully loaded in memory")

	-- Check global variables
	local selfID = fibaro:getSelfId()
	local HC2 = Net.FHttp("127.0.0.1", 11111)
	local response, status, errorCode = HC2:GET("/api/globalVariables/")
	if tonumber(errorCode) == 0 and tonumber(status) == 200 and response ~= nil and response ~= "" then
		local Variables = json.decode(response)
		local Exist = false

		-- SurvStation_SID
		Exist = false
		for _, v in pairs(Variables) do
			if v.name == "SurvStation_SID" then
				fibaro:debug('Global variable "SurvStation_SID" exists')
				Exist = true
				break
			end
		end
		-- Create global variable if it does not exist
		if Exist == false then
			local payload = '{"name":"SurvStation_SID", "isEnum":0, "value":""}'
			local response, status, errorCode = HC2:POST("/api/globalVariables", payload)
			if tonumber(errorCode) == 0 and (tonumber(status) == 200 or tonumber(status) == 201) and response ~= nil and response ~= "" then
				fibaro:debug('Global variable "SurvStation_SID" created')
			else
				fibaro:debug('<span style="display:inline;color:red;">Error : Can not create global variable, errorCode='..errorCode..', status='..status..', payload='..payload..', response='..(response or "")..'</span>')
			end
		end

		-- SurvStation_Status
		Exist = false
		for _, v in pairs(Variables) do
			if v.name == VG_status then 
				fibaro:debug('Global variable "'..VG_status..'" exists')
				Exist = true
				break
			end
		end
		-- Create global variable if it does not exist
		if Exist == false then
			local payload = '{"name":"'..VG_status..'", "isEnum":0, "value":""}'
			local response, status, errorCode = HC2:POST("/api/globalVariables", payload)
			if tonumber(errorCode) == 0 and (tonumber(status) == 200 or tonumber(status) == 201) and response ~= nil and response ~= "" then
				fibaro:debug('Global variable "'..VG_status..'" created')
			else
				fibaro:debug('<span style="display:inline;color:red;">Error : Can not create global variable, errorCode='..errorCode..', status='..status..', payload='..payload..', response='..(response or "")..'</span>')
			end
		end
		fibaro:call(selfID, "setProperty", "ui.LabelVG.value", VG_status)

	else
		fibaro:debug('<span style="display:inline;color:red;">Error : Cannot get global variable list, errorCode='..errorCode..', status='..status..', response='..(response or "")..'</span>')
	end

	-- Get Cameras list
	local camera = false
	if cameras then
		for _, v in ipairs(cameras) do
			if v > 0 then
				camera = true
				break
			end
		end
	end
	if camera then
		-- Update Cameras Label with given IDs
		fibaro:debug('<span style="display:inline;color:yellow;">User cameras : '..json.encode(cameras)..'</span>')
		fibaro:call(selfID, "setProperty", "ui.LabelCameras.value", json.encode(cameras))
	else
		local i = 60
		while not camera do
			if i >= 60 then -- if 60s have elapsed...
				-- Press List button
				fibaro:call(selfID, "setProperty", "ui.LabelCameras.value", "")
				fibaro:debug("No known camera... press List button")
				fibaro:call(selfID, "pressButton", "5")
				i = 0
			end
			fibaro:sleep(1*1000) -- wait 1s
			local label = fibaro:get(selfID, "ui.LabelCameras.value")
			if label ~= nil and label ~= "" then -- if List button has updated label content
				cameras = json.decode(label)
				fibaro:debug('<span style="display:inline;color:yellow;">Discovered cameras : '..json.encode(cameras)..'</span>')
				camera = true
				break
			else
				fibaro:debug('<span style="display:inline;color:orange;">No camera discovered... still trying</span>')
			end
			i = i + 1
		end
	end

end

-- Start
SurvStation:main()
