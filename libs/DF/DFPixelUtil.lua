DFPixelUtil = {};

local function GetRegionEffectiveScale(region)
	while not region.GetEffectiveScale do
		region = region:GetParent();
	end
	return region:GetEffectiveScale();
end

function DFPixelUtil.GetPixelToUIUnitFactor()
	local physicalHeight;
	if GetPhysicalScreenSize then
		physicalHeight = select(2, GetPhysicalScreenSize());
	else
		physicalHeight = GetScreenHeight() * UIParent:GetEffectiveScale();
	end
	return 768.0 / physicalHeight;
end

function DFPixelUtil.GetNearestPixelSize(uiUnitSize, layoutScale, minPixels)
	if uiUnitSize == 0 and (not minPixels or minPixels == 0) then
		return 0;
	end

	local uiUnitFactor = DFPixelUtil.GetPixelToUIUnitFactor();
	local numPixels = math.floor((uiUnitSize * layoutScale) / uiUnitFactor + 0.5);
	local rawNumPixels = numPixels;
	if minPixels then
		if uiUnitSize < 0.0 then
			if numPixels > -minPixels then
				numPixels = -minPixels;
			end
		else
			if numPixels < minPixels then
				numPixels = minPixels;
			end
		end
	end

	return numPixels * uiUnitFactor / layoutScale;
end

function DFPixelUtil.SetWidth(region, width, minPixels)
	region:SetWidth(DFPixelUtil.GetNearestPixelSize(width, GetRegionEffectiveScale(region), minPixels));
end

function DFPixelUtil.SetHeight(region, height, minPixels)
	region:SetHeight(DFPixelUtil.GetNearestPixelSize(height, GetRegionEffectiveScale(region), minPixels));
end

function DFPixelUtil.SetSize(region, width, height, minWidthPixels, minHeightPixels)
	DFPixelUtil.SetWidth(region, width, minWidthPixels);
	DFPixelUtil.SetHeight(region, height, minHeightPixels);
end

function DFPixelUtil.SetPoint(region, point, relativeTo, relativePoint, offsetX, offsetY, minOffsetXPixels, minOffsetYPixels)
	region:SetPoint(point, relativeTo, relativePoint, 
		DFPixelUtil.GetNearestPixelSize(offsetX, GetRegionEffectiveScale(region), minOffsetXPixels), 
		DFPixelUtil.GetNearestPixelSize(offsetY, GetRegionEffectiveScale(region), minOffsetYPixels)
	);
end

function DFPixelUtil.SetStatusBarValue(statusBar, value)
	local width = statusBar:GetWidth();
	if width and width > 0.0 then
		local min, max = statusBar:GetMinMaxValues();
		local percent = max == min and 0 or math.max(0, math.min(1, (value - min) / (max - min)));
		if percent == 0.0 or percent == 1.0 then
			statusBar:SetValue(value);
		else
			local numPixels = DFPixelUtil.GetNearestPixelSize(statusBar:GetWidth() * percent, statusBar:GetEffectiveScale());
			local roundedValue = Lerp(min, max, numPixels / width);
			statusBar:SetValue(roundedValue);
		end
	else
		statusBar:SetValue(value);
	end
end
