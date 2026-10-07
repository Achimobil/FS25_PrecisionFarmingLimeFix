LiquidLimeSprayerFix = {};

-- Ohne geladenes Precision Farming gibt es ExtendedSprayer nicht, dann werden die Hooks am Dateiende übersprungen.
local precisionFarming = _G["FS25_precisionFarming"];
local ExtendedSprayer = precisionFarming ~= nil and precisionFarming.ExtendedSprayer or nil;

-- Anteil der Masse an festem Kalk, den Flüssigkalk für dieselbe Wirkung braucht.
LiquidLimeSprayerFix.LIQUIDLIME_MASS_FACTOR = 0.8;

-- Mindestgewicht je Liter von Flüssigkalk als Vielfaches von festem Kalk.
-- Im Wasser liegt der Kalk dichter als locker geschüttet, Flüssigkalk ist deshalb schwerer als fester Kalk.
LiquidLimeSprayerFix.LIQUIDLIME_MIN_WEIGHT_FACTOR = 1.2;

-- Anteil der PF-Kalkliter, den Flüssigkalk verbraucht.
-- PF rechnet für jede Füllart mit denselben Litern je pH-Stufe, die für festen Kalk ausgelegt sind.
-- Wird beim Laden der Karte in LiquidLimeSprayerFix:loadMap aus den Gewichten der Füllarten berechnet.
LiquidLimeSprayerFix.liquidLimeUsageFactor = 1;

-- Ab hier überschrieben um auch Flüssigkalk zu unerstützen
-- Achtung. Flüssigkalk muss in der Map vorhanden sein, sonst gibt es lua fehler
function LiquidLimeSprayerFix.isLimeFillType(fillType)
    return fillType == FillType.LIME or fillType == FillType.LIQUIDLIME;
end


function LiquidLimeSprayerFix:getCurrentSprayerMode(superFunc)
    local sprayer, fillUnitIndex = ExtendedSprayer.getFillTypeSourceVehicle(self);
    local fillType = sprayer:getFillUnitFillType(fillUnitIndex);

    if fillType == FillType.UNKNOWN then
        if self:getIsAIActive() then
            return false, true;
        end;

        fillType = sprayer:getFillUnitLastValidFillType(fillUnitIndex);
    end;

    if LiquidLimeSprayerFix.isLimeFillType(fillType) then
        return true, false;
    elseif self[ExtendedSprayer.SPEC_TABLE_NAME].nitrogenMap:getFillTypeIsFertilizer(fillType) then
        return false, true;
    elseif fillType == FillType.HERBICIDE then
        return false, false;
    else
        return false, false;
    end;
end


function LiquidLimeSprayerFix:onChangedFillType(superFunc, fillUnitIndex, fillTypeIndex, partOfNode)
    local spec = self[ExtendedSprayer.SPEC_TABLE_NAME];

    if spec.isSolidFertilizerSprayer and LiquidLimeSprayerFix.isLimeFillType(fillTypeIndex) then
        local _, _, pHMaxValue = spec.pHMap:getMinMaxValue();
        spec.sprayAmountManualMax = pHMaxValue - 1;
    else
        local _, _, nMaxValue = spec.nitrogenMap:getMinMaxValue();
        spec.sprayAmountManualMax = nMaxValue - 1;
    end;

    if superFunc ~= nil then
        superFunc(self, fillUnitIndex, fillTypeIndex, partOfNode);
    end;
end


function LiquidLimeSprayerFix:onEndWorkAreaProcessing(superFunc, dt, hasProcessed)
    if superFunc ~= nil then
        superFunc(self, dt, hasProcessed);
    end;

    local specSprayer = self.spec_sprayer;

    if self.isServer and specSprayer.workAreaParameters.isActive then
        if (specSprayer.workAreaParameters.sprayVehicle ~= nil or self:getIsAIActive()) and self:getIsTurnedOn() then
            -- Festen Kalk zählt PF selbst, hier kommt nur Flüssigkalk dazu.
            if specSprayer.workAreaParameters.sprayFillType == FillType.LIQUIDLIME then
                self:updatePFStatistic("usedLime", specSprayer.workAreaParameters.usage);
                self:updatePFStatistic("usedLimeRegular", self[ExtendedSprayer.SPEC_TABLE_NAME].lastRegularUsage);
            end;
        end;
    end;
end


---Streifen ohne gültigen Messpunkt bekommen beim Kalken Bodenart, Ist- und Zielwert ihrer eigenen Mitte.
---PF findet keinen Messpunkt, wenn bis 10 m voraus nur schon gekalkter Boden liegt, etwa in der Überlappung zur vorherigen Spur.
---Es setzt dann den Durchschnitt aller Streifen ein, dadurch bekommt eine Bodenart am Übergang den Zielwert der anderen.
---Streuer mit zwei Hauptbereichen bleiben unverändert, ebenso Streifen ohne Bodenprobe in der Mitte.
---@param superFunc function Original-Funktion
---@param workArea table Arbeitsbereich
function LiquidLimeSprayerFix:updateWorkAreaSubSectionData(superFunc, workArea)
    superFunc(self, workArea);

    local spec = self[ExtendedSprayer.SPEC_TABLE_NAME];
    if not spec.isLiming or workArea.subSectionData == nil or workArea.numMainDivisions ~= 1 then
        return;
    end;

    local startX, _, startZ = getWorldTranslation(workArea.start);
    local widthX, _, widthZ = getWorldTranslation(workArea.width);
    local dirX = widthX - startX;
    local dirZ = widthZ - startZ;
    local width = MathUtil.vector2Length(dirX, dirZ);
    if width == 0 then
        return;
    end;

    dirX = dirX / width;
    dirZ = dirZ / width;
    local subSectionWidth = width / workArea.numSubDivisions;

    for index = 1, workArea.numSubDivisions do
        local subSectionData = workArea.subSectionData[index];
        if not subSectionData.isValid then
            local x = startX + dirX * (index - 0.5) * subSectionWidth;
            local z = startZ + dirZ * (index - 0.5) * subSectionWidth;
            local phLevel = spec.pHMap:getLevelAtWorldPos(x, z);

            if phLevel > 0 then
                local soilTypeIndex = spec.soilMap:getTypeIndexAtWorldPos(x, z);
                subSectionData.soilTypeIndex = soilTypeIndex;
                subSectionData.phLevel = phLevel;
                subSectionData.phTargetLevel = spec.pHMap:getOptimalPHValueForSoilTypeIndex(soilTypeIndex);
            end;
        end;
    end;
end;


---Rechnet die von PF berechnete Kalkmenge bei Flüssigkalk mit liquidLimeUsageFactor um.
---Angepasst werden Verbrauch, die Menge je ha für das HUD und die Vergleichsmenge für die PF-Statistik.
---Die Wirkung auf den pH-Wert bleibt unverändert.
---@param superFunc function Original-Funktion von ExtendedSprayer
---@param vehicleSuperFunc function Vorherige Funktion in der Fahrzeug-Kette
---@param fillType number Füllart
---@param dt number Zeit seit dem letzten Frame in ms
---@return number usage Verbrauch in Litern
function LiquidLimeSprayerFix:getSprayerUsage(superFunc, vehicleSuperFunc, fillType, dt)
    local usage = superFunc(self, vehicleSuperFunc, fillType, dt);

    local spec = self[ExtendedSprayer.SPEC_TABLE_NAME];
    if fillType == FillType.LIQUIDLIME and spec.isLiming and spec.pHMap ~= nil and self:getIsTurnedOn() then
        local factor = LiquidLimeSprayerFix.liquidLimeUsageFactor;
        usage = usage * factor;
        spec.lastLitersPerHectar = spec.lastLitersPerHectar * factor;
        spec.lastRegularUsage = spec.lastRegularUsage * factor;
    end;

    return usage;
end;


---Berechnet liquidLimeUsageFactor aus den Gewichten je Liter, die die Karte für Kalk und Flüssigkalk angibt.
---Flüssigkalk ist etwa zur Hälfte Wasser, der fein gemahlene Kalk darin wirkt aber etwa doppelt so stark wie fester Kalk.
---Für dieselbe Wirkung braucht es damit dieselbe Masse, in Litern also das Verhältnis der Gewichte je Liter.
---Davon wird noch LIQUIDLIME_MASS_FACTOR genommen.
---Ist Flüssigkalk leichter als LIQUIDLIME_MIN_WEIGHT_FACTOR mal fester Kalk, wird mit diesem Mindestgewicht gerechnet und gewarnt.
---Das HUD rechnet weiter mit dem Gewicht der Karte und zeigt dann falsche Mengen an.
---Fehlt Flüssigkalk auf der Karte, landet ein Fehler im Log.
---@param filename string Dateiname der Karte
function LiquidLimeSprayerFix:loadMap(filename) ---@diagnostic disable-line: unused-local
    local liquidLimeFillType = g_fillTypeManager:getFillTypeByName("LIQUIDLIME");
    if liquidLimeFillType == nil then
        Logging.error("LiquidLimeSprayerFix: fill type LIQUIDLIME does not exist, liquid lime is not supported");
        return;
    end;

    local limeFillType = g_fillTypeManager:getFillTypeByName("LIME");
    local liquidLimeMassPerLiter = liquidLimeFillType.massPerLiter;
    local minMassPerLiter = limeFillType.massPerLiter * LiquidLimeSprayerFix.LIQUIDLIME_MIN_WEIGHT_FACTOR;
    if liquidLimeMassPerLiter < minMassPerLiter then
        Logging.warning(
            "LiquidLimeSprayerFix: unrealistic liquid lime weight of %.2f kg/l in the map, calculating with %.2f kg/l, so the liquid lime rates in the Precision Farming HUD are wrong",
            liquidLimeMassPerLiter * 1000,
            minMassPerLiter * 1000
        );
        liquidLimeMassPerLiter = minMassPerLiter;
    end;

    local massRatio = limeFillType.massPerLiter / liquidLimeMassPerLiter;
    LiquidLimeSprayerFix.liquidLimeUsageFactor = massRatio * LiquidLimeSprayerFix.LIQUIDLIME_MASS_FACTOR;
end;


if ExtendedSprayer ~= nil then
    addModEventListener(LiquidLimeSprayerFix);
    ExtendedSprayer.getCurrentSprayerMode = Utils.overwrittenFunction(ExtendedSprayer.getCurrentSprayerMode, LiquidLimeSprayerFix.getCurrentSprayerMode);
    ExtendedSprayer.onChangedFillType = Utils.overwrittenFunction(ExtendedSprayer.onChangedFillType, LiquidLimeSprayerFix.onChangedFillType);
    ExtendedSprayer.onEndWorkAreaProcessing = Utils.overwrittenFunction(ExtendedSprayer.onEndWorkAreaProcessing, LiquidLimeSprayerFix.onEndWorkAreaProcessing);
    ExtendedSprayer.updateWorkAreaSubSectionData = Utils.overwrittenFunction(ExtendedSprayer.updateWorkAreaSubSectionData, LiquidLimeSprayerFix.updateWorkAreaSubSectionData);
    ExtendedSprayer.getSprayerUsage = Utils.overwrittenFunction(ExtendedSprayer.getSprayerUsage, LiquidLimeSprayerFix.getSprayerUsage);
else
    Logging.info("LiquidLimeSprayerFix not loaded, Precision Farming is not active");
end;

