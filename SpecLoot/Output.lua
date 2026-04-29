local addonName, addonTable = ...

-- Reusable popup that displays multi-line text in a selectable EditBox so it can
-- be Ctrl+A / Ctrl+C'd out of the game. Used by /sl debug and /sl probe.

local Output = {}
addonTable.Output = Output

local frame

local function ensureFrame()
    if frame then return end

    frame = CreateFrame("Frame", "SpecLootOutputFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(720, 520)
    frame:SetPoint("CENTER")
    -- Sit above the main SpecLoot frame so dungeon-icon / item-row buttons inside
    -- it can't bleed through. DIALOG strata is one tier above MEDIUM (default).
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame.TitleText:SetText("SpecLoot Output")
    frame:Hide()
    tinsert(UISpecialFrames, "SpecLootOutputFrame")

    local scroll = CreateFrame("ScrollFrame", "SpecLootOutputScroll", frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 12, -32)
    scroll:SetPoint("BOTTOMRIGHT", -32, 12)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetFontObject("GameFontHighlightSmall")
    edit:SetAutoFocus(false)
    edit:SetWidth(scroll:GetWidth())
    edit:SetScript("OnEscapePressed", function() frame:Hide() end)
    scroll:SetScrollChild(edit)

    frame.edit = edit
    frame.scroll = scroll
end

-- Show text in the popup. `title` is appended to "SpecLoot — " in the title bar.
function Output:Show(title, text)
    ensureFrame()
    frame.TitleText:SetText(title and ("SpecLoot — " .. title) or "SpecLoot Output")
    frame.edit:SetText(text or "")
    frame.edit:SetCursorPosition(0)
    frame.edit:HighlightText(0, 0)
    frame:Show()
    frame.scroll:SetVerticalScroll(0)
end
