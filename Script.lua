local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local player = Players.LocalPlayer

local function cleanupPrevious()
    if _G.MM2Connections then
        for _, conn in ipairs(_G.MM2Connections) do
            if typeof(conn) == "RBXScriptConnection" and conn.Connected then
                pcall(function() conn:Disconnect() end)
            end
        end
    end
    _G.MM2Connections = {}

    if _G.TimerThread then
        task.cancel(_G.TimerThread)
        _G.TimerThread = nil
    end
end
cleanupPrevious()

_G.hasUnlockedTimerThisRound = false
_G.isRoundEnded = false
_G.isInnocentMode = false
_G.roundEndTime = nil

local isUpdating = false
local WHITE_COLOR = Color3.fromRGB(255, 255, 255)
local ORANGE_COLOR = Color3.fromRGB(255, 165, 0)
local RED_COLOR = Color3.fromRGB(255, 0, 0)

local scoreLabel = nil
local headerLabel = nil
local trackedLabels = {}

local function hideTimerUI()
    isUpdating = true
    if scoreLabel and scoreLabel.Parent then scoreLabel.Visible = false end
    if headerLabel and headerLabel.Parent then headerLabel.Visible = false end
    isUpdating = false
end

local function isWeaponTool(tool)
    if not (tool and tool:IsA("Tool")) then return false end
    local name = tool.Name:lower()
    if not name:find("toy") and not name:find("radio") and not name:find("emote") then
        if name:find("gun") or name:find("revolver") or name:find("hero") or name:find("knife") then
            return true
        end
    end
    return false
end

local function isTimerPattern(txt)
    if not txt then return false end
    local lower = txt:lower()
    if lower:match("%d+%s*m") or lower:match("%d+%s*s") then
        return true
    end
    local num = tonumber(lower:match("^%s*(%d+)%s*$"))
    if num and num >= 0 and num <= 900 then
        return true
    end
    return false
end

local function survivalXpToSeconds(txt)
    local rawNum = tonumber(txt:match("%d+"))
    if rawNum then
        local elapsedSecs = rawNum / 5
        local remaining = math.clamp(720 - elapsedSecs, 0, 720)
        return math.floor(remaining)
    end
    return nil
end

local function parseTextToSeconds(txt)
    if not txt then return nil end
    txt = txt:lower()

    local mins = tonumber(txt:match("(%d+)%s*m")) or 0
    local secs = tonumber(txt:match("(%d+)%s*s")) or 0
    if mins > 0 or secs > 0 or txt:find("m") or txt:find("s") then
        return (mins * 60) + secs
    end

    local rawNum = tonumber(txt:match("%d+"))
    if rawNum then
        local converted = survivalXpToSeconds(txt)
        if converted then return converted end
    end

    return nil
end

local function secondsToFormattedText(sec)
    if sec <= 0 then return "0s" end
    local m = math.floor(sec / 60)
    local s = sec % 60
    if m > 0 then
        return string.format("%dm %ds", m, s)
    else
        return string.format("%ds", s)
    end
end

local function isMainHUDLabel(obj)
    if not obj:IsA("TextLabel") then return false end

    local p = obj.Parent
    local playerGui = player:FindFirstChild("PlayerGui")
    while p and p ~= playerGui and p ~= game do
        local pName = p.Name:lower()
        if pName:find("inventory") or pName:find("profile") or pName:find("trade") or
           pName:find("shop") or pName:find("menu") or pName:find("container") or
           pName:find("crafting") or pName:find("leaderboard") then
            return false
        end
        p = p.Parent
    end

    local name = obj.Name:lower()
    if name:find("level") or name:find("amount") or name:find("title") or
       name:find("slot") or name:find("key") or name:find("role") or name:find("coin") then
        return false
    end

    local absPos = obj.AbsolutePosition
    local camera = workspace.CurrentCamera
    if not camera then return false end
    local vp = camera.ViewportSize

    if absPos.Y > (vp.Y * 0.35) or absPos.X > (vp.X * 0.75) or absPos.X < (vp.X * 0.25) then
        return false
    end
    return true
end

local function isMM2RoundActive()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return false end

    for _, guiName in ipairs({"MainGUI", "GameGUI", "HUD", "ScreenGui"}) do
        local gui = pGui:FindFirstChild(guiName)
        if gui and gui:IsA("ScreenGui") and not gui.Enabled then
            return false
        end
    end
    return true
end

local function updateRealtimeDisplay()
    if _G.isRoundEnded or not isMM2RoundActive() then
        _G.isRoundEnded = true
        hideTimerUI()
        return
    end

    if not _G.isInnocentMode or not _G.hasUnlockedTimerThisRound or not _G.roundEndTime then
        return
    end

    if scoreLabel and scoreLabel.Parent then
        local curTxt = scoreLabel.Text:lower()
        if scoreLabel.TextColor3 == Color3.fromRGB(0, 255, 0) or curTxt:find("victory") or curTxt:find("defeat") or curTxt:find("won") or curTxt == "0s" or curTxt == "0 s" then
            _G.isRoundEnded = true
            hideTimerUI()
            return
        end
    end

    if headerLabel and headerLabel.Parent then
        local headTxt = headerLabel.Text:lower()
        if headerLabel.TextColor3 == Color3.fromRGB(0, 255, 0) or headTxt:find("victory") or headTxt:find("defeat") or headTxt:find("won") then
            _G.isRoundEnded = true
            hideTimerUI()
            return
        end
    end

    local remaining = math.max(0, math.ceil(_G.roundEndTime - os.clock()))

    if remaining <= 0 then
        _G.isRoundEnded = true
        hideTimerUI()
        return
    end

    if scoreLabel and scoreLabel.Parent then
        isUpdating = true
        scoreLabel.Visible = true
        scoreLabel.Text = secondsToFormattedText(remaining)
        scoreLabel.TextColor3 = (remaining <= 30) and RED_COLOR or WHITE_COLOR
        scoreLabel.TextStrokeTransparency = 0
        scoreLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        isUpdating = false
    end

    if headerLabel and headerLabel.Parent then
        isUpdating = true
        headerLabel.Visible = false
        isUpdating = false
    end
end

local function cacheHUDLabels()
    local pGui = player:FindFirstChild("PlayerGui")
    if not pGui then return end

    for _, v in ipairs(pGui:GetDescendants()) do
        if isMainHUDLabel(v) then
            local txt = v.Text:lower()
            if txt:find("survival") or txt:find("xp") or v.Name:lower():find("header") then
                headerLabel = v
                _G.isInnocentMode = true
            elseif isTimerPattern(v.Text) then
                scoreLabel = v
            end
        end
    end
end

_G.TimerThread = task.spawn(function()
    while true do
        task.wait(0.15)
        if _G.isInnocentMode and not _G.isRoundEnded then
            if _G.hasUnlockedTimerThisRound then
                updateRealtimeDisplay()
            end
        else
            hideTimerUI()
        end
    end
end)

local function unlockRealtimeTimer(currentText)
    if _G.hasUnlockedTimerThisRound or _G.isRoundEnded then return end

    local currentSecs = parseTextToSeconds(currentText) or 720
    _G.roundEndTime = os.clock() + currentSecs
    _G.hasUnlockedTimerThisRound = true
    updateRealtimeDisplay()
end

local function applyMM2Formatting(obj)
    if not isMainHUDLabel(obj) or trackedLabels[obj] then return end
    trackedLabels[obj] = true

    local function atualizar()
        if isUpdating then return end
        local rawTxt = obj.Text
        local lowerTxt = rawTxt:lower()

        if _G.isRoundEnded or not isMM2RoundActive() or
           obj.TextColor3 == Color3.fromRGB(0, 255, 0) or
           lowerTxt:find("victory") or lowerTxt:find("defeat") or
           lowerTxt:find("won") or lowerTxt:find("hero") or
           lowerTxt:find("murderer") or lowerTxt:find("sheriff") or
           rawTxt == "0s" or rawTxt == "0 s" then
            _G.isRoundEnded = true
            obj.Visible = false
            hideTimerUI()
            return
        end

        if string.find(lowerTxt, "survival") or string.find(lowerTxt, "xp") or obj.Name:lower():find("header") then
            headerLabel = obj
            _G.isInnocentMode = true

            isUpdating = true
            obj.Visible = not _G.hasUnlockedTimerThisRound and not _G.isRoundEnded
            obj.TextColor3 = WHITE_COLOR
            obj.TextStrokeTransparency = 0
            obj.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
            isUpdating = false
            return
        end

        if isTimerPattern(rawTxt) and not _G.isRoundEnded then
            scoreLabel = obj

            if _G.hasUnlockedTimerThisRound and _G.isInnocentMode then
                updateRealtimeDisplay()
            else
                isUpdating = true
                obj.Visible = not _G.isRoundEnded

                local hasMOrS = lowerTxt:find("m") or lowerTxt:find("s")

                if hasMOrS then
                    obj.TextColor3 = WHITE_COLOR
                    local secs = parseTextToSeconds(rawTxt)
                    if secs then
                        obj.Text = secondsToFormattedText(secs)
                    end
                else
                    obj.TextColor3 = ORANGE_COLOR
                end

                obj.TextStrokeTransparency = 0
                obj.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

                if headerLabel then
                    headerLabel.Visible = not _G.hasUnlockedTimerThisRound and not _G.isRoundEnded
                    headerLabel.TextColor3 = WHITE_COLOR
                    headerLabel.TextStrokeTransparency = 0
                    headerLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
                end
                isUpdating = false
            end
        end
    end

    local conn = obj:GetPropertyChangedSignal("Text"):Connect(function()
        if not isUpdating then
            atualizar()
        end
    end)

    table.insert(_G.MM2Connections, conn)
    atualizar()
end

local function monitorCharacter(char)
    local equippedWeapon = nil

    local c1 = char.ChildAdded:Connect(function(child)
        if isWeaponTool(child) then
            equippedWeapon = child
        end
    end)

    local c2 = char.ChildRemoved:Connect(function(child)
        if not _G.isInnocentMode or _G.isRoundEnded then return end

        if isWeaponTool(child) or (equippedWeapon and child == equippedWeapon) then
            equippedWeapon = nil
            local currentTxt = scoreLabel and scoreLabel.Text or "0"
            unlockRealtimeTimer(currentTxt)
        end
    end)

    table.insert(_G.MM2Connections, c1)
    table.insert(_G.MM2Connections, c2)

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local diedConn = humanoid.Died:Connect(function()
            if _G.isInnocentMode then
                _G.isRoundEnded = true
                hideTimerUI()
            end
        end)
        table.insert(_G.MM2Connections, diedConn)
    end
end

if player.Character then monitorCharacter(player.Character) end

local charConn = player.CharacterAdded:Connect(function(char)
    _G.hasUnlockedTimerThisRound = false
    _G.isRoundEnded = false
    _G.isInnocentMode = false
    _G.roundEndTime = nil
    scoreLabel = nil
    headerLabel = nil
    trackedLabels = {}
    task.wait(0.5)

    cacheHUDLabels()
    monitorCharacter(char)
end)
table.insert(_G.MM2Connections, charConn)

local pGui = player:WaitForChild("PlayerGui", 5)
if pGui then
    cacheHUDLabels()
    for _, v in ipairs(pGui:GetDescendants()) do
        if isMainHUDLabel(v) then applyMM2Formatting(v) end
    end

    local descConn = pGui.DescendantAdded:Connect(function(v)
        if isMainHUDLabel(v) then applyMM2Formatting(v) end
    end)
    table.insert(_G.MM2Connections, descConn)
end
