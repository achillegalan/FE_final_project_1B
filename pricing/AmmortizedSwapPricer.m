function swapPrice = AmmortizedSwapPricer( ...
    swapData, oisCurve, pseudoCurve, settlementDate, fixedRate, resetType, knownFixing)

%AMMORTIZEDSWAPPRICER Price an amortizing IRS from the bank perspective.
%
% Computes the risk-free MtM of an amortizing swap:
%   swapPrice = PV(floating leg) - PV(fixed leg)
%
% Inputs:
%   swapData        Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   oisCurve        OIS discounting curve with dates and continuous zeroRates.
%   pseudoCurve     EUR3M projection curve with dates and continuous zeroRates.
%   settlementDate  Pricing date; only PayDate > valuationDate are considered.
%   fixedRate       Fixed coupon rate, in decimal form.
%   resetType       'quarterly' or 'semiannual'. Default: 'quarterly'.
%   knownFixing     Optional struct with resetStartDate and resetRate for
%                   already-fixed coupons.
%
% Outputs:
%   swapPrice       Bank MtM: receive floating, pay fixed.

% Defaults
if nargin < 6 || isempty(resetType)
    resetType = 'quarterly';
end
if nargin < 7 || isempty(knownFixing)
    knownFixing = struct('resetStartDate', NaT, 'resetRate', NaN);
end


% Extract and shape data
paymentDates       = swapData.PayDate(:);
accrualStartDates  = swapData.AccrualStart(:);
accrualEndDates    = swapData.AccrualEnd(:);
ammortizedNotional = swapData.Notional(:);

curveDates      = oisCurve.dates(:);
zeroRates       = oisCurve.zeroRates(:);
pseudocurveDates = pseudoCurve.dates(:);
pseudozeroRates  = pseudoCurve.zeroRates(:);

% al posto di queste righe quelle sotto
knownDates = knownFixing.resetStartDate(:);
knownRates = knownFixing.resetRate(:);

% % Support both interfaces:
% % - preferred: knownFixing.fixingDate
% % - backward compatible: knownFixing.resetStartDate (converted to fixingDate = start-2bd)
% if isfield(knownFixing, 'fixingDate')
%     knownFixDates = knownFixing.fixingDate(:);
% elseif isfield(knownFixing, 'resetStartDate')
%     knownFixDates = arrayfun(@(d) add_target_business_days(d, -2), knownFixing.resetStartDate(:));
% else
%     knownFixDates = NaT(0,1);
% end
% knownRates = knownFixing.resetRate(:);

%% Keep only future payment flows
check = paymentDates > settlementDate;  
payDates = paymentDates(check);
accStart = accrualStartDates(check);
accEnd = accrualEndDates(check);
notional = ammortizedNotional(check);
keptFullIdx = find(check);

%% Map reset dates for kept coupons
resetType = lower(string(strtrim(resetType)));

switch resetType
    case "quarterly"
        resetStart = accStart;
        resetEnd = accEnd;

    case "semiannual"
        % Legacy: same 3M fixing of the first trimester of the couple
        pairStartIdxFull = 2 * ceil(keptFullIdx / 2) - 1;   % 1,1,3,3,...
        resetStart = accrualStartDates(pairStartIdxFull);
        resetEnd = accrualEndDates(pairStartIdxFull);

    otherwise
        error('AmmortizedSwapPricer:InvalidResetType', ...
            'resetType must be ''quarterly'' or ''semiannual''.');
end

%% Year fractions and discounting
yearfracs = yearfrac(accStart, accEnd, 2); % ACT/360
discounts = getTargetDF(settlementDate, curveDates, zeroRates, payDates);

%% Fixed leg
fixedCashFlows = yearfracs .* fixedRate .* notional;
fixedPrice = dot(fixedCashFlows, discounts);

%% Floating leg
floatingRates = zeros(size(yearfracs));

% couponFixDates = arrayfun(@(d) add_target_business_days(d, -2), resetStart);

for k = 1:numel(yearfracs)

    % al posto di questa parte quella sotto
    if resetStart(k) < settlementDate
        % Coupon already fixed before valuation date -> use known historical fixing
        idxKnown = find(knownDates == resetStart(k), 1);
        floatingRates(k) = knownRates(idxKnown);
    else
        % Project from pseudo-curve
        Pstart = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetStart(k));
        Pend   = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetEnd(k));
        deltaReset = yearfrac(resetStart(k), resetEnd(k), 2); % ACT/360 del periodo di reset
        floatingRates(k) = (Pstart / Pend - 1) / deltaReset;
    end

    % if couponFixDates(k) <= settlementDate
    %     idxKnown = find(knownFixDates == couponFixDates(k), 1);
    %     if isempty(idxKnown)
    %         error('AmmortizedSwapPricer:MissingKnownFixing', ...
    %             'Missing known fixing for coupon %d (fixing date %s, reset start %s).', ...
    %             k, datestr(couponFixDates(k)), datestr(resetStart(k)));
    %     end
    %     floatingRates(k) = knownRates(idxKnown);
    % else
    %     % Project from pseudo-curve
    %     Pstart = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetStart(k));
    %     Pend   = getTargetDF(settlementDate, pseudocurveDates, pseudozeroRates, resetEnd(k));
    %     deltaReset = yearfrac(resetStart(k), resetEnd(k), 2);
    %     floatingRates(k) = (Pstart / Pend - 1) / deltaReset;
    % end
end

floatingCashFlows = floatingRates .* yearfracs .* notional;
floatingPrice = dot(floatingCashFlows, discounts);

%% Bank MtM = receive float - pay fixed
swapPrice = floatingPrice - fixedPrice;

end
