
-- AuctionatorBargain.lua
--
-- "Sniping" support: while a Full Scan runs, every auction is compared against
-- the item's median price (last 15 scans).  Auctions selling at or below a
-- configurable fraction of that median are collected as "bargains" and shown
-- in the Bargains tab, where clicking one jumps to the Buy tab and searches it
-- so you can buy it cheap and relist it higher.

local addonName, addonTable = ...;
local zc = addonTable.zc;

gBargainList     = {};		-- one entry per cheap auction found in the last full scan
gBargainSelIndex = 0;		-- highlighted row in the Bargains tab

local DEFAULT_PCT       = 70;		-- a bargain is an auction priced at or below this % of the median
local DEFAULT_MINPROFIT = 10000;	-- ignore bargains worth less than this much total profit (1g)

local gMedianCache = {};	-- name -> median, computed once per item during a scan (0 = no history)
local playerName   = nil;	-- captured at the start of each scan, to skip your own auctions

-----------------------------------------

function Atr_BargainThreshold ()

	local n = tonumber (AUCTIONATOR_BARGAIN_PCT);

	if (n and n >= 1 and n <= 99) then
		return math.floor (n);
	end

	return DEFAULT_PCT;
end

-----------------------------------------

function Atr_BargainMinProfit ()		-- minimum total profit (in copper) for a bargain to be listed

	local n = tonumber (AUCTIONATOR_BARGAIN_MINPROFIT);

	if (n and n >= 0) then
		return math.floor (n);
	end

	return DEFAULT_MINPROFIT;
end

-----------------------------------------

function Atr_ResetBargains ()

	gBargainList     = {};
	gBargainSelIndex = 0;
	playerName       = UnitName ("player");
	wipe (gMedianCache);
end

-----------------------------------------
-- Median of an item's stored scan window, computed once per item per scan and
-- cached.  Returns 0 when there is no price history (so the caller can skip).
-- Reusing this avoids allocating/sorting a fresh table for every single
-- auction in a full scan (which can be tens of thousands).

function Atr_GetScanMedian (name)

	local cached = gMedianCache[name];
	if (cached ~= nil) then
		return cached;
	end

	local median = 0;
	local win    = gAtr_MeanDB and gAtr_MeanDB[name];

	if (win and #win > 0) then
		local sorted = {};
		for i = 1, #win do sorted[i] = win[i]; end
		table.sort (sorted);

		local n = #sorted;
		if (n % 2 == 0) then
			median = math.floor ((sorted[n/2] + sorted[n/2 + 1]) / 2);
		else
			median = sorted[math.ceil (n/2)];
		end
	end

	gMedianCache[name] = median;
	return median;
end

-----------------------------------------
-- Called once per auction from the main loop of Atr_FullScanAnalyze.
-- All the per-auction data is passed in (already read by the caller) so we
-- don't re-query the API or re-walk the auction list a second time.

function Atr_CheckForBargain (x, name, texture, count, quality, perItem, median, owner)

	if (median == nil or median <= 0) then
		return;		-- no price history yet for this item
	end

	if (perItem == nil or perItem <= 0) then
		return;		-- bid-only / invalid; can't be insta-flipped
	end

	if (owner ~= nil and owner == playerName) then
		return;		-- don't "snipe" your own auctions
	end

	if (perItem > median * Atr_BargainThreshold() / 100) then
		return;		-- not cheap enough
	end

	local profit = (median - perItem) * count;		-- gross profit if you flip the whole stack

	if (profit < Atr_BargainMinProfit()) then
		return;		-- not enough money in it to bother
	end

	tinsert (gBargainList, {
		name		= name,
		link		= GetAuctionItemLink ("list", x),
		texture		= texture,
		quality		= quality or 1,
		count		= count,
		perItem		= perItem,		-- buyout per single item
		market		= median,		-- median price per single item
		profit		= profit,
		pct			= math.floor (perItem * 100 / median),
	});
end

-----------------------------------------
-- called after all auctions in a full scan have been checked

function Atr_PrintBargains ()

	table.sort (gBargainList, function (a, b) return a.profit > b.profit; end);

	if (#gBargainList > 0) then
		zc.msg_atr (string.format (ZT("Found %d bargains - see the Bargains tab"), #gBargainList));
	end
end

-----------------------------------------

local function Atr_BargainQualityColor (quality)

	if (quality == 0) then return 0.62, 0.62, 0.62; end		-- poor
	if (quality == 2) then return 0.12, 1.00, 0.00; end		-- uncommon
	if (quality == 3) then return 0.00, 0.44, 0.87; end		-- rare
	if (quality == 4) then return 0.64, 0.21, 0.93; end		-- epic
	if (quality == 5) then return 1.00, 0.50, 0.00; end		-- legendary

	return 1.0, 1.0, 1.0;									-- common / default
end

-----------------------------------------
-- renders gBargainList into the shared AuctionatorScrollFrame (12 visible rows)

function Atr_ShowBargains ()

	Atr_Col1_Heading_Button:Hide();
	Atr_Col3_Heading_Button:Hide();

	local numrows = #gBargainList;

	Atr_Col1_Heading:Show();
	Atr_Col3_Heading:Show();
	Atr_Col4_Heading:Show();

	Atr_Col1_Heading:SetText (ZT("Item Price"));
	Atr_Col3_Heading:SetText (ZT("Bargains"));
	Atr_Col4_Heading:SetText (ZT("Profit"));

	if (numrows == 0) then
		Atr_SetMessage (ZT("Run a Full Scan to find items selling below the median price."));
	else
		Atr_SetMessage ("");
	end

	local line       = 0;
	local dataOffset = FauxScrollFrame_GetOffset (AuctionatorScrollFrame);

	FauxScrollFrame_Update (AuctionatorScrollFrame, numrows, 12, 16);

	while (line < 12) do

		dataOffset = dataOffset + 1;
		line       = line + 1;

		local lineEntry = _G["AuctionatorEntry"..line];

		lineEntry:SetID (dataOffset);
		lineEntry.itemLink = nil;

		local b = gBargainList[dataOffset];

		if (dataOffset > numrows or not b) then

			lineEntry:Hide();

		else

			local tag        = "AuctionatorEntry"..line.."_PerItem_Price";
			local mf         = _G[tag];
			local itemtext   = _G["AuctionatorEntry"..line.."_PerItem_Text"];
			local text       = _G["AuctionatorEntry"..line.."_EntryText"];
			local stacktext  = _G["AuctionatorEntry"..line.."_StackPrice"];

			itemtext:SetText ("");
			text:SetText ("");
			stacktext:SetText ("");

			text:GetParent():SetPoint ("LEFT", 157, 0);

			Atr_SetMFcolor (tag);

			lineEntry:Show();
			lineEntry.itemLink = b.link;

			-- column 3: item name (coloured by quality) + stack info
			local r, g, bl = Atr_BargainQualityColor (b.quality);
			text:SetTextColor (r, g, bl);

			local label = Atr_GetUCIcon (b.name).."  "..b.name;
			if (b.count > 1) then
				label = label.."  ("..ZT("stack of").." "..b.count..")";
			end
			text:SetText (label);

			-- column 1: per-item buyout (the deal price)
			mf:Show();
			itemtext:Hide();
			MoneyFrame_Update (tag, b.perItem);

			-- column 4: total profit if flipped + per-item discount vs median
			stacktext:SetTextColor (0.1, 1.0, 0.1);
			stacktext:SetText ("+"..zc.priceToString (b.profit).."   (-"..(100 - b.pct).."%)");
		end
	end

	Atr_HighlightEntry (gBargainSelIndex);
end

-----------------------------------------
-- /snipe              show current settings
-- /snipe <1-99>       set the bargain threshold (% of median)
-- /snipe profit <g>   set the minimum total profit (in gold)

SLASH_ATRSNIPE1 = "/atrsnipe";
SLASH_ATRSNIPE2 = "/snipe";

SlashCmdList["ATRSNIPE"] = function (msg)

	msg = string.lower (msg or "");
	msg = string.gsub (msg, "^%s+", "");
	msg = string.gsub (msg, "%s+$", "");

	local pcmd, pval = string.match (msg, "^(%a+)%s+(%d+)$");

	if (pcmd == "profit" or pcmd == "lucro" or pcmd == "p") then
		AUCTIONATOR_BARGAIN_MINPROFIT = tonumber (pval) * 10000;		-- gold -> copper
		zc.msg_atr (string.format (ZT("Minimum bargain profit set to %s"), zc.priceToString (Atr_BargainMinProfit())));
		return;
	end

	local n = tonumber (msg);

	if (n and n >= 1 and n <= 99) then
		AUCTIONATOR_BARGAIN_PCT = math.floor (n);
		zc.msg_atr (string.format (ZT("Bargain threshold set to %d%% of median"), Atr_BargainThreshold()));
		return;
	end

	zc.msg_atr (string.format (ZT("Bargains: threshold %d%% of median, min profit %s"), Atr_BargainThreshold(), zc.priceToString (Atr_BargainMinProfit())));
	zc.msg_atr (ZT("Use: /snipe 1-99  or  /snipe profit <gold>"));
end
