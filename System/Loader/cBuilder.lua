br.loader = {}
function br.loader.loadProfiles()
    local specID = GetSpecializationInfo(GetSpecialization())
    wipe(br.rotations)
    local function rotationsDirectory()
	    return GetWoWDirectory() .. '\\Interface\\AddOns\\BadRotations\\Rotations\\'
	end

	local function classDirectories()
	    return GetSubdirectories(rotationsDirectory()..'*')
	end

	local function specDirectories(class)
	    return GetSubdirectories(rotationsDirectory() .. class .. '\\*')
	end

	local function profiles(class, spec)
	    return GetDirectoryFiles(rotationsDirectory() .. class .. '\\' .. spec .. '\\*.lua')
	end

    -- Search each Class Folder in the Rotations Folder
    for _, class in pairs(classDirectories()) do
        -- Search each Spec Folder in the Class Folder
        for _, spec in pairs(specDirectories(class)) do
            -- Search each Profile in the Spec Folder
            for _, file in pairs(profiles(class, spec)) do
                local profile = ReadFile(rotationsDirectory()..class.."\\"..spec.."\\"..file)
                local start = string.find(profile,"local id = ",1,true) or 0
                profileID = tonumber(string.sub(profile,start+10,start+13)) or 0
                -- Print(profileID)
                local loadProfile, error = loadstring(profile,file)
                if profileID == specID then loadProfile() end
            end
        end
    end
end

function br.loader:new(spec,specName)
    local loadStart = debugprofilestop()
    local self = cCharacter:new(tostring(select(1,UnitClass("player"))))
    local player = "player" -- if someone forgets ""

    if not brLoaded then
        br.loader.loadProfiles()
        brLoaded = true
    end

    self.profile = specName

    -- Mandatory !
    self.rotation = br.rotations[spec][br.selectedProfile]

    -- Spells From Spell Table
    local function getSpellsForSpec(spec)
        local playerClass = select(2,UnitClass('player'))
        for unitClass , classTable in pairs(br.lists.spells) do
            if unitClass == playerClass or unitClass == 'Shared' then
                for specID, specTable in pairs(classTable) do
                    if specID == spec or specID == 'Shared' then
                        for spellType, spellTypeTable in pairs(specTable) do
                            if self.spell[spellType] == nil then self.spell[spellType] = {} end
                            for spellRef, spellID in pairs(spellTypeTable) do
                                self.spell[spellType][spellRef] = spellID
                                if not IsPassiveSpell(spellID)
                                    and (spellType == 'abilities' or spellType == 'traits' or spellType == 'talents')
                                then
                                    if self.spell.abilities == nil then self.spell.abilities = {} end
                                    self.spell.abilities[spellRef] = spellID
                                    self.spell[spellRef] = spellID
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    -- Update Talent Info
    local function getTalentInfo()
        br.activeSpecGroup = GetActiveSpecGroup()
        if self.talent == nil then self.talent = {} end
        for r = 1, 7 do --search each talent row
            for c = 1, 3 do -- search each talent column
            -- Cache Talent IDs for talent checks
                local _,_,_,selected,_,talentID = GetTalentInfo(r,c,br.activeSpecGroup)
                -- Compare Row/Column Spell Id to Talent Id List for matches
                for k,v in pairs(self.spell.talents) do
                    if v == talentID then
                        -- Add All Matches to Talent List for Boolean Checks
                        self.talent[k] = selected
                        -- Add All Active Ability Matches to Ability/Spell List for Use Checks
                        if not IsPassiveSpell(v) then
                            self.spell['abilities'][k] = v
                            self.spell[k] = v
                        end
                    end
                end
            end
        end
    end

    local function getFunctions()
        -- if not UnitAffectingCombat("player") then
        -- Build Artifact Info
        for k,v in pairs(self.spell.artifacts) do
            if not self.artifact[k] then self.artifact[k] = {} end
            local artifact = self.artifact[k]

            artifact.enabled = function()
                return hasPerk(v)
            end
            artifact.rank = function()
                return getPerkRank(v)
            end
        end

        local function getAzeriteTraitInfo(traitID)
            local rank = 0
            local azeriteItemLocation = C_AzeriteItem.FindActiveAzeriteItem()
            if (not azeriteItemLocation) then return end
            local azeritePowerLevel = C_AzeriteItem.GetPowerLevel(azeriteItemLocation)
            for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED - 1 do -- exclude tabard
                local item = Item:CreateFromEquipmentSlot(slot)
                if (not item:IsItemEmpty()) then
                    local itemLocation = item:GetItemLocation()
                    if (C_AzeriteEmpoweredItem.IsAzeriteEmpoweredItem(itemLocation)) then
                        local tierInfo = C_AzeriteEmpoweredItem.GetAllTierInfo(itemLocation)
                        for tier, info in next, tierInfo do
                            if (info.unlockLevel <= azeritePowerLevel) then
                                for _, powerID in next, info.azeritePowerIDs do
                                    local isSelected = C_AzeriteEmpoweredItem.IsPowerSelected(itemLocation,powerID)
                                    local powerInfo = C_AzeriteEmpoweredItem.GetPowerInfo(powerID)
                                    if (powerInfo) then
                                        local azeriteSpellID = powerInfo["spellID"]
                                        if isSelected and azeriteSpellID == traitID then rank = rank + 1 end
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if rank > 0 then return true, rank else return false, rank end
        end

        -- Build Azerite Trait Info
        if self.spell.traits ~= nil then
            for k,v in pairs(self.spell.traits) do
                if not self.traits[k] then self.traits[k] = {} end
                local traits = self.traits[k]
                local specID = GetSpecializationInfo(GetSpecialization())
                self.traits[k].active = function()
                    return select(1, getAzeriteTraitInfo(v)) or false
                end
                self.traits[k].rank = function()
                    return select(2, getAzeriteTraitInfo(v)) or 0
                end
            end
        end

        -- Update Power
        if not self.power then self.power = {} end
        self.power.list     = {
            mana            = 0, --SPELL_POWER_MANA, --0,
            rage            = 1, --SPELL_POWER_RAGE, --1,
            focus           = 2, --SPELL_POWER_FOCUS, --2,
            energy          = 3, --SPELL_POWER_ENERGY, --3,
            comboPoints     = 4, --SPELL_POWER_COMBO_POINTS, --4,
            runes           = 5, --SPELL_POWER_RUNES, --5,
            runicPower      = 6, --SPELL_POWER_RUNIC_POWER, --6,
            soulShards      = 7, --SPELL_POWER_SOUL_SHARDS, --7,
            astralPower     = 8, --SPELL_POWER_LUNAR_POWER, --8,
            holyPower       = 9, --SPELL_POWER_HOLY_POWER, --9,
            altPower        = 10, --SPELL_POWER_ALTERNATE_POWER, --10,
            maelstrom       = 11, --SPELL_POWER_MAELSTROM, --11,
            chi             = 12, --SPELL_POWER_CHI, --12,
            insanity        = 13, --SPELL_POWER_INSANITY, --13,
            obsolete        = 14,
            obsolete2       = 15,
            arcaneCharges   = 16, --SPELL_POWER_ARCANE_CHARGES, --16,
            fury            = 17, --SPELL_POWER_FURY, --17,
            pain            = 18, --SPELL_POWER_PAIN, --18,
        }
        for k, v in pairs(self.power.list) do
            if not self.power[k] then self.power[k] = {} end
            local power = self.power[k]
            local isDKRunes = select(2,UnitClass("player")) == "DEATHKNIGHT" and v == 5

            power.amount = function()
                if isDKRunes then
                    local runeCount = 0
                    for i = 1, 6 do
                        runeCount = runeCount + GetRuneCount(i)
                    end
                    return runeCount
                else
                    return getPower("player",v)
                end
            end
            power.deficit = function()
                return getPowerMax("player",v) - getPower("player",v)
            end
            power.frac = function()
                if isDKRunes then
                    local runeCount = 0
                    for i = 1, 6 do
                        runeCount = runeCount + GetRuneCount(i)
                    end
                    return runeCount + math.max(runeCDPercent(1),runeCDPercent(2),runeCDPercent(3),runeCDPercent(4),runeCDPercent(5),runeCDPercent(6))
                else
                    return 0
                end
            end
            power.max = function()
                return getPowerMax("player",v)
            end
            power.percent = function()
                if getPowerMax("player",v) == 0 then
                    return 0
                else
                    return ((getPower("player",v) / getPowerMax("player",v)) * 100)
                end
            end
            power.regen = function()
                return getRegen("player")
            end
            power.ttm = function(amount)
                if amount == nil then amount = 6 end
                if isDKRunes then
                    return runeTimeTill(amount)
                else
                    return getTimeToMax("player")
                end
            end
        end

        -- Build Buff Info
        for k,v in pairs(self.spell.buffs) do
            if k ~= "rollTheBones" then
                if self.buff[k] == nil then self.buff[k] = {} end
                local buff = self.buff[k]
                buff.cancel = function(thisUnit,sourceUnit)
                    if thisUnit == nil then thisUnit = 'player' end
                    if sourceUnit == nil then sourceUnit = 'player' end
                    if UnitBuffID(thisUnit,v,sourceUnit) ~= nil then
                        RunMacroText("/cancelaura "..GetSpellInfo(v))
                        -- CancelUnitBuff(thisUnit,v,sourceUnit)
                    end
                end
                buff.exists = function(thisUnit,sourceUnit)
                    if thisUnit == nil then thisUnit = 'player' end
                    if sourceUnit == nil then sourceUnit = 'player' end
                    return UnitBuffID(thisUnit,v,sourceUnit) ~= nil
                end
                buff.duration = function(thisUnit,sourceUnit)
                    if thisUnit == nil then thisUnit = 'player' end
                    if sourceUnit == nil then sourceUnit = 'player' end
                    return getBuffDuration(thisUnit,v,sourceUnit)
                end
                buff.remain = function(thisUnit,sourceUnit)
                    if thisUnit == nil then thisUnit = 'player' end
                    if sourceUnit == nil then sourceUnit = 'player' end
                    return math.abs(getBuffRemain(thisUnit,v,sourceUnit))
                end
                buff.stack = function(thisUnit,sourceUnit)
                    if thisUnit == nil then thisUnit = 'player' end
                    if sourceUnit == nil then sourceUnit = 'player' end
                    return getBuffStacks(thisUnit,v,sourceUnit)
                end
                buff.refresh = function(thisUnit,sourceUnit)
                    return buff.remain(thisUnit,sourceUnit) <= buff.duration(thisUnit,sourceUnit) * 0.3
                end
                buff.count = function()
                    return tonumber(getBuffCount(v))
                end
            end
        end
        -- Build Debuff Info
        function self.getSnapshotValue(dot)
            -- Feral Bleeds
            if GetSpecializationInfo(GetSpecialization()) == 103 then
                local multiplier        = 1.00
                local Bloodtalons       = 1.30
                -- local SavageRoar        = 1.40
                local TigersFury        = 1.15
                local RakeMultiplier    = 1
                -- Bloodtalons
                if self.buff.bloodtalons.exists() then multiplier = multiplier*Bloodtalons end
                -- Savage Roar
                -- if self.buff.savageRoar.exists() then multiplier = multiplier*SavageRoar end
                -- Tigers Fury
                if self.buff.tigersFury.exists() then multiplier = multiplier*TigersFury end
                -- rip
                if dot == self.spell.debuffs.rip then
                    -- -- Versatility
                    -- multiplier = multiplier*(1+Versatility*0.1)
                    -- return rip
                    return 5*multiplier
                end
                -- rake
                if dot == self.spell.debuffs.rake then
                    -- Incarnation/Prowl
                    if self.buff.incarnationKingOfTheJungle.exists() or self.buff.prowl.exists() then
                        RakeMultiplier = 2
                    end
                    -- return rake
                    return multiplier*RakeMultiplier
                end
                return 0
            end
        end

        for k,v in pairs(self.spell.debuffs) do
            if self.debuff[k] == nil then self.debuff[k] = {} end
            local debuff = self.debuff[k]
            debuff.exists = function(thisUnit,sourceUnit)
                if thisUnit == nil then thisUnit = 'target' end
                if sourceUnit == nil then sourceUnit = 'player' end
                return UnitDebuffID(thisUnit,v,sourceUnit) ~= nil
            end
            debuff.duration = function(thisUnit,sourceUnit)
                if thisUnit == nil then thisUnit = 'target' end
                if sourceUnit == nil then sourceUnit = 'player' end
                return getDebuffDuration(thisUnit,v,sourceUnit) or 0
            end
            debuff.remain = function(thisUnit,sourceUnit)
                if thisUnit == nil then thisUnit = 'target' end
                if sourceUnit == nil then sourceUnit = 'player' end
                return math.abs(getDebuffRemain(thisUnit,v,sourceUnit))
            end
            debuff.stack = function(thisUnit,sourceUnit)
                if thisUnit == nil then thisUnit = 'target' end
                if sourceUnit == nil then sourceUnit = 'player' end
                if getDebuffStacks(thisUnit,v,sourceUnit) == 0 and UnitDebuffID(thisUnit,v,sourceUnit) ~= nil then
                    return 1
                else
                    return getDebuffStacks(thisUnit,v,sourceUnit)
                end
            end
            debuff.refresh = function(thisUnit,sourceUnit)
                if thisUnit == nil then thisUnit = 'target' end
                if sourceUnit == nil then sourceUnit = 'player' end
                return debuff.remain(thisUnit,sourceUnit) <= debuff.duration(thisUnit,sourceUnit) * 0.3
            end
            debuff.count = function()
                return tonumber(getDebuffCount(v))
            end
            debuff.remainCount = function(remain)
                return tonumber(getDebuffRemainCount(v,remain))
            end
            debuff.lowest = function(range,debuffType)
                if range == nil then range = 40 end
                if debuffType == nil then debuffType = "remain" end
                return getDebuffMinMax(k, range, debuffType, "min")
            end
            debuff.max = function(range,debuffType)
                if range == nil then range = 40 end
                if debuffType == nil then debuffType = "remain" end
                return getDebuffMinMax(k, range, debuffType, "max")
            end
            if spec == 103 then
                debuff.calc = function()
                    return self.getSnapshotValue(v)
                end
                debuff.applied = function(thisUnit)
                    return debuff.bleed[thisUnit] or 0
                end
            end
        end

        self.units.get = function(range,aoe)
            if aoe == nil then aoe = false end
            if aoe then
                if self.units["dyn"..range.."AOE"] == nil then self.units["dyn"..range.."AOE"] = {} end
                self.units["dyn"..range.."AOE"] =  dynamicTarget(range, false)
            else
                if self.units["dyn"..range] == nil then self.units["dyn"..range] = {} end
                self.units["dyn"..range] =  dynamicTarget(range, true)
            end
            return aoe and dynamicTarget(range, false) or dynamicTarget(range, true)
        end

        self.enemies.get = function(range,unit,checkNoCombat)
            if unit == nil then unit = "player" end
            if checkNoCombat == nil then checkNoCombat = false end
            local enemyTable = getEnemies(unit,range,checkNoCombat)
            if unit ~= "player" then
                if checkNoCombat then insertTable = "yards"..range..unit:sub(1,1).."nc" else insertTable = "yards"..range..unit:sub(1,1) end
            else
                if checkNoCombat then insertTable = "yards"..range.."nc" else insertTable = "yards"..range end
            end
            if self.enemies[insertTable] == nil then self.enemies[insertTable] = {} else wipe(self.enemies[insertTable]) end
            if #enemyTable > 0 then insertTableIntoTable(self.enemies[insertTable],enemyTable) end
            return enemyTable
        end

        if self.spell.pets ~= nil then
            if self.pet.active == nil then self.pet.active = {} end
            self.pet.active.exists = function()
                return GetObjectExists("pet")
            end

            self.pet.active.count = function()
                local count = 0
                for k,v in pairs(self.pet.list) do
                    local listID = self.pet.list[k].id
                    if GetObjectID("pet") == listID then count = count + 1 end
                end
                return count
            end

            for k,v in pairs(self.spell.pets) do
                if self.pet[k] == nil then self.pet[k] = {} end

                local pet = self.pet[k]
                pet.exists = function()
                    return GetObjectExists(v)
                end

                pet.count = function()
                    local count = 0
                    for l,w in pairs(self.pet.list) do
                        local listID = self.pet.list[l].id
                        if v == listID then count = count + 1 end
                    end
                    return count
                end
            end
        end

        -- if self.pet.buff == nil then self.pet.buff = {} end
        -- self.pet.buff.exists = function(buffID,petID)
        --     for k, v in pairs(self.pet) do
        --         local pet = self.pet[k]
        --         if self.pet[k].id == petID and UnitBuffID(k,buffID) ~= nil then return true end
        --     end
        --     return false
        -- end

        -- self.pet.buff.count = function(buffID,petID)
        --     local petCount = 0
        --     for k, v in pairs(self.pet) do
        --         local pet = self.pet[k]
        --         if self.pet[k].id == petID and UnitBuffID(k,buffID) ~= nil then petCount = petCount + 1 end
        --     end
        --     return petCount
        -- end

        -- self.pet.buff.missing = function(buffID,petID)
        --     local petCount = 0
        --     for k, v in pairs(self.pet) do
        --         local pet = self.pet[k]
        --         if self.pet[k].id == petID and UnitBuffID(k,buffID) == nil then petCount = petCount + 1 end
        --     end
        --     return petCount
        -- end


        -- Cycle through Items List
        for k,v in pairs(self.spell.items) do
            if self.charges[k]  == nil then self.charges[k] = {} end -- Item Charge Functions
            if self.equiped     == nil then self.equiped    = {} end -- Use Item Debugging
            if self.has         == nil then self.has        = {} end -- Item In Bags
            if self.use         == nil then self.use        = {} end -- Use Item Functions
            if self.use.able    == nil then self.use.able   = {} end -- Useable Item Check Functions

            local charges = self.charges[k]
            charges.exists = function()
                return itemCharges(v) > 0
            end
            charges.count = function()
                return itemCharges(v)
            end

            self.use[k] = function(slotID)
                if slotID == nil then
                    if canUse(v) then return useItem(v) else return end
                else
                    if canUse(slotID) then return useItem(slotID) else return end
                end
            end
            self.use.able[k] = function(slotID)
                if slotID == nil then return canUse(v) else return canUse(slotID) end
            end

            self.equiped[k] = function(slotID)
                if slotID == nil then
                    return hasEquiped(v)
                else
                    return hasEquiped(v,slotID)
                end
            end

            self.has[k] = function()
                return hasItem(v)
            end
        end

        self.use.slot = function(slotID)
            if canUse(slotID) then return useItem(slotID) else return end
        end
        self.use.able.slot = function(slotID)
            return canUse(slotID)
        end

        -- if UnitDebuffID("player", 240447) ~= nil and (getCastTime(v) + 0.15) > getDebuffRemain("player",240447) then end
        -- Cycle through Abilities List
        for k,v in pairs(self.spell.abilities) do
            if self.cast            == nil then self.cast               = {} end        -- Cast Spell Functions
            if self.cast.debug      == nil then self.cast.debug         = {} end        -- Cast Spell Debugging
            if self.cast.able       == nil then self.cast.able          = {} end        -- Cast Spell Available
            if self.cast.active     == nil then self.cast.active        = {} end        -- Cast Spell Active
            if self.cast.cost       == nil then self.cast.cost          = {} end        -- Cast Spell Cost
            if self.cast.pool       == nil then self.cast.pool          = {} end        -- Cast Spell Pooling
            if self.cast.current    == nil then self.cast.current       = {} end        -- Cast Spell Current
            if self.cast.last       == nil then self.cast.last          = {} end        -- Cast Spell Last
            if self.cast.range      == nil then self.cast.range         = {} end        -- Cast Spell Range
            if self.cast.regen      == nil then self.cast.regen         = {} end        -- Cast Spell Regen
            if self.cast.safe       == nil then self.cast.safe          = {} end        -- Case Spell Safe
            if self.cast.time       == nil then self.cast.time          = {} end        -- Cast Spell Time
            if self.charges[k]      == nil then self.charges[k]         = {} end        -- Spell Charge Functions
            if self.cd[k]           == nil then self.cd[k]              = {} end        -- Spell Cooldown Functions

            -- Build Spell Charges
            local charges = self.charges[k]
            charges.exists = function()
                return getCharges(v) >= 1
            end
            charges.count = function()
                return getCharges(v)
            end
            charges.frac = function()
                return getChargesFrac(v)
            end
            charges.max = function()
                return getChargesFrac(v,true)
            end
            charges.recharge = function(chargeMax)
                if chargeMax then
                    return getRecharge(v,true)
                else
                    return getRecharge(v)
                end
            end
            charges.timeTillFull = function()
                return getFullRechargeTime(v)
            end

            -- Build Spell Cooldown
            local cd = self.cd[k]
            cd.exists = function()
                return getSpellCD(v) > 0
            end
            cd.remain = function()
                return getSpellCD(v)
            end

            -- Build Cast Funcitons
            self.cast[k] = function(thisUnit,debug,minUnits,effectRng)
                return createCastFunction(thisUnit,debug,minUnits,effectRng,v,k)
            end

            self.cast.able[k] = function(thisUnit,debug,minUnits,effectRng)
                return createCastFunction(thisUnit,"debug",minUnits,effectRng,v,k)
                -- return self.cast[v](nil,"debug")
            end

            self.cast.active[k] = function(unit)
                if unit == nil then unit = "player" end
                return isCastingSpell(v,unit)
            end

            self.cast.cost[k] = function(altPower)
                if altPower == nil then altPower = false end
                if altPower then
                    return select(2,getSpellCost(v))
                else
                    return select(1,getSpellCost(v))
                end
            end

            self.cast.pool[k] = function(altPower,specificAmt)
                local powerType = select(2,UnitPowerType("player")):lower()
                specificAmt = specificAmt or 0
                if altPower == nil then altPower = false end
                return self.power[powerType].amount() < self.cast.cost[k](altPower) or self.power[powerType].amount() < specificAmt
            end

            self.cast.current[k] = function(spellID,unit)
                if spellID == nil then spellID = v end
                if unit == nil then unit = "player" end
                return isCastingSpell(spellID,unit)
            end

            self.cast.last[k] = function(index)
                if index == nil then index = 1 end
                if index == 1 then return lastCast == v end
                if index == 2 then return lastCast2 == v end
                if index == 3 then return lastCast3 == v end
                if index == 4 then return lastCast4 == v end
                if index == 5 then return lastCast5 == v end
                return false
            end

            self.cast.range[k] = function()
                return getSpellRange(v)
            end

            self.cast.regen[k] = function()
                return getCastingRegen(v)
            end

            self.cast.safe[k] = function(unit,effectRng,minUnits,aoeType)
                return isSafeToAoE(v,unit,effectRng,minUnits,aoeType)
            end

            self.cast.time[k] = function()
                return getCastTime(v)
            end
        end
    end

    if self.talent == nil or self.cast == nil then getSpellsForSpec(spec); getTalentInfo(); getFunctions(); br.updatePlayerInfo = false end
------------------
--- OOC UPDATE ---
------------------

    function self.updateOOC()
        -- Call baseUpdateOOC()
        self.baseUpdateOOC()
    end

--------------
--- UPDATE ---
--------------

    function self.update()
        -- Call baseUpdate()
        if not UnitAffectingCombat("player") then self.updateOOC() end
        self.baseUpdate()
        -- Update Player Info on Init, Talent, and Level Change
        if br.updatePlayerInfo then getSpellsForSpec(spec); getTalentInfo(); getFunctions(); br.updatePlayerInfo = false end
        self.getBleeds()
        self.getToggleModes()
        -- Start selected rotation
        self.startRotation()
    end

---------------
--- BLEEDS  ---
---------------
    function self.getBleeds()
        if spec == 103 then
            for k, v in pairs(self.debuff) do
                if k == "rake" or k == "rip" then
                    if self.debuff[k].bleed == nil then self.debuff[k].bleed = {} end
                    for l, w in pairs(self.debuff[k].bleed) do
                        if not UnitAffectingCombat("player") or UnitIsDeadOrGhost(l) then
                            self.debuff[k].bleed[l] = nil
                        elseif not self.debuff[k].exists(l) then
                            self.debuff[k].bleed[l] = 0
                        end
                    end
                end
            end
        end
    end

---------------
--- TOGGLES ---
---------------

    function self.getToggleModes()

        self.mode.rotation      = br.data.settings[br.selectedSpec].toggles["Rotation"]
        self.mode.cooldown      = br.data.settings[br.selectedSpec].toggles["Cooldown"]
        self.mode.defensive     = br.data.settings[br.selectedSpec].toggles["Defensive"]
        self.mode.interrupt     = br.data.settings[br.selectedSpec].toggles["Interrupt"]
    end

    -- Create the toggle defined within rotation files
    function self.createToggles()
        GarbageButtons()
        if self.rotation ~= nil then
            self.rotation.toggles()
        else
            return
        end
    end

---------------
--- OPTIONS ---
---------------

    -- Class options
    -- Options which every Rogue should have
    -- function self.createClassOptions()
    --     -- Class Wrap
    --     local section = br.ui:createSection(br.ui.window.profile,  "Class Options", "Nothing")
    --     br.ui:checkSectionState(section)
    -- end
    -- Create Spell Index
    -- function self.createSpellIndex()
    --     section = br.ui:createSection(br.ui.window.profile,  "Spells - Uncheck to prevent bot use")
    --     for k,v in pairs(self.spell.abilities) do
    --         if v ~= 61304 and v ~= 28880 and v ~= 58984 and v ~= 107079 then
    --             br.ui:createCheckbox(section, "Use: "..tostring(GetSpellInfo(v)),"|cFFED0000 WARNING!".."|cFFFFFFFF Unchecking spell may cause rotation to not function correctly or at all.",true)
    --         end
    --     end
    -- end
     -- Creates the option/profile window
    function self.createOptions()
        -- if br.ui:closeWindow("profile")
        for i = 1, #br.data.settings[br.selectedSpec] do
            local thisProfile = br.data.settings[br.selectedSpec][i]
            if thisProfile ~= br.data.settings[br.selectedSpec][br.selectedProfile] then
                br.ui:closeWindow("profile")
            end
        end
        if br.data.settings[br.selectedSpec][br.selectedProfile] == nil then br.data.settings[br.selectedSpec][br.selectedProfile] = {} end
        br.ui:createProfileWindow(self.profile)

        -- Get the names of all profiles and create rotation dropdown
        local names = {}
        for i=1,#br.rotations[spec] do
            local thisName = br.rotations[spec][i].name
            tinsert(names, thisName)
        end

        br.ui:createRotationDropdown(br.ui.window.profile.parent, names)

        -- Create Base and Class option table
        local optionTable = {
            {
                [1] = "Base Options",
                [2] = self.createBaseOptions,
            },
            -- {
            --     [1] = "Spell Index",
            --     [2] = self.createSpellIndex,
            -- },
        }

        -- -- Get profile defined options
        -- local profileTable = profileTable
        -- if self.rotation~= nil then
        --     profileTable = self.rotation.options()
        -- else
        --     return
        -- end
        --
        -- -- Only add profile pages if they are found
        -- if profileTable then
            insertTableIntoTable(optionTable, self.rotation.options())
        -- end



        -- Create pages dropdown
        br.ui:createPagesDropdown(br.ui.window.profile, optionTable)

        -- br:checkProfileWindowStatus()
        br.ui:checkWindowStatus("profile")
    end

------------------------
--- CUSTOM FUNCTIONS ---
------------------------

    function useAoE()
        local rotation = self.mode.rotation
        if (rotation == 1 and #self.enemies.get(8) >= 3) or rotation == 2 then
            return true
        else
            return false
        end
    end

    function useCDs()
        local cooldown = self.mode.cooldown
        if (cooldown == 1 and isBoss()) or cooldown == 2 then
            return true
        else
            return false
        end
    end

    function useDefensive()
        if self.mode.defensive == 1 then
            return true
        else
            return false
        end
    end

    function useInterrupts()
        if self.mode.interrupt == 1 then
            return true
        else
            return false
        end
    end

    function useMfD()
        if self.mode.mfd == 1 then
            return true
        else
            return false
        end
    end

    function useRollForTB()
        if self.mode.RerollTB == 1 then
            return true
        else
            return false
        end
    end

     function useRollForOne()
        if self.mode.RollForOne == 1  then
            return true
        else
            return false
        end
    end

    function ComboMaxSpend()
        return br.player.talent.deeperStrategem and 6 or 5
    end

    function ComboSpend()
        return math.min(br.player.power.comboPoints.amount(), ComboMaxSpend())
    end

    function mantleDuration()
        if hasEquiped(144236) then
            --if br.player.buff.masterAssassinsInitiative.remain("player") > 100 or br.player.buff.masterAssassinsInitiative.remain("player") < 0 then
            if br.player.buff.masterAssassinsInitiative.exists("player") and (getBuffRemain("player",235027) > 100 or getBuffRemain("player",235027) < 100) then
                return br.player.cd.global.remain() + 5
            else
                --return br.player.buff.masterAssassinsInitiative.remain("player")
                if getBuffRemain("player",235027) >= 0 and getBuffRemain("player",235027) < 0.1 then
                    return 0
                else
                    return getBuffRemain("player",235027)
                end
            end
        else
            return 0
        end
    end

    function BleedTarget()
        return (br.player.debuff.garrote.exists("target") and 1 or 0) + (br.player.debuff.rupture.exists("target") and 1 or 0) + (br.player.debuff.internalBleeding.exists("target") and 1 or 0)
    end

    -- Debugging
        br.debug.cpu.rotation.loadTime = debugprofilestop()-loadStart
-----------------------------
--- CALL CREATE FUNCTIONS ---
-----------------------------
    -- Return
    return self
end --End function
