LiquidLimeSprayerHUDFix = {};

-- Ohne geladenes Precision Farming gibt es beide Klassen nicht, dann wird der Hook am Dateiende übersprungen.
local precisionFarming = _G["FS25_precisionFarming"];
local ExtendedSprayer = precisionFarming ~= nil and precisionFarming.ExtendedSprayer or nil;
local ExtendedSprayerHUDExtension = precisionFarming ~= nil and precisionFarming.ExtendedSprayerHUDExtension or nil;

---Format a decimal number without unnecessary trailing zeros.
local function formatDecimalNumber(value)
    local text = string.format("%.3f", value);
    text = text:gsub("0+$", "");
    text = text:gsub("[%.%,]$", "");
    return text;
end;

---Render text with an optional max width limit.
local function renderLimitedText(posX, posY, textSize, text, maxWidth)
    if maxWidth ~= nil then
        renderText(posX, posY, textSize, text, maxWidth);
    else
        renderText(posX, posY, textSize, text);
    end;

    return getTextWidth(textSize, text);
end;

function LiquidLimeSprayerHUDFix:draw(superFunc, inputHelpDisplay, posX, posY)
    local vehicle = self.vehicle;
    local spec = self.extendedSprayer;

    if spec == nil then
        return posY;
    end;

    local headline = self.texts.headline_ph_lime;

    local applicationRate = 0;
    local applicationRateReal = 0;
    local applicationRateStr = "%.2f t/ha";

    local changeBarText = "";

    local minValue = 0;
    local maxValue = 0;

    self.hasValidValues = false;

    local soilTypeName = "";

    if spec.lastTouchedSoilType ~= 0 and self.soilMap ~= nil then
        local soilType = self.soilMap:getSoilTypeByIndex(spec.lastTouchedSoilType);
        if soilType ~= nil then
            soilTypeName = soilType.name;
        end;
    end;

    local hasLimeLoaded = false;
    local fillTypeDesc;
    local sourceVehicle, fillUnitIndex = ExtendedSprayer.getFillTypeSourceVehicle(vehicle);
    local sprayFillType = sourceVehicle:getFillUnitFillType(fillUnitIndex);
    fillTypeDesc = g_fillTypeManager:getFillTypeByIndex(sprayFillType);
    local massPerLiter = (fillTypeDesc.massPerLiter / FillTypeManager.MASS_SCALE);

    if sprayFillType == FillType.LIME or sprayFillType == FillType.LIQUIDLIME then
        hasLimeLoaded = true;
    end;

    local descriptionText = "";
    local stepResolution;

    local enableZeroTargetFlag = false;

    if hasLimeLoaded then
        self.gradient:setSliceId(self.isColorBlindMode and ExtendedSprayerHUDExtension.SLICES.COLOR_BLIND_GRADIENT or ExtendedSprayerHUDExtension.SLICES.PH_GRADIENT);
        self.gradientInactive:setSliceId(self.isColorBlindMode and ExtendedSprayerHUDExtension.SLICES.COLOR_BLIND_GRADIENT or ExtendedSprayerHUDExtension.SLICES.PH_GRADIENT);

        local pHChanged = 0;
        applicationRate = spec.lastLitersPerHectar * massPerLiter;
        if not spec.sprayAmountAutoMode then
            local requiredLitersPerHa = self.pHMap:getLimeUsageByStateChange(spec.sprayAmountManual);
            if sprayFillType == FillType.LIQUIDLIME then
                requiredLitersPerHa = requiredLitersPerHa * LiquidLimeSprayerFix.LIQUIDLIME_USAGE_FACTOR;
            end;
            pHChanged = self.pHMap:getPhValueFromChangedStates(spec.sprayAmountManual);
            applicationRate = requiredLitersPerHa * massPerLiter;

            if pHChanged > 0 then
                changeBarText = string.format("pH +%s", formatDecimalNumber(pHChanged));
            end;
        end;

        if spec.phActualValue ~= 0 and spec.phTargetValue ~= 0 and self.vehicle.isOnField then
            local pHActual = self.pHMap:getPhValueFromInternalValue(spec.phActualValue);
            local pHTarget = self.pHMap:getPhValueFromInternalValue(spec.phTargetValue);

            self.actualValue = pHActual;
            self.setValue = pHActual + pHChanged;
            self.targetValue = pHTarget;

            if spec.sprayAmountAutoMode then
                pHChanged = self.targetValue - self.actualValue;
                if pHChanged > 0 then
                    changeBarText = string.format("pH +%s", formatDecimalNumber(pHChanged));
                end;

                self.setValue = self.targetValue;
            end;

            self.actualValueStr = "pH %.3f";
            if soilTypeName ~= "" then
                if spec.sprayAmountAutoMode then
                    descriptionText = string.format(self.texts.description_limeAuto, soilTypeName, formatDecimalNumber(pHTarget));
                else
                    descriptionText = string.format(self.texts.description_limeManual, soilTypeName, formatDecimalNumber(pHTarget));
                end;
            end;

            self.hasValidValues = true;
        end;

        if self.pHMap ~= nil then
            minValue, maxValue = self.pHMap:getMinMaxValue();
        end;

        stepResolution = spec.pHMap:getPhValueFromChangedStates(1);
    else
        self.gradient:setSliceId(self.isColorBlindMode and ExtendedSprayerHUDExtension.SLICES.COLOR_BLIND_GRADIENT or ExtendedSprayerHUDExtension.SLICES.N_GRADIENT);
        self.gradientInactive:setSliceId(self.isColorBlindMode and ExtendedSprayerHUDExtension.SLICES.COLOR_BLIND_GRADIENT or ExtendedSprayerHUDExtension.SLICES.N_GRADIENT);

        local litersPerHectar = spec.lastLitersPerHectar;
        local nitrogenChanged = 0;
        if not spec.sprayAmountAutoMode then
            litersPerHectar = self.nitrogenMap:getFertilizerUsageByStateChange(spec.sprayAmountManual, sprayFillType);
            nitrogenChanged = self.nitrogenMap:getNitrogenFromChangedStates(spec.sprayAmountManual);

            if nitrogenChanged > 0 then
                changeBarText = string.format("+%dkg N/ha", nitrogenChanged);
            end;
        end;

        if spec.isSolidFertilizerSprayer then
            headline = self.texts.headline_n_solidFertilizer;
            applicationRateStr = "%d kg/ha";
            applicationRate = litersPerHectar * massPerLiter * 1000;
        elseif spec.isLiquidFertilizerSprayer then
            headline = self.texts.headline_n_liquidFertilizer;
            applicationRateStr = "%d l/ha";
            applicationRate = litersPerHectar;
        elseif spec.isSlurryTanker then
            headline = self.texts.headline_n_slurryTanker;
            applicationRateStr = "%.1f m³/ha";
            applicationRate = litersPerHectar / 1000;

            if spec.sprayAmountAutoMode and soilTypeName ~= "" then
                descriptionText = string.format(self.texts.description_slurryAuto, soilTypeName);
            end;
        elseif spec.isManureSpreader then
            headline = self.texts.headline_n_manureSpreader;
            applicationRateStr = "%.1f t/ha";
            applicationRate = litersPerHectar * massPerLiter;

            if spec.sprayAmountAutoMode and soilTypeName ~= "" then
                descriptionText = string.format(self.texts.description_manureAuto, soilTypeName);
            end;
        end;

        if spec.nActualValue > 0 and spec.nTargetValue > 0 and self.vehicle.isOnField and not spec.isDoingMissionWork then
            local nActual = self.nitrogenMap:getNitrogenValueFromInternalValue(math.clamp(spec.nActualValue, 0, self.nitrogenMap.maxValue));
            local nTarget = self.nitrogenMap:getNitrogenValueFromInternalValue(math.clamp(spec.nTargetValue, 0, self.nitrogenMap.maxValue));

            self.actualValue = nActual;
            self.setValue = nActual + nitrogenChanged;
            self.targetValue = nTarget;

            if spec.sprayAmountAutoMode then
                nitrogenChanged = self.targetValue - self.actualValue;
                if nitrogenChanged > 0 then
                    changeBarText = string.format("+%dkg N/ha", nitrogenChanged);
                end;

                self.setValue = self.targetValue;
            end;

            self.actualValueStr = "%dkg N/ha";

            local forcedFruitType;
            if vehicle.spec_sowingMachine ~= nil then
                forcedFruitType = vehicle.spec_sowingMachine.workAreaParameters.seedsFruitType;
            end;

            local fruitTypeIndex = forcedFruitType or spec.nApplyAutoModeFruitType;
            if fruitTypeIndex ~= nil then
                local fillType = g_fillTypeManager:getFillTypeByIndex(g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(fruitTypeIndex));
                if fillType ~= nil then
                    if fillType ~= FillType.UNKNOWN and soilTypeName ~= "" then
                        if nTarget > 0 then
                            if spec.sprayAmountAutoMode then
                                descriptionText = string.format(self.texts.description_fertilizerAutoFruit, fillType.title, soilTypeName);
                            else
                                descriptionText = string.format(self.texts.description_fertilizerManualFruit, fillType.title, soilTypeName);
                            end;
                        else
                            descriptionText = self.texts.description_noFertilizerRequired;
                            enableZeroTargetFlag = true;
                        end;
                    end;
                end;
            end;

            if descriptionText == "" and soilTypeName ~= "" then
                if spec.sprayAmountAutoMode then
                    descriptionText = string.format(self.texts.description_fertilizerAutoNoFruit, soilTypeName);

                    if self.nitrogenMap ~= nil then
                        local fruitTypeIndex = self.nitrogenMap:getFruitTypeIndexByFruitRequirementIndex(spec.nApplyAutoModeFruitRequirementDefaultIndex);
                        if fruitTypeIndex ~= nil then
                            local fillType = g_fillTypeManager:getFillTypeByIndex(g_fruitTypeManager:getFillTypeIndexByFruitTypeIndex(fruitTypeIndex));
                            if fillType ~= nil then
                                descriptionText = string.format(self.texts.description_fertilizerAutoNoFruitDefault, fillType.title, soilTypeName);
                            end;
                        end;
                    end;
                else
                    descriptionText = string.format(self.texts.description_fertilizerManualNoFruit, soilTypeName);
                end;
            end;

            self.hasValidValues = true;
        end;

        if self.nitrogenMap ~= nil then
            minValue, maxValue = self.nitrogenMap:getMinMaxValue();

            local nAmount = spec.lastNitrogenProportion;
            if nAmount == 0 then
                nAmount = self.nitrogenMap:getNitrogenAmountFromFillType(sprayFillType);
            end;

            if spec.isSlurryTanker then
                local str = " (~%skgN/m³)";
                if sourceVehicle.getIsUsingExactNitrogenAmount ~= nil and sourceVehicle:getIsUsingExactNitrogenAmount() then
                    str = " (%skgN/m³)";
                end;

                applicationRateStr = applicationRateStr .. string.format(str, MathUtil.round(nAmount * 1000, 1));
            else
                applicationRateStr = applicationRateStr .. string.format(" (%s%%%%N)", MathUtil.round(nAmount * 100, 1));
            end;

            stepResolution = self.nitrogenMap:getNitrogenFromChangedStates(1);
        end;
    end;

    if spec.sprayAmountAutoMode then
        applicationRateStr = applicationRateStr .. string.format(" (%s)", self.texts.automaticShort);
        soilTypeName = "";
    end;

    self.actualPos = math.min((self.actualValue - minValue) / (maxValue - minValue), 1);
    self.setValuePos = math.min((self.setValue - minValue) / (maxValue - minValue), 1);
    self.targetPos = math.min((self.targetValue - minValue) / (maxValue - minValue), 1);

    local totalHeight = self:getHeight();
    local middleHeight = totalHeight - self.backgroundTop.height - self.backgroundBottom.height;

    self.backgroundTop:setPosition(posX, posY - self.backgroundTop.height);
    self.backgroundMiddle:setPosition(posX, posY - self.backgroundTop.height - middleHeight);
    self.backgroundBottom:setPosition(posX, posY - self.backgroundTop.height - middleHeight - self.backgroundBottom.height);
    self.backgroundMiddle:setDimension(nil, middleHeight);
    self.backgroundTop:render();
    self.backgroundMiddle:render();
    self.backgroundBottom:render();

    local centerX = posX + self.backgroundTop.width * 0.5;

    setTextColor(1, 1, 1, 1);
    setTextBold(true);
    setTextAlignment(RenderText.ALIGN_CENTER);
    renderLimitedText(centerX, posY - self.textHeightHeadline * 1.1, self.textHeightHeadline, headline, self.contentMaxWidth);
    setTextBold(false);

    local gradientPosX = centerX - self.gradientInactive.width * 0.5 + self.gradientPosX;
    local gradientPosY = posY + self.gradientPosY;
    if not self.hasValidValues then
        gradientPosY = gradientPosY + (self.actualBar.height - self.gradientInactive.height) + self.textHeight;
    end;

    self.gradientInactive:setPosition(gradientPosX, gradientPosY);
    self.gradientInactive:render();

    local gradientVisibilePos = 0;
    if self.hasValidValues then
        gradientVisibilePos = self.actualPos;
    end;

    self.gradient:setPosition(gradientPosX, gradientPosY);
    self.gradient:setDimension(gradientVisibilePos * self.gradientInactive.width);

    local uvs = self.gradient.uvs;
    local uv5 = uvs[1] + (uvs[5] - uvs[1]) * gradientVisibilePos;
    local uv7 = uvs[3] + (uvs[7] - uvs[3]) * gradientVisibilePos;
    setOverlayUVs(self.gradient.overlayId, uvs[1], uvs[2], uvs[3], uvs[4], uv5, uvs[6], uv7, uvs[8]);
    self.gradient:render();

    local labelMin;
    local labelMax;
    if hasLimeLoaded then
        labelMin = string.format("pH\n%s", minValue);
        labelMax = string.format("pH\n%s", maxValue);
    else
        labelMin = string.format("%s\nkg/ha", minValue);
        labelMax = string.format("%s\nkg/ha", maxValue);
    end;

    local widthDiff = (self.backgroundTop.width - self.gradientInactive.width) * 0.25;
    renderLimitedText(posX + widthDiff, gradientPosY + self.gradientInactive.height * 0.85, self.gradientInactive.height * 1.3, labelMin);
    renderLimitedText(posX + self.backgroundTop.width - widthDiff, gradientPosY + self.gradientInactive.height * 0.85, self.gradientInactive.height * 1.3, labelMax);

    local additionalChangeLineHeight = 0;

    local changeBarRendered = false;
    if self.hasValidValues then
        local targetBarX, targetBarY;
        local showFlag = self.targetPos ~= 0 or enableZeroTargetFlag;
        if showFlag then
            targetBarX = gradientPosX + self.gradientInactive.width * self.targetPos - self.targetBar.width * 0.5;
            targetBarY = gradientPosY;
            self.targetBar:setPosition(targetBarX, targetBarY);
            self.targetBar:render();

            self.targetFlag:setPosition(targetBarX, targetBarY + self.targetBar.height);
            self.targetFlag:render();
        end;

        local actualBarText;
        local actualBarTextOffset = self.actualBar.height + self.textHeight * 1.1;
        local actualBarSkipFlagCollisionCheck = false;
        if self.actualPos ~= self.targetPos then
            actualBarText = string.format(self.texts.actualValue, string.format(self.actualValueStr, self.actualValue));
        elseif spec.sprayAmountAutoMode or self.targetPos == self.setValuePos then
            if self.targetPos ~= 0 then
                actualBarText = string.format(self.texts.targetReached, string.format(self.actualValueStr, self.actualValue));
                actualBarTextOffset = -self.textHeight * 0.7;
                actualBarSkipFlagCollisionCheck = true;
                changeBarRendered = true;
            end;
        end;

        if actualBarText ~= nil then
            local actualBarX = gradientPosX + self.gradientInactive.width * self.actualPos - self.actualBar.width * 0.5;
            local actualBarY = gradientPosY + (self.gradientInactive.height - self.actualBar.height) * 0.5;

            self.actualBar:setPosition(actualBarX, actualBarY);
            self.actualBar:render();

            local actualTextWidth = getTextWidth(self.textHeight * 0.7, actualBarText);
            actualBarX = math.max(math.min(actualBarX, (posX + self.backgroundTop.width) - actualTextWidth * 0.5), posX + actualTextWidth * 0.5);

            if not actualBarSkipFlagCollisionCheck and showFlag then
                local rightTextBorder = actualBarX + actualTextWidth * 0.5;
                if rightTextBorder > targetBarX and rightTextBorder < targetBarX + self.targetFlag.width * 0.5 then
                    actualBarX = targetBarX - actualTextWidth * 0.5 - self.pixelSizeX;
                end;

                local leftTextBorder = actualBarX - actualTextWidth * 0.5;
                if (leftTextBorder > targetBarX and leftTextBorder < targetBarX + self.targetFlag.width * 0.5)
                or (targetBarX > leftTextBorder and targetBarX < rightTextBorder) then
                    actualBarX = targetBarX + self.targetFlag.width + self.pixelSizeX + actualTextWidth * 0.5;
                end;
            end;

            renderLimitedText(actualBarX, actualBarY + actualBarTextOffset, self.textHeight * 0.7, actualBarText);
        end;

        if self.setValuePos > self.actualPos then
            local goodColor = ExtendedSprayerHUDExtension.COLOR.SET_VALUE_BAR_GOOD;
            local badColor = ExtendedSprayerHUDExtension.COLOR.SET_VALUE_BAR_BAD;
            local difference = math.min((math.abs(self.setValue - self.targetValue) / stepResolution) / 3, 1);
            local differenceInv = 1 - difference;
            local r, g, b, a = difference * badColor[1] + differenceInv * goodColor[1],
                            difference * badColor[2] + differenceInv * goodColor[2],
                            difference * badColor[3] + differenceInv * goodColor[3],
                            1;
            local setValueBarX = gradientPosX + self.gradientInactive.width * self.actualPos;
            local setValueBarY = gradientPosY - self.gradientInactive.height - self.setValueBar.height;
            self.setValueBar:setPosition(setValueBarX, setValueBarY);
            self.setValueBar:setDimension(self.gradientInactive.width * (math.min(self.setValuePos, 1) - self.actualPos));
            self.setValueBar:setColor(r, g, b, a);
            self.setValueBar:render();

            local setBarTextX = setValueBarX + self.setValueBar.width * 0.5;
            local setBarTextY = setValueBarY + self.setValueBar.height * 0.2;
            local setTextWidth = getTextWidth(self.setValueBar.height * 0.9, changeBarText);
            if setTextWidth > self.setValueBar.width * 0.95 then
                setBarTextY = setValueBarY - self.setValueBar.height;
                additionalChangeLineHeight = self.setValueBar.height;
            end;
            renderLimitedText(setBarTextX, setBarTextY, self.setValueBar.height * 0.9, changeBarText);

            changeBarRendered = true;
        end;
    else
        descriptionText = self.texts.invalidValues;
    end;

    local bottomPosY = posY - self:getHeight();

    if descriptionText ~= "" and self.additionalDisplayHeight ~= 0 then
        setTextAlignment(RenderText.ALIGN_CENTER);
        renderLimitedText(centerX, bottomPosY + self.footerOffset + self.textHeight * 1.85, self.textHeight, descriptionText, self.contentMaxWidth);
    end;

    self.footerSeparationBar:setPosition(centerX - self.footerSeparationBar.width * 0.5, bottomPosY + self.footerOffset + self.textHeight * 1.3);
    self.footerSeparationBar:render();

    setTextAlignment(RenderText.ALIGN_LEFT);
    local sideOffset = (self.backgroundTop.width - self.contentMaxWidth) * 0.5;
    local rateText = self.texts.applicationRate .. " " .. string.format(applicationRateStr, applicationRate, applicationRateReal);
    local rateWidth = renderLimitedText(posX + sideOffset, bottomPosY + self.footerOffset, self.textHeight, rateText, self.contentMaxWidth);

    if soilTypeName ~= "" then
        local maxWidth = self.contentMaxWidth - rateWidth - self.footerTextSpacing;
        setTextAlignment(RenderText.ALIGN_RIGHT);
        renderLimitedText(posX + self.backgroundTop.width - sideOffset, bottomPosY + self.footerOffset, self.textHeight, string.format(self.texts.soilType, soilTypeName), maxWidth);
    end;

    self.additionalDisplayHeight = additionalChangeLineHeight;
    if descriptionText ~= "" then
        self.additionalDisplayHeight = self.additionalDisplayHeight + self.additionalTextHeightOffset;
    end;
    if not self.hasValidValues then
        self.additionalDisplayHeight = self.additionalDisplayHeight - self.invalidHeightOffset;
    elseif not changeBarRendered then
        self.additionalDisplayHeight = self.additionalDisplayHeight - self.noSetBarHeightOffset;
    end;

    return bottomPosY;
end;


if ExtendedSprayerHUDExtension ~= nil then
    ExtendedSprayerHUDExtension.draw = Utils.overwrittenFunction(ExtendedSprayerHUDExtension.draw, LiquidLimeSprayerHUDFix.draw);
else
    Logging.info("LiquidLimeSprayerHUDFix not loaded, Precision Farming is not active");
end;