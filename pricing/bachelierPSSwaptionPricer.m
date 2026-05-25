function price = bachelierPSSwaptionPricer( ...
    OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, TTM, Notional, isPayer, fixingFrequency)
%BACHELIERPSSWAPTIONPRICER Physical-settlement swaption under Bachelier.
%
% INPUTS:
%   OIS_curve    - OIS discount curve struct with settlementDate, dates,
%                  zeroRates.
%   EUR3M_curve  - Euribor 3M pseudo-discount curve struct with dates,
%                  zeroRates.
%   paymentDates - Full amortizing swap payment schedule.
%   strike       - Fixed rate K.
%   normalVol    - Bachelier/normal volatility of the forward swap rate.
%   TTM          - Option expiry in years from OIS_curve.settlementDate.
%   Notional     - Amortizing notionals, one per quarterly payment.
%   isPayer      - Logical flag: true for payer, false for receiver.
%   fixingFrequency - Optional. 'semiannual' or 'quarterly'. Logical true
%                  means semiannual, false means quarterly. Default is
%                  'semiannual'.
%
% OUTPUTS:
%   price           - Time-0 physical-settlement swaption price.

settleDate = OIS_curve.settlementDate;
exerciseDate = add_target_months(settleDate, 12 * TTM, 'modifiedfollow');

paymentDates = paymentDates(:);
Notional = Notional(:);

% We filter the actual valid payment days to compute the quantities of
% interest
remainingPayments = paymentDates > exerciseDate;
paymentDates = paymentDates(remainingPayments);
remainingNotional = Notional(remainingPayments);

% Interpolation to get the right discounts
accrualStartDates = [exerciseDate; paymentDates(1:end-1)];
yearFracs = yearfrac(accrualStartDates, paymentDates, 2); % ACT/360

% Discounting
optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
paymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, paymentDates);
fwdDiscounts = paymentDiscounts ./ optionDiscount;

% Pseudo - Discounting
pseudoDiscounts = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, paymentDates);
pseudoDiscountsAtExpiry = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
pseudoDiscountsFull = [pseudoDiscountsAtExpiry; pseudoDiscounts];

quarterlyFwdRates = (pseudoDiscountsFull(1:end-1) ./ pseudoDiscountsFull(2:end) - 1) ./ yearFracs;

if fixingFrequency == "semiannual"
    fixingRates = quarterlyFwdRates;
    fixingRates(2:2:end) = quarterlyFwdRates(1:2:end-1);
else
    fixingRates = quarterlyFwdRates;
end

% Computing Ammortized BPV and Swap Rate
% COMMENT: N_alpha in the formula I am pretty sure is the first notional
% available (as Locatelli actually told us I believe during the call, but
% also as suggested by notation explanation in the PDF file)
ammortizedNotional = remainingNotional ./ remainingNotional(1);
ammortizedBPV = sum(yearFracs .* ammortizedNotional .* fwdDiscounts);

floatingLegFwdValue = sum(fwdDiscounts .* yearFracs .* ...
    ammortizedNotional .* fixingRates);

ammortizedFwdSwapRate = floatingLegFwdValue / ammortizedBPV;

% Actual Swaption formula
stdDev = normalVol * sqrt(TTM); 
d = (ammortizedFwdSwapRate - strike) / stdDev;
phi = exp(-0.5 * d^2) / sqrt(2*pi);
Phi = 0.5 * erfc(-d / sqrt(2));

if isPayer
    price = optionDiscount * ammortizedBPV * ((ammortizedFwdSwapRate - strike) * Phi + stdDev * phi);
else
    price = optionDiscount * ammortizedBPV * ((strike - ammortizedFwdSwapRate) * (1 - Phi) + stdDev * phi);
end

end
