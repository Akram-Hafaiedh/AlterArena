local ADDON_NAME, ns = ...

-- Tracks how long you've been queued (any BG/Arena slot) and shows a
-- sleek movable timer matching the modern PvPQTimer aesthetic.
-- Alerts once when a queue pops (status "confirm").

local currentQueue = nil   -- populated by CheckQueues; nil when not queued
local isTestMode = false
local alerted = {}         -- [slot] = true once we've played the pop alert
local timerFrame
local elapsedSinceUpdate = 0

local QUEUE_TYPE_LABELS = {
    RATEDSHUFFLE = "Shuffle",
    BATTLEGROUND = "Battleground",
    RATEDBG = "Blitz",
    WARGAME = "War Game",
}

local function EnsurePVPInfo()
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_PVPUI")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_PVPUI")
    end
    if RequestRatedInfo then
        pcall(RequestRatedInfo)
    end
end

local function FormatDuration(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d min %d sec", m, s)
end

local function QueueLabel(q)
    if q.isSoloQueue or q.queueType == "RATEDSHUFFLE" then
        return "Shuffle"
    elseif q.queueType == "ARENA" then
        if q.teamSize == 2 then return "2v2" end
        if q.teamSize == 3 then return "3v3" end
        return "Arena"
    elseif q.queueType == "RATEDBG" then
        return "Blitz"
    end
    return QUEUE_TYPE_LABELS[q.queueType] or q.queueType or "Queue"
end

local function IsRatedQueue(q)
    if q.isSoloQueue or q.queueType == "RATEDSHUFFLE" or q.queueType == "RATEDBG" then
        return true
    end
    if q.queueType == "ARENA" and (q.teamSize == 2 or q.teamSize == 3) then
        return true
    end
    return false
end

local function GetBracketIndex(bracketName)
    EnsurePVPInfo()
    local target = string.lower(bracketName or "")

    if CONQUEST_SIZE_STRINGS and CONQUEST_BRACKET_INDEXES then
        for i, name in pairs(CONQUEST_SIZE_STRINGS) do
            if name and string.find(string.lower(name), target) then
                return CONQUEST_BRACKET_INDEXES[i] or i
            end
        end
    end

    if target == "2v2" then return 1 end
    if target == "3v3" then return 2 end
    if target == "shuffle" then return 7 end
    if target == "blitz" then return 9 end
    return 1
end

-- Rating data sources: WoW API (GetPersonalRatedInfo) + our own match history only.
-- No external addon data scraping.

local function GetCurrentSpecName()
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local _, specName = GetSpecializationInfo(specIndex)
            return specName
        end
    end
    return nil
end

local function GetBracketStorageKey(bracketName)
    local target = string.lower(bracketName or "")
    if target == "shuffle" or target == "solo shuffle" or target == "blitz" or target == "battleground blitz" then
        local spec = GetCurrentSpecName()
        if spec then
            return bracketName .. "-" .. spec
        end
    end
    return bracketName
end

local function UpdatePlayerBracketRating(bracketName, currentRating)
    if not currentRating or currentRating <= 0 then return end
    local playerKey = ns.GetPlayerKey and ns.GetPlayerKey()
    if not playerKey or not AlterArenaDB or not AlterArenaDB.players then return end
    local record = AlterArenaDB.players[playerKey]
    if not record then return end

    record.bracketRatings = record.bracketRatings or {}
    local storageKey = GetBracketStorageKey(bracketName)
    local data = record.bracketRatings[storageKey] or record.bracketRatings[bracketName]

    if not data then
        record.bracketRatings[storageKey] = {
            current = currentRating,
            previous = nil,
            change = 0,
        }
        return
    end

    -- NEW
    local recentMatch = ns.lastMatchTimestamp and (time() - ns.lastMatchTimestamp) < 90
    if currentRating ~= data.current then
        if recentMatch and data.current then
            data.previous = data.current
            data.current  = currentRating
            data.change   = currentRating - data.previous
        else
            data.current  = currentRating
            data.previous = nil
            data.change   = 0
        end
        record.bracketRatings[storageKey] = data
    end
end
ns.UpdateBracketRatingTracking = UpdatePlayerBracketRating

local function GetBracketRating(bracketName)
    if not GetPersonalRatedInfo then return nil end
    EnsurePVPInfo()

    local idx = GetBracketIndex(bracketName)
    local rating = nil
    if idx then
        local r = GetPersonalRatedInfo(idx)
        if r and r > 0 then
            rating = r
        end
    end

    -- Fallback scan across common indices for that bracket
    if not rating then
        if bracketName == "Shuffle" or bracketName == "Solo Shuffle" then
            for _, testIdx in ipairs({ 7, 3 }) do
                local r = GetPersonalRatedInfo(testIdx)
                if r and r > 0 then
                    rating = r
                    break
                end
            end
        elseif bracketName == "Blitz" then
            for _, testIdx in ipairs({ 9 }) do
                local r = GetPersonalRatedInfo(testIdx)
                if r and r > 0 then
                    rating = r
                    break
                end
            end
        end
    end

    if rating and rating > 0 then
        UpdatePlayerBracketRating(bracketName, rating)
        return rating
    end

    return nil
end

local function GetLastMatchRating(bracketName)
    local playerKey = ns.GetPlayerKey and ns.GetPlayerKey()
    if not playerKey or not AlterArenaDB or not AlterArenaDB.players then return nil end
    local record = AlterArenaDB.players[playerKey]
    if not record then return nil end

    local currentSpec = GetCurrentSpecName()
    local isSpecBracket = (bracketName == "Shuffle" or bracketName == "Solo Shuffle" or bracketName == "Blitz" or bracketName == "Battleground Blitz")

    -- 1. Check recorded matches from MatchTracker (matching spec if spec-tracked)
    if record.matches then
        for i = #record.matches, 1, -1 do
            local m = record.matches[i]
            if m then
                local isMatch = (not bracketName)
                    or (m.bracket == bracketName)
                    or (bracketName == "Shuffle" and (m.bracket == "Solo Shuffle" or m.bracket == "Shuffle"))
                    or (bracketName == "Blitz" and (m.bracket == "Battleground Blitz" or m.bracket == "Blitz"))
                local isSpecMatch = (not isSpecBracket) or (not m.spec) or (not currentSpec) or (m.spec == currentSpec)

                if isMatch and isSpecMatch then
                    if m.mmrBefore and m.mmrAfter then
                        return m.mmrBefore, m.mmrAfter, m.mmrChange
                    elseif m.ratingBefore and m.ratingAfter then
                        return m.ratingBefore, m.ratingAfter, m.ratingChange
                    elseif m.ratingAfter then
                        return nil, m.ratingAfter, m.ratingChange
                    end
                end
            end
        end
    end

    -- 2. Check persistent bracket ratings in AlterArenaDB
    if record.bracketRatings then
        local storageKey = GetBracketStorageKey(bracketName)
        local bData = record.bracketRatings[storageKey]
            or record.bracketRatings[bracketName]
            or (bracketName == "Shuffle" and record.bracketRatings["Solo Shuffle"])
            or (bracketName == "Blitz" and record.bracketRatings["Battleground Blitz"])
        if bData and bData.previous and bData.current then
            return bData.previous, bData.current, bData.change or (bData.current - bData.previous)
        end
    end

    return nil
end

local function GetArrowMarkup()
    return "|TInterface\\ChatFrame\\ChatFrameExpandArrow:9:9:0:0:32:32:0:32:0:32:255:209:0|t"
end

local function GetMMRDisplayLine(bracketName)
    local before, after, change = GetLastMatchRating(bracketName)
    local arrow = GetArrowMarkup()

    if before and after then
        if not change or (change == 0 and before ~= after) then
            change = after - before
        end
        local changeStr = ""
        if change > 0 then
            changeStr = string.format(" |cff22c55e(+%d)|r", change)
        elseif change < 0 then
            changeStr = string.format(" |cffef4444(%d)|r", change)
        else
            changeStr = string.format(" |cff888888(+0)|r")
        end
        return string.format("|cffccccccMMR:|r %d %s %d%s", before, arrow, after, changeStr)
    end

    local currentRating = GetBracketRating(bracketName)
    if currentRating and currentRating > 0 then
        return string.format("|cffccccccMMR:|r %d", currentRating)
    end

    return "|cffccccccMMR:|r Unranked"
end

local function CreateTimerDisplay()
    local frame = CreateFrame("Frame", "AlterArenaQueueTimer", UIParent, "BackdropTemplate")
    frame:SetSize(148, 64)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(500)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        if AlterArenaDB then
            AlterArenaDB.timerPosition = { point = point, relPoint = relPoint, x = x, y = y }
        end
    end)
    frame:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8X8",
        edgeFile = "Interface/Buttons/WHITE8X8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    frame:SetBackdropColor(0.06, 0.06, 0.06, 0.88)
    frame:SetBackdropBorderColor(0.18, 0.18, 0.18, 0.95)

    if AlterArenaDB and AlterArenaDB.timerPosition and AlterArenaDB.timerPosition.point then
        local p = AlterArenaDB.timerPosition
        frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    else
        frame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -200)
    end

    frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.text:SetPoint("TOPLEFT", frame, "TOPLEFT", 8, -6)
    frame.text:SetJustifyH("LEFT")
    frame.text:SetJustifyV("TOP")
    frame.text:SetSpacing(2)

    frame:Hide()
    return frame
end

local function OnUpdate(self, delta)
    elapsedSinceUpdate = elapsedSinceUpdate + delta
    if elapsedSinceUpdate < 0.5 then
        return
    end
    elapsedSinceUpdate = 0

    if not currentQueue then
        return
    end

    local label = QueueLabel(currentQueue)
    local lines = {}

    -- Title: yellow / gold bold header
    table.insert(lines, string.format("|cffffd100%s|r", label))

    -- Line 2: MMR (e.g. MMR: 1420 ▶ 1445 (+25))
    local isRated = IsRatedQueue(currentQueue)
    if isRated then
        local mmrText = currentQueue.customMMR or GetMMRDisplayLine(label)
        table.insert(lines, mmrText)
    end

    -- Line 3: Avg wait
    if currentQueue.estimatedWait and currentQueue.estimatedWait > 0 then
        table.insert(lines, string.format("|cffccccccAvg:|r  %s", FormatDuration(currentQueue.estimatedWait)))
    else
        table.insert(lines, "|cffccccccAvg:|r  Unavailable")
    end

    -- Line 4: Time in queue (e.g. Q:    11 sec)
    local timeInQueue = GetTime() - (currentQueue.startTime or GetTime())
    table.insert(lines, string.format("|cffccccccQ:|r    %s", FormatDuration(timeInQueue)))

    timerFrame.text:SetText(table.concat(lines, "\n"))

    -- Auto-fit frame dimensions tightly around the text with exact 8px horizontal / 6px vertical padding
    local textWidth = math.ceil(timerFrame.text:GetStringWidth() or 0)
    local textHeight = math.ceil(timerFrame.text:GetStringHeight() or 0)
    local frameWidth = math.max(140, textWidth + 16)
    local frameHeight = math.max(48, textHeight + 12)
    timerFrame:SetSize(frameWidth, frameHeight)
end

local function PlayPopAlert()
    local soundID = AlterArenaDB
        and AlterArenaDB.settings
        and AlterArenaDB.settings.queueTimerSound
        or "pvpqueue"

    if ns.PlaySoundById then
        ns.PlaySoundById(soundID)
    else
        pcall(PlaySound, 8959)
    end

    print("|cff40c0ffAlterArena|r: Queue popped — accept it!")
end

local function CheckQueues()
    if isTestMode then
        return
    end

    local maxBG = 2
    if GetMaxBattlefieldID then
        local id = GetMaxBattlefieldID()
        if id and id > 0 then
            maxBG = id
        end
    end
    local found = nil

    for slot = 1, maxBG do
        local status, mapName, teamSize, registeredMatch, suspendedQueue, queueType, gameType, role, asGroup, shortDescription, longDescription, isSoloQueue = GetBattlefieldStatus(slot)

        if status == "queued" or status == "confirm" then
            local startTime
            if currentQueue and currentQueue.slot == slot and currentQueue.startTime then
                startTime = currentQueue.startTime
            else
                local waitedMs = (GetBattlefieldTimeWaited and GetBattlefieldTimeWaited(slot)) or 0
                startTime = GetTime() - (waitedMs > 0 and (waitedMs / 1000) or 0)
            end

            local estWait = (GetBattlefieldEstimatedWaitTime and GetBattlefieldEstimatedWaitTime(slot)) or 0

            found = {
                slot = slot,
                mapName = mapName,
                teamSize = teamSize,
                queueType = queueType,
                isSoloQueue = isSoloQueue,
                startTime = startTime,
                estimatedWait = estWait / 1000,
            }

            if status == "confirm" and not alerted[slot] then
                alerted[slot] = true
                ns.lastQueueDuration = math.floor(GetTime() - startTime)
                PlayPopAlert()
            elseif status == "queued" then
                alerted[slot] = nil
                ns.lastQueueDuration = math.floor(GetTime() - startTime)
            end
            break
        end
    end

    currentQueue = found

    if currentQueue and (isTestMode or ns.IsQueueTimerEnabled()) then
        timerFrame:Show()
    else
        timerFrame:Hide()
        if not currentQueue then
            wipe(alerted)
        end
    end
end

function ns.IsQueueTimerEnabled()
    if not AlterArenaDB or not AlterArenaDB.settings then return true end
    if AlterArenaDB.settings.enableQueueTimer == nil then return true end
    return AlterArenaDB.settings.enableQueueTimer
end

function ns.SetQueueTimerEnabled(enabled)
    AlterArenaDB = AlterArenaDB or {}
    AlterArenaDB.settings = AlterArenaDB.settings or {}
    AlterArenaDB.settings.enableQueueTimer = (enabled == true)
    if not enabled then
        if timerFrame then timerFrame:Hide() end
    else
        CheckQueues()
    end
end

function ns.ResetQueueTimerPosition()
    if AlterArenaDB then
        AlterArenaDB.timerPosition = nil
    end
    if not timerFrame then
        timerFrame = CreateTimerDisplay()
        timerFrame:SetScript("OnUpdate", OnUpdate)
    end
    timerFrame:ClearAllPoints()
    timerFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -200)
    timerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    timerFrame:SetFrameLevel(500)
    print("|cff40c0ffAlterArena|r: Queue timer position reset to top-right.")
end

function ns.GetLastQueueDuration()
    return ns.lastQueueDuration
end

function ns.IsTestQueueTimerActive()
    return isTestMode
end

function ns.PrintPvPRatings()
    EnsurePVPInfo()
    local parts = {}
    local brackets = { "2v2", "3v3", "Shuffle", "Blitz" }
    for _, name in ipairs(brackets) do
        local r = GetBracketRating(name)
        if r and r > 0 then
            table.insert(parts, string.format("%s: |cff00ff00%d|r", name, r))
        else
            table.insert(parts, string.format("%s: |cff888888Unranked|r", name))
        end
    end
    print("|cff40c0ffAlterArena|r Ratings: " .. table.concat(parts, " | "))
end

function ns.ToggleTestQueueTimer()
    if not timerFrame then
        timerFrame = CreateTimerDisplay()
        timerFrame:SetScript("OnUpdate", OnUpdate)
    end

    if isTestMode then
        isTestMode = false
        currentQueue = nil
        timerFrame:Hide()
        print("|cff40c0ffAlterArena|r: Queue timer test mode disabled.")
    else
        isTestMode = true
        EnsurePVPInfo()
        currentQueue = {
            slot = 1,
            queueType = "RATEDSHUFFLE",
            isSoloQueue = true,
            startTime = GetTime() - (2 * 60 + 22),
            estimatedWait = 5 * 60 + 16,
        }
        timerFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        timerFrame:SetFrameLevel(500)
        timerFrame:Show()
        timerFrame:Raise()
        OnUpdate(timerFrame, 1)
        print("|cff40c0ffAlterArena|r: Queue timer test mode enabled (showing live character rating). Type /aa test again to hide.")
    end

    if ns.UpdateSettingsUI then
        ns.UpdateSettingsUI()
    end
end

function ns.InitQueueTimer()
    timerFrame = CreateTimerDisplay()
    timerFrame:SetScript("OnUpdate", OnUpdate)

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("UPDATE_BATTLEFIELD_STATUS")
    frame:RegisterEvent("PVP_MATCH_ACTIVE")
    frame:RegisterEvent("PVP_RATED_STATS_UPDATE")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_BATTLEFIELD_STATUS" then
            CheckQueues()
        elseif event == "PVP_RATED_STATS_UPDATE" then
            if timerFrame and timerFrame:IsShown() then
                OnUpdate(timerFrame, 1)
            end
        elseif event == "PLAYER_ENTERING_WORLD" then
            EnsurePVPInfo()
        elseif event == "PVP_MATCH_ACTIVE" then
            if not isTestMode then
                currentQueue = nil
                wipe(alerted)
                timerFrame:Hide()
            end
        end
    end)

    EnsurePVPInfo()
    CheckQueues()
end