
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

local DEFAULT_PCT = 70;		-- a bargain is an auction priced at or below this % of the median

-----------------------------------------

function Atr_BargainThreshold ()

	local n = tonumber (AUCTIONATOR_BARGAIN_PCT);

	if (n and n >= 1 and n <= 99) then
		return math.floor (n);
	end

	return DEFAULT_PCT;
end

-----------------------------------------

function Atr_ResetBargains ()

	gBargainList     = {};
	gBargainSelIndex = 0;
end

-----------------------------------------
-- called once per auction during Atr_FullScanAnalyze

function Atr_CheckForBargain (x)

	local name, texture, count, quality, canUse, level, minBid, minIncrement, buyoutPrice = GetAuctionItemInfo ("list", x);

	if (name == nil or count == nil or count == 0) then
		return;
	end

	if (buyoutPrice == nil or buyoutPrice == 0) then
		return;		-- bid-only auctions can't be insta-flipped
	end

	local perItem = math.floor (buyoutPrice / count);

	if (perItem <= 0) then
		return;
	end

	local market = Atr_GetMeanPrice (name);		-- median of the last 15 scans

	if (market == nil or market <= 0) then
		return;		-- no price history yet for this item
	end

	local threshold = market * Atr_BargainThreshold() / 100;

	if (perItem <= threshold) then

		tinsert (gBargainList, {
			name		= name,
			link		= GetAuctionItemLink ("list", x),
			texture		= texture,
			quality		= quality or 1,
			count		= count,
			buyoutPrice	= buyoutPrice,					-- total buyout for the whole stack
			perItem		= perItem,						-- buyout per single item
			market		= market,						-- median price per single item
			profit		= (market - perItem) * count,	-- gross profit if you flip the whole stack
			pct			= math.floor (perItem * 100 / market),
		});
	end
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
	Atr_Col4_Heading:SetText (ZT("Auction median"));

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

			-- column 4: median price per item + discount
			stacktext:SetTextColor (0.1, 1.0, 0.1);
			stacktext:SetText (zc.priceToString (b.market).."  (-"..(100 - b.pct).."%)");
		end
	end

	Atr_HighlightEntry (gBargainSelIndex);
end

-----------------------------------------
-- /snipe <1-99>   set the bargain threshold (% of median)

SLASH_ATRSNIPE1 = "/atrsnipe";
SLASH_ATRSNIPE2 = "/snipe";

SlashCmdList["ATRSNIPE"] = function (msg)

	local n = tonumber (msg);

	if (n and n >= 1 and n <= 99) then
		AUCTIONATOR_BARGAIN_PCT = math.floor (n);
		zc.msg_atr (string.format (ZT("Bargain threshold set to %d%% of median"), Atr_BargainThreshold()));
	else
		zc.msg_atr (string.format (ZT("Bargain threshold is %d%% of median (use /snipe 1-99 to change)"), Atr_BargainThreshold()));
	end
end
