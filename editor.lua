dofile("$GAME_DATA/Scripts/game/AnimationUtil.lua")
dofile("$GAME_DATA/Scripts/game/Lift.lua")
dofile("$SURVIVAL_DATA/Scripts/util.lua")
dofile("LUAObjectParser.lua")
dofile("Modules.lua")

editor = class()

-- CLIENT/SERVER --

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool.rend"
}

local renderablesTp = {
	"$GAME_DATA/Character/Char_Male/Animations/char_male_tp_connecttool.rend",
	"$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_tp_animlist.rend"
}
local renderablesFp = {
	"$GAME_DATA/Character/Char_Tools/Char_connecttool/char_connecttool_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

local localPlayer = sm.localPlayer
local camera = sm.camera

local create = sm.gui.getKeyBinding("Create", true)
local attack = sm.gui.getKeyBinding("Attack", true)
local force = sm.gui.getKeyBinding("ForceBuild", true)
local toggle = sm.gui.getKeyBinding("NextCreateRotation", true)
local reload = sm.gui.getKeyBinding("Reload", true)

local createStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..create.."To edit selected</p>"
local attackStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..attack.."To multiselect</p>"
local boxAttackStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..attack.."To box select</p>"
local forceStrSelect = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..force.."To select body</p>"
local forceStrDeselect = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..force.."To deselect body</p>"
local forceCreation = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>Hold"..force.."To select creation</p>"
local reloadStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>"..reload.."To open settings</p>"
local boxScaleStr = "<p textShadow='true' bg='gui_keybinds_bg' color='#ffffff' spacing='5'>Box scale: x: %s y: %s z: %s</p>"

local plasticUuid = sm.uuid.new("628b2d61-5ceb-43e9-8334-a4135566df7a")
local lineUuid = sm.uuid.new("992b6953-0026-4e59-ab53-dea0361157bf")
local settingsDir = "$CONTENT_DATA/Settings/toolSettings.json"
local packetSize = 65000
local forceHold = 0.7

local positionButtonMap = {
	["xUp"] = 	sm.vec3.new(1, 0, 0),
	["xDown"] = sm.vec3.new(-1, 0, 0),
	["yUp"] = 	sm.vec3.new(0, 1, 0),
	["yDown"] = sm.vec3.new(0, -1, 0),
	["zUp"] = 	sm.vec3.new(0, 0, 1),
	["zDown"] = sm.vec3.new(0, 0, -1)
}

local rotationButtonMap = {
	["xCw"] =  sm.vec3.new(-1, 0, 0),
	["xACw"] = sm.vec3.new(1, 0, 0),
	["yCw"] =  sm.vec3.new(0, 0, 1),
	["yACw"] = sm.vec3.new(0, 0, -1),
	["zCw"] =  sm.vec3.new(0, -1, 0),
	["zACw"] = sm.vec3.new(0, 1, 0),
}

local function returnBlueprintOrder(exportBody)
    local orderedShapes = {}
    local orderedJoints = {}
    local sortLen = 0
    local sortJoints = {}

    local exportShapes = exportBody:getShapes()

    for i = 1, #exportShapes do
        local shape = exportShapes[i]
        orderedShapes[shape.id] = {1, i}
    end

    local runningIndex = 1
    local creationBodies = exportBody:getCreationBodies()

    for i = 1, #creationBodies do
        local cBody = creationBodies[i]

        if cBody ~= exportBody then
            runningIndex = runningIndex + 1

            local cShapes = cBody:getShapes()

            for k = 1, #cShapes do
                local shape = cShapes[k]
                orderedShapes[shape.id] = {runningIndex, k}
            end
        end

        local joints = cBody:getJoints()

        if joints then
            for j = 1, #joints do
                sortLen = sortLen + 1
                sortJoints[sortLen] = joints[j]
            end
        end
    end

    table.sort(sortJoints, function(a, b)
        return a.id < b.id
    end)

    for i = 1, sortLen do
        orderedJoints[sortJoints[i].id] = i
    end

    return orderedShapes, orderedJoints
end

local function deepCopy(orig)
	local copy

	if type(orig) == "table" then
		copy = {}

		for key, val in pairs(orig) do
			copy[deepCopy(key)] = deepCopy(val)
		end
	else
		copy = orig
	end

	return copy
end

local function beautifyJson(obj, indent)
	indent = indent or 0
	local indentStr = "\t"

	local bracketColors = {"#dbd700", "#CE04B6", "#40a9ff"}
	local function getBracketColor(level)
		return bracketColors[(level - 1) % #bracketColors + 1]
	end

	local function encode(val, level, isUuid)
		local prefix = string.rep(indentStr, level)
		local color = getBracketColor(level + 1)

		if type(val) == "table" then
			local isArray = true
			local maxIndex = 0

			for k, _ in pairs(val) do
				if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
					isArray = false
					break
				end
				if k > maxIndex then maxIndex = k end
			end

			local parts = {}

			if isArray and maxIndex == #val then
				for i = 1, #val do
					table.insert(parts, prefix .. indentStr .. encode(val[i], level + 1))
				end

				return string.format(
					"%s[%s\n%s\n%s%s]",
					color, "#eeeeee",
					table.concat(parts, ",\n"),
					prefix, color
				)
			else
				for k, v in pairs(val) do
					local keyStr
					if type(k) == "number" then
						keyStr = '#eeeeee[' .. "#b5ce89" .. tostring(k) .. "#eeeeee]#94D2E6:#eeeeee "
					else
						keyStr = '#eeeeee"' .. tostring(k) .. '"#94D2E6:#eeeeee '
					end

					local valueStr = encode(v, level + 1, k == "shapeId")
					table.insert(parts, prefix .. indentStr .. keyStr .. valueStr)
				end

				table.sort(parts)
				return string.format(
					"%s{%s\n%s\n%s%s}",
					color, "#eeeeee",
					table.concat(parts, ",\n"),
					prefix, color
				)
			end
		elseif type(val) == "number" then
			return "#b5ce89" .. tostring(val) .. "#eeeeee"
		elseif type(val) == "boolean" then
			return "#094AC1" .. tostring(val) .. "#eeeeee"
		elseif type(val) == "string" then
			local baseStr = '#CD7626"' .. val .. '"#eeeeee'

			if isUuid then
				baseStr = baseStr .. " #888888/*#eeeeee" .. sm.shape.getShapeTitle(sm.uuid.new(val)) .. "#888888*/#eeeeee"
			end

			return baseStr
		elseif val == nil then
			return "#888888null#eeeeee"
		else
			return '#cc0000"Unsupported: ' .. type(val) .. '"#eeeeee'
		end
	end

	return encode(obj, indent)
end


local validColors = {
	["#eeeeee"] = true,
	["#cc0000"] = true,
	["#94D2E6"] = true,
	["#b5ce89"] = true,
	["#094AC1"] = true,
	["#CD7626"] = true,
	["#7a7a7a"] = true,
	["#dbd700"] = true,
	["#CE04B6"] = true,
	["#40a9ff"] = true,
	["#888888"] = true
}

local function uglifyJson(str, keepDoubled)
	str = str:gsub("#%x%x%x%x%x%x", function(string)
		return validColors[string] and "" or string
	end)

	if not keepDoubled then
		str = str:gsub("##", "#")
	end

    return str
end

local function splitString(inputString, chunkSize)
    local chunks = {}

    for i = 1, #inputString, chunkSize do
        local chunk = string.sub(inputString, i, i + chunkSize - 1)
        table.insert(chunks, chunk)
    end

    return chunks
end

local function replaceHexColor(inputStr, newHex)
	local editJson
	local status, error = pcall(function()
		editJson = sm.json.parseJsonString(uglifyJson(inputStr))
	end)

	if not status then
		return true, error
	end

	for _, obj in pairs(editJson) do
		obj.color = newHex
	end

	return false, beautifyJson(editJson)
end

local function convertTimestamp(timestamp)
    local SECONDS_IN_MINUTE = 60
    local SECONDS_IN_HOUR = 3600
    local SECONDS_IN_DAY = 86400
    local SECONDS_IN_YEAR = 31556926

    local function isLeapYear(year)
        return (year % 4 == 0 and year % 100 ~= 0) or (year % 400 == 0)
    end

    local year = 1970
    local remainingSeconds = timestamp

    while remainingSeconds >= SECONDS_IN_YEAR do
        if isLeapYear(year) then
            if remainingSeconds < 366 * SECONDS_IN_DAY then break end
            remainingSeconds = remainingSeconds - 366 * SECONDS_IN_DAY
        else
            if remainingSeconds < 365 * SECONDS_IN_DAY then break end
            remainingSeconds = remainingSeconds - 365 * SECONDS_IN_DAY
        end
        year = year + 1
    end

    local daysInMonth = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    if isLeapYear(year) then
        daysInMonth[2] = 29
    end

    local month = 1
    while remainingSeconds >= daysInMonth[month] * SECONDS_IN_DAY do
        remainingSeconds = remainingSeconds - daysInMonth[month] * SECONDS_IN_DAY
        month = month + 1
    end
    local day = math.floor(remainingSeconds / SECONDS_IN_DAY) + 1
    remainingSeconds = remainingSeconds % SECONDS_IN_DAY

    local hour = math.floor(remainingSeconds / SECONDS_IN_HOUR)
    remainingSeconds = remainingSeconds % SECONDS_IN_HOUR
    local minute = math.floor(remainingSeconds / SECONDS_IN_MINUTE)
    local second = remainingSeconds % SECONDS_IN_MINUTE

    local formattedDate = string.format("%02d/%02d/%04d", day, month, year)
    local formattedTime = string.format("%02d:%02d:%02d", hour, minute, second)

    return formattedDate, formattedTime
end

local function getLength(tbl)
	local count = 0

	for _, v in pairs(tbl) do
		count = count + 1
	end

	return count
end

local function returnFirst(tbl)
	for _, v in pairs(tbl) do
		return v
	end
end

local function destroyEffectTable(table)
	for _, v in pairs(table) do
		if sm.exists(v) then
			v:destroy()
		end
	end
end

local function absVec(vec)
	return sm.vec3.new(math.abs(vec.x), math.abs(vec.y), math.abs(vec.z))
end

local function quatFromMatrix(m)
    local trace = m[1][1] + m[2][2] + m[3][3]
    local q

    if trace > 0 then
        local s = math.sqrt(trace + 1.0) * 2
        q = sm.quat.new(
            (m[3][2] - m[2][3]) / s,
            (m[1][3] - m[3][1]) / s,
            (m[2][1] - m[1][2]) / s,
            0.25 * s
        )
    elseif (m[1][1] > m[2][2] and m[1][1] > m[3][3]) then
        local s = math.sqrt(1.0 + m[1][1] - m[2][2] - m[3][3]) * 2
        q = sm.quat.new(
            0.25 * s,
            (m[1][2] + m[2][1]) / s,
            (m[1][3] + m[3][1]) / s,
            (m[3][2] - m[2][3]) / s
        )
    elseif (m[2][2] > m[3][3]) then
        local s = math.sqrt(1.0 + m[2][2] - m[1][1] - m[3][3]) * 2
        q = sm.quat.new(
            (m[1][2] + m[2][1]) / s,
            0.25 * s,
            (m[2][3] + m[3][2]) / s,
            (m[1][3] - m[3][1]) / s
        )
    else
        local s = math.sqrt(1.0 + m[3][3] - m[1][1] - m[2][2]) * 2
        q = sm.quat.new(
            (m[1][3] + m[3][1]) / s,
            (m[2][3] + m[3][2]) / s,
            0.25 * s,
            (m[2][1] - m[1][2]) / s
        )
    end

    return q
end

local function vectorToAxis(vec)
	local axis

	if vec.x > 0.5 then axis = 1 end
	if vec.y > 0.5 then axis = 2 end
	if vec.z > 0.5 then axis = 3 end

	if vec.x < -0.5 then axis = -1 end
	if vec.y < -0.5 then axis = -2 end
	if vec.z < -0.5 then axis = -3 end

	return axis
end

local function axisToVector(axis)
	local vec = sm.vec3.zero()

	if axis == 1 then vec.x = 1 end
	if axis == 2 then vec.y = 1 end
	if axis == 3 then vec.z = 1 end

	if axis == -1 then vec.x = -1 end
	if axis == -2 then vec.y = -1 end
	if axis == -3 then vec.z = -1 end

	return vec
end

local function quatFromRightUp(right, up)
    right = right:normalize()
    up = up:normalize()

    local forward = right:cross(up):normalize()

    local m = {
        { right.x, up.x, forward.x },
        { right.y, up.y, forward.y },
        { right.z, up.z, forward.z }
    }

    return quatFromMatrix(m)
end

-- SERVER --

function editor:server_onCreate()
	self.sv = {
		export = {},
		settings = {},
		queue = {},
		effect = {
			pointerUpdate = {}
		},
		lift = {},
		owner = self.tool:getOwner(),
	}

	sm.SurvivalBlockAndPartEditor.toolInstance = self.tool
end

function editor:sv_exportSelected(data, player)
	local shapes = data.shapes
	local joints = data.joints
	local body = data.body

	bodyTest = data.body

	if sm.exists(body) then
		local lifted = body:isOnLift()

		local exportedJson, exportedShapeIndexes, exportedJointIndexes = {}, {}, {}
		local oldShapes, oldJoints = {}, {}
		local orderedShapes, orderedJoints = returnBlueprintOrder(body)
		local creationJson = sm.creation.exportToTable(body, true, lifted)
		local exportError

		for _, shape in pairs(shapes) do
			local found

			if sm.exists(shape) then
				local indexData = orderedShapes[shape.id]

				if indexData then
					local bodyIndex, shapeIndex = indexData[1], indexData[2]

					table.insert(exportedJson, creationJson.bodies[bodyIndex].childs[shapeIndex])
					table.insert(exportedShapeIndexes, {i1 = bodyIndex, i2 = shapeIndex, i3 = #exportedJson})
					table.insert(oldShapes, shape)

					found = true
				end
			end

			exportError = not found
		end

		for _, joint in pairs(joints) do
			local jointIndex = orderedJoints[joint.id]
		
			if jointIndex then
				table.insert(exportedJson, creationJson.joints[jointIndex])
				table.insert(exportedJointIndexes, {i1 = jointIndex, i2 = #exportedJson})
				table.insert(oldJoints, joint)
			else
				exportError = true
			end
		end

		if exportError then
			self.network:sendToClient(player, "cl_errorChatMessage", "#ff0000Unable to export all selected shapes/joints")
		end

		local jsonStr = beautifyJson(exportedJson)
		local strings = splitString(jsonStr, packetSize)

		for i, string in pairs(strings) do
			local finished = i == #strings
			self.network:sendToClient(player, "cl_rebuildJson", {string = string, finished = finished, i = i})
		end

		self.sv.export[player.id] = self.sv.export[player.id] or {}
		local exportData = self.sv.export[player.id]
		
		exportData.originalJson = creationJson
		
		print("Экспорт Json ",self.sv.export[player.id])

		--/ Зкспорт Json из мира (exportData)

		exportData.exportedShapeIndexes = exportedShapeIndexes
		exportData.exportedJointIndexes = exportedJointIndexes
		exportData.oldJson = creationJson
		exportData.oldBody = body
		exportData.oldShapes = oldShapes
		exportData.oldJoints = oldJoints
	else
		self.network:sendToClient(player, "cl_errorChatMessage", "#ff0000Unable to re-export creation")
		self.network:sendToClient(player, "cl_closeGui")
		
		self:sv_importErrorReset(player)
	end
end

function editor:sv_rebuildJson(data, player)
	local exportData = self.sv.export[player.id]

	if data.i == 1 then
        exportData.json = data.string
    else
        exportData.json = exportData.json..data.string
    end

    if data.finished then
		local status, err = pcall(function()
			exportData.json = sm.json.parseJsonString(exportData.json)
		end)

		if type(exportData.json) ~= "table" and not err then
			self.network:sendToClient(player, "cl_errorChatMessage", "#ff0000".."Json string parsed to incorrect format")

			self:sv_importErrorReset(player)
		elseif not status then
			err = err:sub(64, #err)
			self.network:sendToClient(player, "cl_errorChatMessage", "#ff0000"..err)

			self:sv_importErrorReset(player)
		else
        	self:sv_importJson(player, data.partialExport, data.forceExport)
		end
    end
end

function editor:sv_importJson(player, partialExport, forceExport)
	local refindShapeIndexes, refindJointIndexes = {}, {}
	local findJointIds = {}
	local findShapeIds = {}
	local exportData = self.sv.export[player.id]
	local specialInstruction = exportData.specialInstruction

----
	local original = exportData.originalJson

	if not original then
		self.network:sendToClient(player, "cl_errorChatMessage", "Невозможно применить изменения: исходный JSON не найден.")
	    return
	end

	local recreated = self:createJsonFromShapes(exportData.shapes, exportData.joints)

	if not recreated or recreated == "" then
		self.network:sendToClient(player, "cl_errorChatMessage", "Объект был удалён на сервере. Применение отменено.")
	    return
	end

	if recreated ~= original then
		self.network:sendToClient(player, "cl_errorChatMessage", "Объект был изменён на сервере. Применение отменено.")
	    return
	end
----

	for i, data in pairs(exportData.exportedShapeIndexes) do
		local jsonData = exportData.json[data.i3]

		if jsonData then
			if specialInstruction then
				if specialInstruction.name == "move" then
					jsonData.pos.x = jsonData.pos.x + specialInstruction.data.x
					jsonData.pos.y = jsonData.pos.y + specialInstruction.data.y
					jsonData.pos.z = jsonData.pos.z + specialInstruction.data.z
				elseif specialInstruction.name == "rotate" then
					local rot = specialInstruction.data
					local shape = exportData.oldShapes[i]
					local isBlock = shape.isBlock

					if isBlock then
						rot.y = rot.y * -1
						rot.x = rot.x * -1
					end

					local isNeg = rot.x < 0 or rot.y < 0 or rot.z < 0

					local right, up = axisToVector(jsonData.xaxis), axisToVector(jsonData.zaxis)
					local quat = quatFromRightUp(right, up)

					local rotQuat = sm.quat.angleAxis(isNeg and math.rad(270) or math.rad(90), absVec(rot))
					local translatedQuat = quat * rotQuat
					local newUp, newRight = sm.quat.getUp(translatedQuat), sm.quat.getRight(translatedQuat)

					jsonData.xaxis = vectorToAxis(newRight)
					jsonData.zaxis = vectorToAxis(newUp)

					local xaxis = shape:getXAxis()
					local yaxis = shape:getYAxis()
					local zaxis = shape:getZAxis()

					if rot.z ~= 0 then -- y
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + zaxis.x
							jsonData.pos.y = jsonData.pos.y + zaxis.y
							jsonData.pos.z = jsonData.pos.z + zaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + xaxis.x
							jsonData.pos.y = jsonData.pos.y + xaxis.y
							jsonData.pos.z = jsonData.pos.z + xaxis.z
						end
					elseif rot.y ~= 0 then -- z
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + yaxis.x
							jsonData.pos.y = jsonData.pos.y + yaxis.y
							jsonData.pos.z = jsonData.pos.z + yaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + xaxis.x
							jsonData.pos.y = jsonData.pos.y + xaxis.y
							jsonData.pos.z = jsonData.pos.z + xaxis.z
						end
					else
						if isNeg then
							jsonData.pos.x = jsonData.pos.x + zaxis.x
							jsonData.pos.y = jsonData.pos.y + zaxis.y
							jsonData.pos.z = jsonData.pos.z + zaxis.z
						else
							jsonData.pos.x = jsonData.pos.x + yaxis.x
							jsonData.pos.y = jsonData.pos.y + yaxis.y
							jsonData.pos.z = jsonData.pos.z + yaxis.z
						end
					end
				end
			end

			local randomColor = sm.color.new(math.random(1, 255) / 255, math.random(1, 255) / 255, math.random(1, 255) / 255)

			refindShapeIndexes[tostring(randomColor)] = sm.color.new(jsonData.color)
			jsonData.color = tostring(randomColor):sub(1, 6)

			exportData.oldJson.bodies[data.i1].childs[data.i2] = jsonData
		else
			for _, shape in pairs(exportData.oldShapes) do
				if sm.exists(shape) then
					shape:destroyShape()
				end
			end

			self.network:sendToClient(player, "cl_setQueueValid", true)
			self.network:sendToClient(player, "cl_closeGui")

			return
		end
	end

	for _, data in pairs(exportData.exportedJointIndexes) do
		local jsonData = exportData.json[data.i2]

		if jsonData then
			if specialInstruction then
				if specialInstruction.name == "move" then
					jsonData.posA.x = jsonData.posA.x + specialInstruction.data.x
					jsonData.posA.y = jsonData.posA.y + specialInstruction.data.y
					jsonData.posA.z = jsonData.posA.z + specialInstruction.data.z

					jsonData.posB.x = jsonData.posB.x + specialInstruction.data.x
					jsonData.posB.y = jsonData.posB.y + specialInstruction.data.y
					jsonData.posB.z = jsonData.posB.z + specialInstruction.data.z

				elseif specialInstruction.name == "wonkify" then
					if sm.shape.getShapeTitle(sm.uuid.new(jsonData.shapeId)):sub(1, 6) == "Piston" then
						local zaxisA = jsonData.zaxisA
						
						jsonData.zaxisB = zaxisA
						jsonData.xaxisA = zaxisA
						jsonData.xaxisB = zaxisA
					else
						jsonData.xaxisA = jsonData.zaxisA
						jsonData.xaxisB = jsonData.zaxisA
					end
				end
			end

			local randomColor = sm.color.new(math.random(1, 255) / 255, math.random(1, 255) / 255, math.random(1, 255) / 255)

			refindJointIndexes[tostring(randomColor)] = sm.color.new(jsonData.color)
			jsonData.color = tostring(randomColor):sub(1, 6)
		else
			local joint = exportData.oldJson.joints[data.i1]

			if joint then
				findJointIds[joint.id] = true

				local controller = joint.controller

				if controller then
					findJointIds[controller.id] = true
				end
			end
		end

		exportData.oldJson.joints[data.i1] = jsonData
	end

	if getLength(findShapeIds) > 0 then
		for _, body in pairs(exportData.oldJson.bodies) do
			for _, child in pairs(body.childs) do
				if child.controller and child.controller.controllers then
					for _, controller in pairs(child.controller.controllers) do
						local find = findShapeIds[controller.id]

						if find then
							local newData = deepCopy(controller)
							newData.id = find

							table.insert(child.controller.controllers, newData)
						end
					end
				end
			end
		end
	end

	local function indexRestructure(controller)
		local jointStruct = {}

		if controller.joints then
			for _, data in pairs(controller.joints) do
				jointStruct[data.index + 1] = data.id
			end
		end

		if controller.controllers then
			for _, data in pairs(controller.controllers) do
				jointStruct[data.index + 1] = data.id
			end
		end

		local newIndex = 0

		for _, jointId in pairs(jointStruct) do
			if controller.joints then
				for _, data in pairs(controller.joints) do
					if data.id == jointId then
						data.index = newIndex
						break
					end
				end
			end

			if controller.controllers then
				for _, data in pairs(controller.controllers) do
					if data.id == jointId then
						data.index = newIndex
						break
					end
				end
			end

			newIndex = newIndex + 1
		end
	end

	if getLength(findJointIds) > 0 then
		for _, body in pairs(exportData.oldJson.bodies) do
			for _, child in pairs(body.childs) do
				if child.controller then
					if child.controller.joints then
						for i, data in pairs(child.controller.joints) do
							local find = findJointIds[data.id]

							if find then
								if type(find) == "boolean" then
									local hasIndex = child.controller.joints[i].index

									child.controller.joints[i] = nil

									if hasIndex then
										indexRestructure(child.controller)
									end	
								else
									local newData = deepCopy(data)

									newData.id = find

									if data.index then
										newData.index = #child.controller.joints + 
										(child.controller.controllers and #child.controller.controllers or 0)

										if newData.index < 10 then
											table.insert(child.controller.joints, newData)
										end
									else
										table.insert(child.controller.joints, newData)
									end
								end
							end
						end
					end

					if child.controller.controllers then
						for i, data in pairs(child.controller.controllers) do
							local find = findJointIds[data.id]

							if find then
								if type(find) == "boolean" then
									local hasIndex = child.controller.controllers[i].index

									child.controller.controllers[i] = nil

									if hasIndex then
										indexRestructure(child.controller)
									end	
								else
									local newData = deepCopy(data)

									newData.id = find

									if data.index then
										newData.index = #child.controller.controllers + 
										(child.controller.joints and #child.controller.joints or 0)

										if newData.index < 10 then
											table.insert(child.controller.controllers, newData)
										end
									else
										table.insert(child.controller.controllers, newData)
									end
								end
							end
						end
					end

					if child.controller.steering then
						for _, data in pairs(child.controller.steering) do
							local find = findJointIds[data.id]

							if find then
								local newData = deepCopy(data)

								newData.id = find
								table.insert(child.controller.steering, newData)
							end
						end
					end
				end
			end
		end
	end

	exportData.specialInstruction = nil

	local isLifted = false

	if sm.exists(exportData.oldBody) then
		isLifted = exportData.oldBody:isOnLift()

		if not isLifted then
			local transformCreation = sm.creation.exportToTable(exportData.oldBody, true, exportData.oldBody:isOnLift())

			for i, body in pairs(transformCreation.bodies) do
				exportData.oldJson.bodies[i].transform = body.transform
			end
		end
	end

	if partialExport then
		local jsonString = sm.json.writeJsonString(exportData.oldJson)
		local strings = splitString(jsonString, packetSize)

		for i, string in pairs(strings) do
			self.network:sendToClient(player, "cl_setCreationVisualization", {string = string, finished = i == #strings})
		end

		self:sv_importErrorReset(player)
		return
	end

	if not self.sv.settings[player.id].autoApply and not forceExport then
		local foundJson = {}
		local exportedShapeIndexes = {}
		local exportedJointIndexes = {}

		if exportData.oldJson.bodies then
			for i, body in pairs(exportData.oldJson.bodies) do
				for j, child in pairs(body.childs) do
					local foundColor = refindShapeIndexes[tostring(sm.color.new(child.color))]

					if foundColor then
						child.color = tostring(foundColor):sub(1, 6)
						table.insert(foundJson, child)
						table.insert(exportedShapeIndexes, {i1 = i, i2 = j, i3 = #foundJson})
					end
				end
			end
		end

		if exportData.oldJson.joints then
			for i, joint in pairs(exportData.oldJson.joints) do
				local foundColor = refindJointIndexes[tostring(sm.color.new(joint.color))]

				if foundColor then
					joint.color = tostring(foundColor):sub(1, 6)
					table.insert(foundJson, joint)
					table.insert(exportedJointIndexes, {i1 = i, i2 = #foundJson})
				end
			end
		end

		exportData.exportedShapeIndexes = exportedShapeIndexes
		exportData.exportedJointIndexes = exportedJointIndexes
		exportData.json = foundJson

		local jsonString = beautifyJson(foundJson)
		local strings = splitString(jsonString, packetSize)

		for i, string in pairs(strings) do
			local finished = i == #strings
			self.network:sendToClient(player, "cl_rebuildJson", {string = string, finished = finished, i = i, onlySet = true})
		end

		self:sv_importErrorReset(player)

		return
	end

	exportData.creation = sm.creation.importFromString(sm.world.getCurrentWorld(), sm.json.writeJsonString(exportData.oldJson), _, _, true)

	if exportData.creation then
		local exportBody

		for _, body in pairs(exportData.creation) do
			if sm.exists(body) then
				exportBody = body
				break
			end
		end

		local liftData = sm.SurvivalBlockAndPartEditor.liftData

		if liftData and isLifted then
			local liftPlayer = player
			local liftLen = getLength(liftData)

			if liftLen > 1 and sm.exists(exportData.oldBody) then
				local randomShape = exportData.oldBody:getCreationShapes()[1]

				for _, lift in pairs(liftData) do
					for _, shape in pairs(lift.selectedShapes) do
						if sm.exists(shape) and sm.exists(randomShape) and shape.body.id == randomShape.body.id then
							liftPlayer = lift.player
							break
						end
					end
				end
			elseif liftLen == 1 then
				local _, data = next(liftData)
				liftPlayer = data.player
			end

			local hookedLift = liftData[liftPlayer.id]
			local lowest
			local highest

			for _, body in pairs(exportData.creation) do
				local low, high = body:getWorldAabb()

				if not lowest then 
					lowest = low 
				end
				if not highest then 
					highest = high 
				end

				lowest = lowest:min(low)
				highest = highest:max(high)
			end

			local bb = highest - lowest
			local creationCenter = lowest + (bb) / 2
			local difference = (creationCenter - hookedLift.liftPosition / 4) * 4

			if difference.x >= -1 and difference.x < 0 then 
				difference.x = 0 
			elseif difference.x <= 1 and difference.x > 0 then
				difference.x = 0 
			end

			if difference.y >= -1 and difference.y < 0 then 
				difference.y = 0 
			elseif  difference.y <= 1 and difference.y > 0 then
				difference.y = 0 
			end

			difference.z = 0

			if sm.exists(exportData.oldBody) then
				for _, shape in pairs(exportData.oldBody:getCreationShapes()) do
					shape:destroyShape()
				end
			end

			sm.player.placeLift(liftPlayer, exportData.creation, hookedLift.liftPosition + difference, hookedLift.liftLevel, hookedLift.rotationIndex)

			self:sv_refindImported(refindShapeIndexes, refindJointIndexes, exportBody, player)
		else
			if sm.exists(exportData.oldBody) then
				for _, shape in pairs(exportData.oldBody:getCreationShapes()) do
					shape:destroyShape()
				end
			end

			self:sv_refindImported(refindShapeIndexes, refindJointIndexes, exportBody, player)
		end
	else
		self.network:sendToClient(player, "cl_errorChatMessage", "#ff0000Failed to import creation")

		self:sv_importErrorReset(player)
	end
end

function editor:sv_importErrorReset(player)
	self.sv.queue[player.id] = nil

	self.network:sendToClient(player, "cl_setJsonSet", true)
	self.network:sendToClient(player, "cl_setQueueValid", true)
end

--/ Сервер: Каждые 1/40 сек
function editor:server_onFixedUpdate()
	for i, queueData in pairs(self.sv.queue) do
		local exportBody = sm.exists(queueData.data.body) and queueData.data.body or nil

		if not exportBody then
			for _, shape in pairs(queueData.data.shapes) do
				if sm.exists(shape) then
					local body = shape.body

					if sm.exists(body) then
						exportBody = body
						break
					end
				end
			end

			if not exportBody then
				for _, joint in pairs(queueData.data.joints) do
					if sm.exists(joint) then
						local bodyA = joint.shapeA.body

						if sm.exists(bodyA) then
							exportBody = bodyA
							break
						end

						if joint.shapeB then
							if sm.exists(joint.shapeB.body) then
								exportBody = joint.shapeB.body
								break
							end
						end
					end
				end
			end

			queueData.data.body = exportBody
		end

		if exportBody then
			local gameTick = sm.game.getCurrentTick()
			local hasChanged = false

			for _, body in pairs(exportBody:getCreationBodies()) do
				if body:hasChanged(queueData.lastUpdate - 6) then
					queueData.lastUpdate = gameTick

					hasChanged = true
					break
				end
			end

			local changeBasedUpdate = not hasChanged and queueData.data.count < 1000 and queueData.tick + 80 > gameTick
			local timeBasedUpdate = queueData.tick + queueData.data.count / 25 < gameTick and queueData.tick + 80 < gameTick

			if (changeBasedUpdate or timeBasedUpdate) and queueData.hasChanged and queueData.tick + 6 < gameTick then
				local player = queueData.player

				self:sv_exportSelected(queueData.data, player)

				local _, v1 = next(queueData.data.shapes)
				local _, v2 = next(queueData.data.joints)

				if self.sv.effect.pointerUpdate[player.id] then
					self.network:sendToClient(player, "cl_setPointerShape", v1 or v2)
					self.sv.effect.pointerUpdate[player.id] = false
				end

				self.network:sendToClient(player, "cl_setNewObjects", {queueData.data.shapes, queueData.data.joints})
				self.network:sendToClient(player, "cl_setQueueValid", true)
				self.sv.queue[i] = nil
			end

			if not queueData.hasChanged and hasChanged then
				queueData.hasChanged = true
			end
		else
			self.network:sendToClient(queueData.player, "cl_errorChatMessage", "#ff0000Unable to re-export creation")
			self:sv_importErrorReset(queueData.player)

			self.network:sendToClient(queueData.player, "cl_closeGui")

			self.sv.queue[i] = nil
		end
	end
end

function editor:sv_setSpecialInstruction(data, player)

	self:cl_ChatMessage("sv_setSpecialInstruction(data, player)")--

	self.sv.export[player.id].specialInstruction = data
end

function editor:sv_refindImported(refindShapeIndexes, refindJointIndexes, body, player)
	local foundShapes, foundJoints = {}, {}
	local newPointerEffect
	local count = 0
	local refindError

	for _, shape in pairs(body:getCreationShapes()) do
		local refind = refindShapeIndexes[tostring(shape.color)]

		if refind then
			shape.color = refind
			foundShapes[shape.id] = shape

			if not newPointerEffect then
				newPointerEffect = shape
			end
		end

		if shape.interactable then
			count = count + 1
		end
	end

	for _, joint in pairs(body:getCreationJoints()) do
		local refind = refindJointIndexes[tostring(joint.color)]

		if refind then
			joint.color = refind
			foundJoints[joint.id] = joint

			if not newPointerEffect then
				newPointerEffect = joint
			end
		end

		count = count + 1
	end

	if refindError then
		self:cl_errorChatMessage("#ff0000Unable to refind all selected shapes/joints")
	end

	if getLength(foundShapes) > 0 or getLength(foundJoints) > 0 then
		self.sv.queue[player.id] = {
			data = {
				shapes = foundShapes,
				joints = foundJoints,
				body = body,
				count = count
			},
			hasChanged = false,
			player = player,
			tick = sm.game.getCurrentTick(),
			lastUpdate = sm.game.getCurrentTick()
		}

		self.network:sendToClient(player, "cl_postImportClear")
	else
		self.network:sendToClient(player, "cl_setQueueValid", true)
		self.network:sendToClient(player, "cl_closeGui")
	end
end

function editor:sv_updateSettings(settingData, player)
	self.sv.settings[player.id] = self.sv.settings[player.id] or {}
	self.sv.settings[player.id][settingData[1]] = settingData[2]
end

function editor:sv_updatePointer(_, player)
	self.sv.effect.pointerUpdate[player.id] = true
end

function editor:sv_setLiftLevel(level, player)
	if sm.SurvivalBlockAndPartEditor.liftData then
		local liftData = sm.SurvivalBlockAndPartEditor.liftData[player.id]

		if liftData then
			liftData.liftLevel = level
		end
	end
end

-- CLIENT --

--/ Когда объект создаётся
function editor:client_onCreate()
	self:cl_loadAnimations()

	self.cl = {
		effect = {
			pointerEffect = sm.effect.createEffect("ShapeRenderable"),
			boxEffect = sm.effect.createEffect("ShapeRenderable"),
			selectedShapeEffects = {},
			shapePositions = {},
			selectedJointEffects = {},
			jointPositions = {},
			jointOffsets = {},
			hostedEffects = {},
			pointerPosition = sm.vec3.zero()
		},
		selectedShapes = {},
		selectedJoints = {},
		export = {},
		lift = {},
		queue = {
			valid = true
		},
		color = {
			rgb = sm.color.new(0, 0, 0),
			isValid = true,
			hex = "000000",
			extraVisible = false
		},
		rotationAxis = false,
		moveAmmount = 1,
		selectionFilter = 1
	}

	self.cl.effect.pointerEffect:setParameter("visualization", true)
	self.cl.effect.boxEffect:setParameter("visualization", true)

	self.cl.effect.boxEffect:setParameter("uuid", plasticUuid)

	self.cl.gui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/Json_Editor_Layout_Side.layout")
	self.cl.gui:setOnCloseCallback("cl_onClose")

	self.cl.gui:setButtonCallback("Done", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zUp", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zDown", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("xACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("yACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zCw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("zACw", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("wonkify", "cl_onButtonPress")
	self.cl.gui:setButtonCallback("Close", "cl_closeGui")
	self.cl.gui:setButtonCallback("exitButton", "cl_closeGui")
	self.cl.gui:setButtonCallback("Rotation Axis", "cl_axisChange")
	self.cl.gui:setButtonCallback("applyAll", "cl_applyAll")
	self.cl.gui:setButtonCallback("expandColors", "cl_onExpand")

	self.cl.gui:setTextChangedCallback("hexText", "cl_onHexUpdate")
	self.cl.gui:setTextChangedCallback("moveAmmount", "cl_moveUpdate")

	self.cl.gui:createHorizontalSlider("rSlider", 256, 0, "cl_onRSliderUpdate")
	self.cl.gui:createHorizontalSlider("gSlider", 256, 0, "cl_onGSliderUpdate")
	self.cl.gui:createHorizontalSlider("bSlider", 256, 0, "cl_onBSliderUpdate")

	self.cl.settingsGui = sm.gui.createGuiFromLayout("$CONTENT_DATA/Gui/Layouts/Tool_Settings.layout")
	self.cl.settingsGui:setButtonCallback("Close", "cl_closeSettings")
	self.cl.settingsGui:setButtonCallback("effectQuality", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("axisType", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("selectionType", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("clickExit", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("childDetection", "cl_onSettingChange")
	self.cl.settingsGui:setButtonCallback("autoApply", "cl_onSettingChange")

	self.cl.settingsGui:createDropDown("selectionFilter", "cl_onDropDown", {"Shapes And Joints", "Joints", "Shapes"})

	for i = 1, 40 do
		if i < 10 then
			self.cl.gui:setButtonCallback("0"..i.."_paintColor", "cl_setPaintColor")
		else
			self.cl.gui:setButtonCallback(i.."_paintColor", "cl_setPaintColor")
		end

		self.cl.gui:setColor(i.."_paintIcon", sm.color.new(PAINT_COLORS[i]))
	end

	local json

	local settingsTbl = sm.json.open(settingsDir)

	self.cl.effect.isFancy = settingsTbl.fancyEffects

	if self.cl.effect.isFancy then
		self.cl.settingsGui:setText("effectQuality", "Fancy")
	else
		self.cl.settingsGui:setText("effectQuality", "Fast")
	end

	self.cl.boxSelect = settingsTbl.boxSelect

	if self.cl.boxSelect then
		self.cl.settingsGui:setText("selectionType", "Box")
	else
		self.cl.settingsGui:setText("selectionType", "Shape")
	end

	self.cl.clickExit = settingsTbl.clickExit

	if self.cl.clickExit then
		self.cl.settingsGui:setText("clickExit", "#00aa00Enabled")
	else
		self.cl.settingsGui:setText("clickExit", "#aa0000Disabled")
	end

	self.cl.childDetection = settingsTbl.childDetection

	if self.cl.childDetection then
		self.cl.settingsGui:setText("childDetection", "#00aa00Enabled")
	else
		self.cl.settingsGui:setText("childDetection", "#aa0000Disabled")
	end

	self.cl.autoApply = settingsTbl.autoApply

	if self.cl.autoApply then
		self.cl.settingsGui:setText("autoApply", "#00aa00Enabled")
	else
		self.cl.settingsGui:setText("autoApply", "#aa0000Disabled")
	end

	self.network:sendToServer("sv_updateSettings", {"childDetection", self.cl.childDetection})
	self.network:sendToServer("sv_updateSettings", {"autoApply", self.cl.autoApply})

	self.cl.effect.xEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
	self.cl.effect.yEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)
	self.cl.effect.zEffect = sm.gui.createWorldIconGui(20, 20, "$GAME_DATA/Gui/Layouts/Hud/Hud_WorldIcon.layout", false)

	self.cl.effect.xLine = sm.effect.createEffect("ShapeRenderable")
	self.cl.effect.yLine = sm.effect.createEffect("ShapeRenderable")
	self.cl.effect.zLine = sm.effect.createEffect("ShapeRenderable")

	self.cl.effect.xEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/x.png")
	self.cl.effect.yEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/y.png")
	self.cl.effect.zEffect:setImage("Icon", "$CONTENT_DATA/Gui/HUD/z.png")

	self.cl.effect.xLine:setParameter("uuid", lineUuid)
	self.cl.effect.yLine:setParameter("uuid", lineUuid)
	self.cl.effect.zLine:setParameter("uuid", lineUuid)

	self.cl.effect.xLine:setParameter("color", sm.color.new("ff0000"))
	self.cl.effect.yLine:setParameter("color", sm.color.new("00ff00"))
	self.cl.effect.zLine:setParameter("color", sm.color.new("0000ff"))

	local lineScale = sm.vec3.new(0.01, 0.45, 0.01)

	self.cl.effect.xLine:setScale(lineScale)
	self.cl.effect.yLine:setScale(lineScale)
	self.cl.effect.zLine:setScale(lineScale)

	self.cl.effect.xEffect:setColor("Icon", sm.color.new("#ff0000"))
	self.cl.effect.yEffect:setColor("Icon",  sm.color.new("#00ff00"))
	self.cl.effect.zEffect:setColor("Icon",  sm.color.new("#0000ff"))

	self.cl.effect.xEffect:open()
	self.cl.effect.yEffect:open()
	self.cl.effect.zEffect:open()
end

function editor:cl_loadAnimations()

	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			idle = { "connecttool_idle" },
			pickup = { "connecttool_pickup", { nextAnimation = "idle" } },
			putdown = { "connecttool_putdown" },
		}
	)
	local movementAnimations = {
		idle = "connecttool_idle",
		idleRelaxed = "connecttool_idle_relaxed",

		sprint = "connecttool_sprint",
		runFwd = "connecttool_run_fwd",
		runBwd = "connecttool_run_bwd",

		jump = "connecttool_jump",
		jumpUp = "connecttool_jump_up",
		jumpDown = "connecttool_jump_down",

		land = "connecttool_jump_land",
		landFwd = "connecttool_jump_land_fwd",
		landBwd = "connecttool_jump_land_bwd",

		crouchIdle = "connecttool_crouch_idle",
		crouchFwd = "connecttool_crouch_fwd",
		crouchBwd = "connecttool_crouch_bwd"
	}

	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.tool:isLocal() then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "connecttool_pickup", { nextAnimation = "idle" } },
				unequip = { "connecttool_putdown" },

				idle = { "connecttool_idle", { looping = true } },
				idleFlip = { "connecttool_idle_flip", { nextAnimation = "idle", blendNext = 0.5 } },
				idleUse = { "connecttool_use_idle", { nextAnimation = "idle", blendNext = 0.5 } },

				sprintInto = { "connecttool_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 5.0 } },
				sprintExit = { "connecttool_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "connecttool_sprint_idle", { looping = true } },
			}
		)
	end
	self.blendTime = 0.2
end

function editor:cl_onAnimUpdate(dt)
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.tool:isLocal() then
		if self.equipped then
			if self.fpAnimations.currentAnimation ~= "idleFlip" then
				if isSprinting and self.fpAnimations.currentAnimation ~= "sprintInto" and self.fpAnimations.currentAnimation ~= "sprintIdle" then
					swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
				elseif not self.tool:isSprinting() and ( self.fpAnimations.currentAnimation == "sprintIdle" or self.fpAnimations.currentAnimation == "sprintInto" ) then
					swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
				end
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			if animation.time >= animation.info.duration - self.blendTime then
				if name == "pickup" then
					setTpAnimation( self.tpAnimations, "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		end
	end
end

--/ Клиент: Каждый кадр
function editor:client_onUpdate(dt)
	self:cl_onAnimUpdate(dt)
	
	if self.tool:isLocal() and self.tool:isEquipped() then
		local scaleModify = sm.vec3.one() / 500
		local selectedShape = self.cl.effect.selectedShape

		if sm.exists(selectedShape) and not self.cl.deselect and not (self.cl.selectedShapes[selectedShape.id] or self.cl.selectedJoints[selectedShape.id]) then
			local shapeType = type(selectedShape)
			local isShape = shapeType == "Shape"

			if (selectedShape.id ~= self.cl.effect.lastSelectedId) or shapeType ~= self.cl.effect.lastSelectedType then
				self.cl.effect.pointerOffset = nil
				self.cl.effect.lastSelectedId = selectedShape.id
				self.cl.effect.lastSelectedType = shapeType

				if self.cl.effect.pointerEffect:isPlaying() then 
					self.cl.effect.pointerEffect:stop()
				end

				if isShape then
					local isPart = not (selectedShape.isBlock or selectedShape.isWedge)
					local uuid = not selectedShape.isBlock and selectedShape.uuid or plasticUuid
					local scale = isPart and sm.vec3.one() / 4 or selectedShape:getBoundingBox()
		
					self.cl.effect.pointerEffect:setParameter("uuid", uuid)
					self.cl.effect.pointerEffect:setScale(scale + (not isPart and scaleModify or sm.vec3.zero()))
				else
					self.cl.effect.pointerEffect:setParameter("uuid", selectedShape.uuid)
					self.cl.effect.pointerEffect:setScale(sm.vec3.one() / 4)

					self.cl.effect.pointerOffset = selectedShape.shapeA:transformPoint(selectedShape.worldPosition)
				end

				if not self.cl.boxSelect then
					self.cl.effect.pointerEffect:start()
				end
			end

			local position, rotation = sm.vec3.zero(), sm.quat.identity()

			if self.cl.effect.isFancy then
				if isShape then
					local angularVelocity = selectedShape.body.angularVelocity

					local interpQuat = sm.util.axesToQuat(selectedShape:getInterpolatedRight(), selectedShape:getInterpolatedUp())
					local qTranslate = sm.quat.angleAxis(angularVelocity:length() * dt, angularVelocity:safeNormalize(sm.vec3.zero()))

					rotation = qTranslate * interpQuat
					position = selectedShape:getInterpolatedWorldPosition() + selectedShape.velocity * dt
				elseif self.cl.effect.pointerOffset then
					local shapeA = selectedShape.shapeA

					position = shapeA:transformLocalPoint(
						shapeA:transformPoint(
							shapeA:getInterpolatedWorldPosition() + shapeA.velocity * dt
						) + self.cl.effect.pointerOffset
					)

					rotation = selectedShape:getWorldRotation()
				else
					position = selectedShape:getWorldPosition()
					rotation = selectedShape:getWorldRotation()
				end
			else
				position = selectedShape:getWorldPosition()
				rotation = selectedShape:getWorldRotation()
			end

			if not isShape then
				local jointType = selectedShape:getType()

				if jointType == "unknown" then
					local bb = selectedShape:getBoundingBox()
					local len = math.max(math.abs(bb.x),  math.abs(bb.y), math.abs(bb.z))
					local offset = len / 2 - 0.125

					position = position + rotation * sm.vec3.new(0, 0, 1) * offset
				elseif jointType == "piston" then
					local lifted = selectedShape.shapeA.body:isOnLift()
					local pistonLength = selectedShape:getLength()

					if self.cl.effect.pointerEffect:isPlaying() then
						self.cl.effect.pointerEffect:stop()
					end

					if lifted or not selectedShape.shapeB or pistonLength < 1.05 then
						self.cl.effect.pointerEffect:setParameter("uuid", selectedShape.uuid)
						self.cl.effect.pointerEffect:setScale(sm.vec3.one() / 4)
					else
						self.cl.effect.pointerEffect:setParameter("uuid", plasticUuid)
						self.cl.effect.pointerEffect:setScale(sm.vec3.new(0.25, 0.25, pistonLength / 4))

						local endPos = position + (rotation * sm.vec3.new(0, 0, 1) * (pistonLength / 4 - 0.25))
						position = position - (position - endPos) / 2
					end

					if not self.cl.effect.pointerEffect:isPlaying() then
						self.cl.effect.pointerEffect:start()
					end
				end
			end

			self.cl.effect.pointerEffect:setPosition(position)
			self.cl.effect.pointerEffect:setRotation(rotation)

			if self.cl.boxSelect and self.cl.effect.pointerEffect:isPlaying() then
				self.cl.effect.pointerEffect:stop()
			elseif not self.cl.boxSelect and not self.cl.effect.pointerEffect:isPlaying() then
				self.cl.effect.pointerEffect:start()
			end

			self.cl.effect.pointerPosition = position

			if not self.cl.multiSelected then
				self.cl.effect.originPosition = position
			end
		else
			self.cl.effect.pointerPosition = sm.vec3.zero()

			if self.cl.effect.pointerEffect:isPlaying() then
				self.cl.effect.pointerEffect:stop()
			end
		end

		local tick = sm.game.getCurrentTick()

		if self.cl.effect.isFancy or tick ~= self.cl.lastTick then
			self.cl.lastTick = tick

			for shapeId, shape in pairs(self.cl.selectedShapes) do
				local effect = self.cl.effect.selectedShapeEffects[shapeId]
				local host = self.cl.effect.hostedEffects[shapeId]

				if sm.exists(shape) then
					local hostDestroy = host and not sm.exists(host)

					if not sm.exists(effect) or hostDestroy then
						if hostDestroy then
							if sm.exists(effect) then
								effect:destroy()
							end

							self.cl.effect.selectedShapeEffects[shapeId] = nil
							self.cl.effect.hostedEffects[shapeId] = nil
						end

						local isPart = not (shape.isBlock or shape.isWedge)
						local uuid = not shape.isBlock and shape.uuid or plasticUuid
						local scale = isPart and sm.vec3.one() / 4 or shape:getBoundingBox()

						local _, inter = next(shape.body:getInteractables())
						
						effect = sm.effect.createEffect("ShapeRenderable", shape.interactable or inter)
						effect:setParameter("visualization", true)
						effect:setParameter("uuid", uuid)
						effect:setScale(scale + (not isPart and scaleModify or sm.vec3.zero()))
						effect:start()

						if not shape.interactable and inter then
							host = inter
							self.cl.effect.hostedEffects[shapeId] = inter

							effect:setOffsetPosition(inter.shape:transformPoint(shape.worldPosition))
							effect:setOffsetRotation(inter.shape:transformRotation(shape.worldRotation))
						end

						self.cl.effect.selectedShapeEffects[shapeId] = effect
					end

					local position, rotation

					if not (shape.interactable or host) then
						if self.cl.effect.isFancy then
							local angularVelocity = shape.body.angularVelocity

							local interpQuat = sm.util.axesToQuat(shape:getInterpolatedRight(), shape:getInterpolatedUp())
							local qTranslate = sm.quat.angleAxis(angularVelocity:length() * dt, angularVelocity:safeNormalize(sm.vec3.zero()))

							rotation = qTranslate * interpQuat
							position = shape:getInterpolatedWorldPosition() + shape.velocity * dt
						else
							position = shape.worldPosition
							rotation = shape.worldRotation
						end

						effect:setPosition(position)
						effect:setRotation(rotation)
					else
						if self.cl.effect.isFancy then
							position = shape:getInterpolatedWorldPosition() + shape.velocity * dt
						else
							position = shape.worldPosition
						end
					end

					self.cl.effect.shapePositions[shapeId] = position
				else
					if sm.exists(effect) then
						effect:destroy()
					end

					self.cl.effect.selectedShapeEffects[shapeId] = nil
					self.cl.selectedShapes[shapeId] = nil
					self.cl.effect.shapePositions[shapeId] = nil
					self.cl.effect.hostedEffects[shapeId] = nil
				end
			end

			for jointId, joint in pairs(self.cl.selectedJoints) do
				local effect = self.cl.effect.selectedJointEffects[jointId]

				if sm.exists(joint) then
					if not sm.exists(effect) then
						effect = sm.effect.createEffect("ShapeRenderable")
						effect:setParameter("visualization", true)
						effect:setParameter("uuid", joint.uuid)
						effect:setScale(sm.vec3.one() / 4)
						effect:start()

						self.cl.effect.jointOffsets[jointId] = joint.shapeA:transformPoint(joint:getWorldPosition())
						self.cl.effect.selectedJointEffects[jointId] = effect
					end

					local jointType = joint:getType()
					local position
					local rotation = joint:getWorldRotation()
					local jointOffset = self.cl.effect.jointOffsets[jointId]

					if self.cl.effect.isFancy and jointOffset then
						local shapeA = joint.shapeA

						position = shapeA:transformLocalPoint(
							shapeA:transformPoint(
								shapeA:getInterpolatedWorldPosition() + shapeA.velocity * dt
							) + jointOffset
						)
					else
						position = joint:getWorldPosition()
					end

					if jointType == "unknown" then
						local bb = joint:getBoundingBox()
						local len = math.max(math.abs(bb.x),  math.abs(bb.y), math.abs(bb.z))
						local offset = len / 2 - 0.125

						position = position + rotation * sm.vec3.new(0, 0, 1) * offset
					elseif jointType == "piston" then
						local lifted = joint.shapeA.body:isOnLift()
						local pistonLength = joint:getLength()

						effect:stop()

						if lifted or not joint.shapeB or pistonLength < 1.05 then
							effect:setParameter("uuid", joint.uuid)
							effect:setScale(sm.vec3.one() / 4)
						else
							effect:setParameter("uuid", plasticUuid)
							effect:setScale(sm.vec3.new(0.25, 0.25, pistonLength / 4))

							local endPos = position + (rotation * sm.vec3.new(0, 0, 1) * (pistonLength / 4 - 0.25))
							position = position - (position - endPos) / 2
						end

						effect:start()
					end

					self.cl.effect.jointPositions[jointId] = position

					effect:setPosition(position)
					effect:setRotation(rotation)
				else
					if sm.exists(effect) then
						effect:destroy()
					end

					self.cl.effect.jointOffsets[jointId] = nil
					self.cl.effect.selectedJointEffects[jointId] = nil
					self.cl.selectedJoints[jointId] = nil
					self.cl.effect.jointPositions[jointId] = nil
				end
			end

		end

		if self.cl.multiSelected and not self.cl.boxSelect and not self.cl.effectBlock then
			local position = self.cl.effect.pointerPosition
			local count = getLength(self.cl.selectedJoints) + getLength(self.cl.selectedShapes) + (position ~= sm.vec3.zero() and 1 or 0)

			for i, shape in pairs(self.cl.selectedShapes) do
				local shapePos = self.cl.effect.shapePositions[shape.id]

				if sm.exists(shape) and shapePos then
					position = position + shapePos
				else
					self.cl.selectedShapes[i] = nil
				end
			end

			for i, joint in pairs(self.cl.selectedJoints) do
				local jointPos = self.cl.effect.jointPositions[joint.id]

				if sm.exists(joint) and jointPos then
					position = position + jointPos
				else
					self.cl.selectedJoints[i] = nil
				end
			end
	
			if count ~= 0 then
				self.cl.effect.originPosition = position / count
			end
		elseif self.cl.boxSelect then
			local hit, result = self.cl.hit, self.cl.result

			local function r(value, increment)
				return math.floor(value / increment + 0.5) * increment
			end	

			local function isInBox(point, center, halfSize, orientation)
				local toPoint = point - center
				local localPoint = sm.quat.new(-orientation.x, -orientation.y, -orientation.z, orientation.w) * toPoint
				
				return math.abs(localPoint.x) <= halfSize.x
				   and math.abs(localPoint.y) <= halfSize.y
				   and math.abs(localPoint.z) <= halfSize.z
			end

			if hit and result and (result:getBody() or result:getJoint()) then
				local isShape = result.type == "body"
				local body = isShape and result:getBody() or result:getJoint().shapeA.body
				local pointLocal = result.pointLocal
				local roundedLocal = sm.vec3.new(r(pointLocal.x, 0.25), r(pointLocal.y, 0.25), r(pointLocal.z, 0.25))
				local worldPoint = body:transformPoint(roundedLocal)

				self.cl.effect.originPosition = worldPoint
				self.cl.roundedLocal = roundedLocal
			else
				self.cl.effect.originPosition = nil
			end


			if self.cl.startPos and self.cl.startPos ~= self.cl.endPos then
				if self.cl.effect.boxEffect:isPlaying() then
					self.cl.effect.boxEffect:stop()
				end

				local startWorld = self.cl.startBody:transformPoint(self.cl.startPos)
				local diff = startWorld - self.cl.endBody:transformPoint(self.cl.endPos)
				local localDiff = self.cl.startPos - self.cl.endPos
				local scale, pos, rot = sm.vec3.new(math.abs(localDiff.x), math.abs(localDiff.y), math.abs(localDiff.z)), startWorld - diff / 2, self.cl.startBody.worldRotation

				self.cl.bbCentre = pos
				self.cl.bbScale = scale
				self.cl.displayScale = scale * 4

				if self.cl.lastScale ~= scale then
					self.cl.lastScale = scale
					self.cl.reCalc = true
				end

				self.cl.effect.boxEffect:setScale(scale)
				self.cl.effect.boxEffect:setPosition(pos)
				self.cl.effect.boxEffect:setRotation(rot)

				self.cl.effect.boxEffect:start()
			else
				if self.cl.effect.boxEffect:isPlaying() then
					self.cl.effect.boxEffect:stop()
				end
			end

			if self.cl.reCalc then
				local datumBody = self.cl.startBody
				local shapes = self.cl.startBody:getCreationShapes()

				for _, shape in pairs(shapes) do
					if self.cl.selectionFilter ~= 2 then
						if not self.cl.selectedShapes[shape.id] and isInBox(shape.worldPosition, self.cl.bbCentre, self.cl.bbScale / 2, datumBody.worldRotation) then
							self.cl.selectedShapes[shape.id] = shape
						end
					end

					if self.cl.selectionFilter ~= 3 then
						local joints = shape:getJoints()

						for _, joint in pairs(joints) do
							if not self.cl.selectedJoints[joint.id] and isInBox(joint.worldPosition, self.cl.bbCentre, self.cl.bbScale / 2, datumBody.worldRotation) then
								self.cl.selectedJoints[joint.id] = joint
							end
						end
					end
				end

				self.cl.reCalc = false
			end
		end

		if self.cl.effect.originPosition then
			if not self.cl.effect.xEffect:isActive() then
				self.cl.effect.xEffect:open()
				self.cl.effect.yEffect:open()
				self.cl.effect.zEffect:open()
			end

			local firstShape = returnFirst(self.cl.selectedShapes)
			local firstJoint = returnFirst(self.cl.selectedJoints)
			local shape

			if sm.exists(selectedShape) then
				shape = selectedShape
			elseif sm.exists(firstShape) then
				shape = firstShape
			elseif sm.exists(firstJoint) then
				shape = firstJoint
			end

			if shape then
				local isShape = type(shape) == "Shape"

				local bodyRotation = isShape and shape.body.worldRotation or shape.shapeA.body.worldRotation
				local shapeRotation = isShape and shape.worldRotation or shape.shapeA.worldRotation
				local rotation = self.cl.rotationAxis and shapeRotation or bodyRotation

				local xPos, yPos, zPos = self.cl.effect.originPosition + rotation * sm.vec3.new(0.5, 0, 0),
										 self.cl.effect.originPosition + rotation * sm.vec3.new(0, 0.5, 0),
										 self.cl.effect.originPosition + rotation * sm.vec3.new(0, 0, 0.5)

				if self.cl.lastAxis ~= self.cl.rotationAxis then
					self.cl.lastAxis = self.cl.rotationAxis

					if self.cl.rotationAxis then
						self.cl.effect.xEffect:setColor("Icon", sm.color.new("00ffff"))
						self.cl.effect.yEffect:setColor("Icon", sm.color.new("ff00ff"))
						self.cl.effect.zEffect:setColor("Icon", sm.color.new("ffff00"))

						self.cl.effect.xLine:setParameter("color", sm.color.new("00ffff"))
						self.cl.effect.yLine:setParameter("color", sm.color.new("ff00ff"))
						self.cl.effect.zLine:setParameter("color", sm.color.new("ffff00"))
					else
						self.cl.effect.xEffect:setColor("Icon", sm.color.new("ff0000"))
						self.cl.effect.yEffect:setColor("Icon", sm.color.new("00ff00"))
						self.cl.effect.zEffect:setColor("Icon", sm.color.new("0000ff"))

						self.cl.effect.xLine:setParameter("color", sm.color.new("ff0000"))
						self.cl.effect.yLine:setParameter("color", sm.color.new("00ff00"))
						self.cl.effect.zLine:setParameter("color", sm.color.new("0000ff"))
					end
				end

				self.cl.effect.xEffect:setWorldPosition(xPos)
				self.cl.effect.yEffect:setWorldPosition(yPos)
				self.cl.effect.zEffect:setWorldPosition(zPos)

				self.cl.effect.xLine:setPosition((xPos - self.cl.effect.originPosition) * 0.45 + self.cl.effect.originPosition)
				self.cl.effect.yLine:setPosition((yPos - self.cl.effect.originPosition) * 0.45 + self.cl.effect.originPosition)
				self.cl.effect.zLine:setPosition((zPos - self.cl.effect.originPosition) * 0.45 + self.cl.effect.originPosition)

				self.cl.effect.xLine:setRotation(rotation * sm.quat.angleAxis(math.rad(90), sm.vec3.new(0, 0, 1)))
				self.cl.effect.yLine:setRotation(rotation)
				self.cl.effect.zLine:setRotation(rotation * sm.quat.angleAxis(math.rad(90), sm.vec3.new(1, 0, 0)))

				if not self.cl.effect.xLine:isPlaying() then
					self.cl.effect.xLine:start()
					self.cl.effect.yLine:start()
					self.cl.effect.zLine:start()
				end
			else
				self.cl.effect.xEffect:close()
				self.cl.effect.yEffect:close()
				self.cl.effect.zEffect:close()

				self.cl.effect.xLine:stop()
				self.cl.effect.yLine:stop()
				self.cl.effect.zLine:stop()

				self.cl.effect.pointerEffect:stop()
			end
		else
			self.cl.effect.xEffect:close()
			self.cl.effect.yEffect:close()
			self.cl.effect.zEffect:close()

			self.cl.effect.xLine:stop()
			self.cl.effect.yLine:stop()
			self.cl.effect.zLine:stop()
		end

	end

	if self.cl.forcePress then
		sm.gui.setProgressFraction((os.clock() - self.cl.forcePress) / forceHold)
	end
end

--/ Клиент: Каждые 1/40 сек
function editor:client_onFixedUpdate()
	local player = localPlayer.getPlayer()
	local character = player.character
	local lift = localPlayer.getOwnedLift()

	if character then
		if lift then
			local level = lift.level

			if level ~= self.cl.liftLevel then
				self.cl.liftLevel = level
				self.network:sendToServer("sv_setLiftLevel", level)
			end
		end

		if self.cl.closeLockout and self.cl.closeLockout + 10 < sm.game.getCurrentTick() then
			self.cl.closeLockout = nil
		end

		if self.cl.creationVisualization and sm.exists(self.cl.selectedBody) then
			local pointerShape = self.cl.effect.selectedShape
			local _, firstShape = next(self.cl.selectedShapes)
			local _, firstJoint = next(self.cl.selectedJoints)

			local datumBody

			if pointerShape then
				if type(pointerShape) == "Shape" then
					datumBody = pointerShape.body
				else
					datumBody = pointerShape.shapeA.body
				end
			elseif firstShape then
				datumBody = firstShape.body
			elseif firstJoint then
				datumBody = firstShape.shapeA.body
			end

			self.cl.creationVisualization:setPosition(datumBody.worldPosition)
			self.cl.creationVisualization:setRotation(datumBody.worldRotation)
		end
	end
end

--/ Q (следующее вращение)
function editor:client_onToggle()
	self:cl_ChatMessage("Q нажата")
end

function editor:cl_closeSettings()
	self.cl.settingsGui:close()
end

--/ Когда игрок берёт tool в руки.
function editor:client_onEquip()
	if self.tool:isLocal() then
		sm.audio.play("ConnectTool - Equip")
	end

	self.wantEquipped = true
	self.jointWeight = 0.0

	currentRenderablesTp = {}
	currentRenderablesFp = {}

	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderables ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	self.tool:setTpRenderables( currentRenderablesTp )

	self:cl_loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )

	if self.tool:isLocal() then
		self.tool:setFpRenderables( currentRenderablesFp )
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

--/ Когда игрок убирает инструмент
function editor:client_onUnequip()
	if self.tool:isLocal() then
		sm.audio.play("ConnectTool - Unequip")
	end

	self.wantEquipped = false
	self.equipped = false

	if sm.exists( self.tool ) then
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.tool:isLocal() then
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end

	if self.cl.effect.pointerEffect:isPlaying() then
		self.cl.effect.pointerEffect:stop()
	end

	destroyEffectTable(self.cl.effect.selectedJointEffects)
	destroyEffectTable(self.cl.effect.selectedShapeEffects)

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}
	self.cl.effect.hostedEffects = {}

	self.cl.selectedJoints = {}
	self.cl.selectedShapes = {}

	self.cl.effect.shapePositions = {}
	self.cl.effect.jointPositions = {}

	self.cl.effect.xEffect:close()
	self.cl.effect.yEffect:close()
	self.cl.effect.zEffect:close()

	self.cl.effect.xLine:stop()
	self.cl.effect.yLine:stop()
	self.cl.effect.zLine:stop()

	self.cl.effect.boxEffect:stop()

	self.cl.startPos = nil
end

--/ R (перезарядка)
function editor:client_onReload()
--	self:cl_ChatMessage("R нажата")
	self.cl.settingsGui:open()

	return true
end

function editor:cl_onSettingChange(button)
	local settingsTbl = sm.json.open(settingsDir)

	if button == "effectQuality" then
		self.cl.effect.isFancy = not self.cl.effect.isFancy

		if self.cl.effect.isFancy then
			self.cl.settingsGui:setText("effectQuality", "Fancy")
		else
			self.cl.settingsGui:setText("effectQuality", "Fast")
		end

		settingsTbl.fancyEffects = self.cl.effect.isFancy
	elseif button == "selectionType" then
		self.cl.boxSelect = not self.cl.boxSelect

		if self.cl.boxSelect  then
			self.cl.settingsGui:setText("selectionType", "Box")
		else
			self.cl.settingsGui:setText("selectionType", "Shape")

			self.cl.startPos = nil

			if sm.exists(self.cl.effect.boxEffect) then
				self.cl.effect.boxEffect:stop()
			end
		end

		settingsTbl.boxSelect = self.cl.boxSelect
	elseif button == "clickExit" then
		self.cl.clickExit = not self.cl.clickExit

		if self.cl.clickExit  then
			self.cl.settingsGui:setText("clickExit", "#00aa00Enabled")
		else
			self.cl.settingsGui:setText("clickExit", "#aa0000Disabled")
		end

		settingsTbl.clickExit = self.cl.clickExit
	elseif button == "childDetection" then
		self.cl.childDetection = not self.cl.childDetection

		if self.cl.childDetection  then
			self.cl.settingsGui:setText("childDetection", "#00aa00Enabled")
		else
			self.cl.settingsGui:setText("childDetection", "#aa0000Disabled")
		end

		self.network:sendToServer("sv_updateSettings", {"childDetection", self.cl.childDetection})

		settingsTbl.childDetection = self.cl.childDetection
	elseif button == "autoApply" then
		self.cl.autoApply = not self.cl.autoApply

		if self.cl.autoApply  then
			self.cl.settingsGui:setText("autoApply", "#00aa00Enabled")
		else
			self.cl.settingsGui:setText("autoApply", "#aa0000Disabled")
		end

		self.network:sendToServer("sv_updateSettings", {"autoApply", self.cl.autoApply})

		settingsTbl.autoApply = self.cl.autoApply
	end

	sm.json.save(settingsTbl, settingsDir)
end

function editor:cl_onDropDown(selection)
	if selection == "Shapes And Joints" then
		self.cl.selectionFilter = 1
	elseif selection == "Joints" then
		self.cl.selectionFilter = 2
	else
		self.cl.selectionFilter = 3
	end
end

--/ Каждый кадр, пока инструмент экипирован
function editor:client_onEquippedUpdate(primary, secondary, forceBuild)
	local filter

	if self.cl.selectionFilter == 1 then
		filter = sm.physics.filter.joints + sm.physics.filter.dynamicBody + sm.physics.filter.staticBody
	elseif self.cl.selectionFilter == 2 then
		filter = sm.physics.filter.joints
	elseif self.cl.selectionFilter == 3 then
		filter = sm.physics.filter.dynamicBody + sm.physics.filter.staticBody
	end

	local pos = camera.getPosition()

	local hit, result = sm.physics.raycast(pos, pos + camera.getDirection() * 7.5, localPlayer.getPlayer().character, filter)
	local localHit, localResult = localPlayer.getRaycast(7.5)

	if localHit and localResult.type == "joint" and self.cl.selectionFilter ~= 3 then
		hit, result = localHit, localResult
	end

	local valid

	self.cl.hit, self.cl.result = hit, result

	if hit then
		valid = true

		local type_ = result.type

		local isShape = type_ == "body"
		local selectedShape = isShape and result:getShape() or result:getJoint()
		local selectedBody = isShape and selectedShape.body or selectedShape.shapeA.body

		self.cl.selectedBody = selectedBody

		local multiSelected = getLength(self.cl.selectedShapes) + getLength(self.cl.selectedJoints) > 0

		self.cl.multiSelected = multiSelected

		if not self.cl.gui:isActive() then
			self.cl.effect.selectedShape = selectedShape
		end

		local bodyDeselect = false
		local broke

		if self.cl.selectionFilter ~= 2 then
			for _, shape in pairs(selectedBody:getShapes()) do
				if not self.cl.selectedShapes[shape.id] then
					broke = true
					break
				end
			end
		end

		if not broke and self.cl.selectionFilter ~= 3 then
			for _, joint in pairs(selectedBody:getJoints()) do
				if not self.cl.selectedJoints[joint.id] then
					broke = true
					break
				end
			end

			if not broke then
				bodyDeselect = true
			end
		end

		sm.gui.setInteractionText(createStr, self.cl.boxSelect and boxAttackStr or attackStr)

		if self.cl.boxSelect then
			if self.cl.displayScale then
				sm.gui.setInteractionText(string.format(boxScaleStr, self.cl.displayScale.x, self.cl.displayScale.y, self.cl.displayScale.z))
			else
				sm.gui.setInteractionText("")
			end
		else
			sm.gui.setInteractionText(bodyDeselect and forceStrDeselect or forceStrSelect, forceCreation, reloadStr)
		end

		if primary == 1 then
			local status, err = pcall(function()
				if multiSelected then
					self.network:sendToServer("sv_exportSelected", {shapes = self.cl.selectedShapes, joints = self.cl.selectedJoints, body = selectedBody})
				else
					self.network:sendToServer("sv_exportSelected", {shapes = isShape and {selectedShape} or {}, joints = not isShape and {selectedShape} or {}, body = selectedBody})
				end
			end)

			if not status then
				self:cl_errorChatMessage("#ff0000Selection ammount too large!")
			else
				self.cl.export.wasOpen = false
				
				self.cl.startPos = nil
				self.cl.displayScale = nil
			end
		end

		if secondary == 1 or secondary == 2 then
			if not self.cl.boxSelect then
				if isShape then
					local shape = self.cl.selectedShapes[selectedShape.id]

					if not shape then
						if secondary == 1 then
							self.cl.deselecting = false
						end

						if not self.cl.deselecting then
							self.cl.selectedShapes[selectedShape.id] = selectedShape
						end
					else
						if secondary == 1 then
							self.cl.deselecting = true
						end

						if self.cl.deselecting then
							self.cl.selectedShapes[selectedShape.id] = nil

							self.cl.effect.selectedShapeEffects[selectedShape.id]:destroy()
							self.cl.effect.selectedShapeEffects[selectedShape.id] = nil

							self.cl.effect.shapePositions[selectedShape.id] = nil
							self.cl.effect.hostedEffects[selectedShape.id] = nil
						end
					end
				else
					local joint = self.cl.selectedJoints[selectedShape.id]

					if not joint then
						if secondary == 1 then
							self.cl.deselecting = false
						end

						if not self.cl.deselecting then
							self.cl.selectedJoints[selectedShape.id] = selectedShape
						end				
					else
						if secondary == 1 then
							self.cl.deselecting = true
						end

						if self.cl.deselecting then
							self.cl.selectedJoints[selectedShape.id] = nil

							self.cl.effect.selectedJointEffects[selectedShape.id]:destroy()
							self.cl.effect.selectedJointEffects[selectedShape.id] = nil
						end
					end
				end
			elseif self.cl.roundedLocal then
				local roundedLocal = self.cl.roundedLocal

				if secondary == 1 then
					self.cl.startPos = roundedLocal
					self.cl.startBody = selectedBody
				end

				self.cl.endPos = roundedLocal
				self.cl.endBody = selectedBody
			end
		end

		if secondary == 3 then
			self.cl.deselecting = false
		end

		if forceBuild and not self.cl.forceToggle then
			self.cl.forceToggle = true
			self.cl.forcePress = os.clock()

			if self.cl.selectionFilter ~= 2 then
				for _, shape in pairs(selectedBody:getShapes()) do
					if not bodyDeselect then
						local shapeA = self.cl.selectedShapes[shape.id]

						if not shapeA then
							self.cl.selectedShapes[shape.id] = shape
						end
					else
						self.cl.selectedShapes[shape.id] = nil

						self.cl.effect.selectedShapeEffects[shape.id]:destroy()
						self.cl.effect.selectedShapeEffects[shape.id] = nil

						self.cl.effect.shapePositions[shape.id] = nil
						self.cl.effect.hostedEffects[shape.id] = nil
					end
				end
			end

			if self.cl.selectionFilter ~= 3 then
				for _, joint in pairs(selectedBody:getJoints()) do
					if not bodyDeselect then
						local jointA = self.cl.selectedJoints[joint.id]

						if not jointA then
							self.cl.selectedJoints[joint.id] = joint
						end
					else
						self.cl.selectedJoints[joint.id] = nil

						self.cl.effect.selectedJointEffects[joint.id]:destroy()
						self.cl.effect.selectedJointEffects[joint.id] = nil
					end
				end
			end
		elseif not forceBuild and self.cl.forceToggle then
			self.cl.forceToggle = false
			self.cl.forcePress = nil
		end

		if self.cl.forcePress and self.cl.forcePress + forceHold <= os.clock() then
			if self.cl.selectionFilter ~= 2 then
				for _, shape in pairs(selectedBody:getCreationShapes()) do
					local shapeA = self.cl.selectedShapes[shape.id]

					if not shapeA then
						self.cl.selectedShapes[shape.id] = shape
					end
				end
			end

			if self.cl.selectionFilter ~= 3 then
				for _, joint in pairs(selectedBody:getCreationJoints()) do
					local jointA = self.cl.selectedJoints[joint.id]

					if not jointA then
						self.cl.selectedJoints[joint.id] = joint
					end
				end
			end
		end
	else	
		if primary == 1 then
			self.cl.selectedShapes = {}
			self.cl.selectedJoints = {}

			self.cl.effect.shapePositions = {}
			self.cl.effect.jointPositions = {}

			destroyEffectTable(self.cl.effect.selectedShapeEffects)
			destroyEffectTable(self.cl.effect.selectedJointEffects)

			self.cl.effect.selectedShapeEffects = {}
			self.cl.effect.selectedShapeEffects = {}

			self.cl.effect.hostedEffects = {}

			if self.cl.boxSelect then
				self.cl.startPos = nil
				self.cl.effect.boxEffect:stop()
			end

			self.cl.displayScale = nil
		end

		sm.gui.setInteractionText(reloadStr)
	end

	if not valid and not self.cl.gui:isActive() then
		self.cl.effect.selectedShape = nil
	end

	return true, true
end

--/ Удаления инструмента
function editor:client_onDestroy()
	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.effect.pointerEffect:stop()

	self.cl.effect.xEffect:close()
	self.cl.effect.yEffect:close()
	self.cl.effect.zEffect:close()

	self.cl.effect.xLine:stop()
	self.cl.effect.yLine:stop()
	self.cl.effect.zLine:stop()

	self.cl.effect.boxEffect:stop()
end

function editor:cl_rebuildJson(data)
    if data.i == 1 then
        self.cl.export.json = data.string
    else
        self.cl.export.json = self.cl.export.json..data.string
    end

	if not data.finished then return end

    if not data.onlySet then
        self:cl_openEditMenu()
	else
		self.cl.export.editedJson = self.cl.export.json
		self.cl.queue.valid = true
		self.cl.export.jsonSet = true
	end
end

function editor:cl_openEditMenu()
	if (self.cl.export.wasOpen and self.cl.gui:isActive()) or not self.cl.export.wasOpen then
		self.cl.gui:open()

		local tick = sm.game.getCurrentTick()
		self.cl.closeLockout = tick
		self.cl.export.jsonSet = true
		self.cl.export.editedJson = self.cl.export.json
	end
end

function editor:cl_moveUpdate(_, text)
    local numb = tonumber(text)

	if numb then
		self.cl.moveAmmount = numb
	end
end

function editor:cl_onButtonPress(button)
	self.network:sendToServer("sv_updatePointer")

	if self.cl.queue.valid and self.cl.export.jsonSet then

		self.cl.queue.valid = false
		self.cl.export.jsonSet = false

		if button ~= "Done" then
			local vec = positionButtonMap[button]
			local rot = rotationButtonMap[button]

			if vec then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "move", data = vec * self.cl.moveAmmount})
			elseif rot then
				self.network:sendToServer("sv_setSpecialInstruction", {name = "rotate", data = rot})
			else
				self.network:sendToServer("sv_setSpecialInstruction", {name = button})
			end
		end

		local json = uglifyJson(self.cl.export.editedJson)
		local strings = splitString(json, packetSize)

		self:cl_ChatMessage("json")--
		
		for i, string in pairs(strings) do
			local finished = i == #strings
			self.network:sendToServer("sv_rebuildJson", {string = string, finished = finished, i = i, partialExport = button == "showPlacement", forceExport = button == "Done"})
		end
	end
end

function editor:cl_onRSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("rText", "#ff0000R#eeeeee: "..value)
	self.cl.color.rgb.r = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("rSlider", value)
	end
end

function editor:cl_onGSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("gText", "#00ff00G#eeeeee: "..value)
	self.cl.color.rgb.g = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("gSlider", value)
	end
end

function editor:cl_onBSliderUpdate(value, dontUpdate)
	self.cl.gui:setText("bText", "#0000ffB#eeeeee: "..value)
	self.cl.color.rgb.b = value / 255

	if not dontUpdate then
		self:cl_updateHex(self.cl.color.rgb)
	else
		self.cl.gui:setSliderPosition("bSlider", value)
	end
end

function editor:cl_updateHex(rgb)
	local hex = tostring(rgb):sub(1, 6):upper()

	self.cl.gui:setText("hexText", hex)
	self.cl.color.hex = hex:upper()

	self.cl.gui:setColor("Preview", sm.color.new(hex))
end

function editor:cl_onHexUpdate(_, text)
	if text:match("%x%x%x%x%x%x$") ~= nil then
		self.cl.color.isValid = true
		self.cl.gui:setText("hexText", "#eeeeee"..text)

		self.cl.color.hex = text:upper()

		local r = tonumber(text:sub(1, 2), 16)
		local g = tonumber(text:sub(3, 4), 16)
		local b = tonumber(text:sub(5, 6), 16)

		self:cl_onRSliderUpdate(r, true)
		self:cl_onGSliderUpdate(g, true)
		self:cl_onBSliderUpdate(b, true)

		self.cl.gui:setColor("Preview", sm.color.new(text))
	else
		self.cl.color.isValid = false
		self.cl.gui:setText("hexText", "#ff0000"..text)
	end
end

function editor:cl_applyAll()
	local failed, newJson = replaceHexColor(self.cl.export.editedJson, self.cl.color.hex)

	if not failed then
		self.cl.export.editedJson = newJson
	else
		self:cl_errorChatMessage("#ff0000"..newJson:sub(64, #newJson))
	end
end

function editor:cl_onExpand(button)
	if button == "expandColors" then
		self.cl.color.extraVisible = not self.cl.color.extraVisible
		self.cl.gui:setVisible("extraColorWindow", self.cl.color.extraVisible)
	end
end

function editor:cl_setPaintColor(button)
	local index

	if button:sub(1, 1) == "0" then
		index = tonumber(button:sub(2, 2))
	else
		index = tonumber(button:sub(1, 2))
	end

	self:cl_onHexUpdate(_, PAINT_COLORS[index]:sub(1, 6):upper())
end

function editor:cl_setCreationVisualization(data)
	if not self.cl.creationVisualizationString then
		self.cl.creationVisualizationString = ""
	end

	self.cl.creationVisualizationString = self.cl.creationVisualizationString..data.string

	if not data.finished then return end

	if self.cl.creationVisualization then
		self.cl.creationVisualization:destroy()
	end

	self.cl.creationVisualization = sm.visualization.createBlueprint(sm.json.parseJsonString(self.cl.creationVisualizationString))
	
	self.cl.creationVisualizationString = nil
end

function editor:cl_axisChange(button, userSet)
	self.cl.rotationAxis = not self.cl.rotationAxis
end

function editor:cl_setPointerShape(shape)
	self.cl.effect.selectedShape = shape
end

function editor:cl_postImportClear()
	self.cl.export.wasOpen = true
	self.cl.effect.selectedShape = nil
	self.cl.effect.originPosition = nil
	self.cl.effectBlock = true

	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}

	if self.cl.creationVisualization then
		self.cl.creationVisualization:destroy()
		self.cl.creationVisualization = nil
	end

	self.cl.gui:setText("debugBox", "Loading...")
end

function editor:cl_setNewObjects(data)
	self.cl.selectedShapes = data[1]
	self.cl.selectedJoints = data[2]
	self.cl.effectBlock = false

	self.cl.gui:setText("debugBox", "")
end

function editor:cl_onClose()
	self.cl.selectedJoints = {}
	self.cl.selectedShapes = {}

	self.cl.effect.shapePositions = {}
	self.cl.effect.jointPositions = {}

	destroyEffectTable(self.cl.effect.selectedShapeEffects)
	destroyEffectTable(self.cl.effect.selectedJointEffects)

	self.cl.effect.selectedShapeEffects = {}
	self.cl.effect.selectedJointEffects = {}

	self.cl.effect.selectedShape = nil
	self.cl.rotationAxis = false

	if self.cl.creationVisualization then
		self.cl.creationVisualization:destroy()
	end

	self.cl.creationVisualization = nil
end

function editor:cl_setQueueValid(bool)
	self.cl.queue.valid = bool
end

function editor:cl_setJsonSet(bool)
	self.cl.export.jsonSet = bool
end

function editor:cl_closeGui(button)
	if not self.cl.closeLockout and not (button == "exitButton" and not self.cl.clickExit) then
		self.cl.gui:close()
		return true
	end
end

function editor:cl_alertText(msg)
	sm.gui.displayAlertText(msg)
end

function editor:cl_errorChatMessage(msg)
	sm.gui.chatMessage("Error : #ff0000"..msg)
end

function editor:cl_ChatMessage(msg)
	sm.gui.chatMessage("Message: #00ffff"..msg)
end

-- HOOKS --

sm.SurvivalBlockAndPartEditor = {}
sm.SurvivalBlockAndPartEditor.mechanicHook = false

local oldPlaceLift = sm.player.placeLift

function placeLiftHook(player, selectedBodies, liftPosition, liftLevel, rotationIndex)
	if not sm.SurvivalBlockAndPartEditor.liftData then sm.SurvivalBlockAndPartEditor.liftData = {} end

	sm.SurvivalBlockAndPartEditor.liftData[player.id] = {
		player = player,
		selectedBodies = selectedBodies,
		selectedShapes = sm.exists(selectedBodies[1]) and selectedBodies[1]:getCreationShapes() or {},
		liftPosition = liftPosition,
		liftLevel = liftLevel,
		rotationIndex = rotationIndex
	}

	oldPlaceLift(player, selectedBodies, liftPosition, liftLevel, rotationIndex)
end

sm.player.placeLift = placeLiftHook

local oldBindCommand = sm.game.bindChatCommand

local function bindCommandHook(command, params, callback, help)
	if not sm.SurvivalBlockAndPartEditor.hooked then
		sm.SurvivalBlockAndPartEditor.hooked = true

		dofile("$CONTENT_7e425f00-20a3-42ea-850d-f91afa4d656f/Scripts/dofiler.lua")
		print("| BBPE - MechanicCharacter Hooked |")
	end

	oldBindCommand(command, params, callback, help)
end

sm.game.bindChatCommand = bindCommandHook