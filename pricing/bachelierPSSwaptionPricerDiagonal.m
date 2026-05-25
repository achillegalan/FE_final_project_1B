function [price, details] = bachelierPSSwaptionPricerDiagonal( ...
    OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, TTM, Notional, isPayer, fixingFrequency)

%BACHELIERPSSWAPTIONPRICERDIAGONAL Prices a physical-settlement swaption with Bachelier formula.
%
% INPUTS:
%   - OIS_curve         Struct containing the OIS discount curve.
%                       Required fields: settlementDate, dates, zeroRates
%   - EUR3M_curve       Struct containing the Euribor 3M pseudo-discount curve.
%                       Required field: dates, zeroRates
%
%   - paymentDates      Vector of underlying swap payment dates.
%   - strike            Fixed swap rate / swaption strike.
%   - normalVol         Bachelier normal volatility in decimal units.
%   - TTM               Time to maturity / option expiry in years.
%   - Notional          Vector of amortizing notionals associated with paymentDates.
%
%   - isPayer           Optional boolean flag:  true  -> payer swaption (default)
%                                               false -> receiver swaption
%   - fixingFrequency   Optional string specifying the floating reset rule:"quarterly" (default), "semiannual"
%
% OUTPUTS:
%   - price             Swaption price in currency units, scaled by the remaining notional convention used inside the function.
%
%   - details           Struct containing intermediate quantities:
%                       - exerciseDate
%                       - remainingNotional
%                       - yearFracs
%                       - optionDiscount
%                       - annuityFwd
%                       - forwardSwapRate
%                       - strike
%                       - normalVol
%                       - stdDev


    if nargin < 8 || isempty(isPayer)
        isPayer = true;
    end
    if nargin < 9 || isempty(fixingFrequency)
        fixingFrequency = "quarterly";
    end

    paymentDates = paymentDates(:);
    Notional = Notional(:);

    settleDate = OIS_curve.settlementDate;
    exerciseDate = add_target_months(settleDate, round(12 * TTM), 'modifiedfollow');

    % Keep only coupons strictly after option expiry.
    remaining = paymentDates > exerciseDate;
    paymentDates = paymentDates(remaining);
    remainingNotional = Notional(remaining);

    % Accrual fractions (ACT/360) for underlying coupons.
    accrualStartDates = [exerciseDate; paymentDates(1:end-1)];
    yearFracs = yearfrac(accrualStartDates, paymentDates, 2);

    % Discounting to expiry-forward measure.
    optionDiscount = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, exerciseDate);
    paymentDiscounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, paymentDates);
    fwdDiscounts = paymentDiscounts ./ optionDiscount;

    % Projection from pseudo-discount curve (3M).
    pseudoDiscounts = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, paymentDates);
    pseudoAtExpiry = getTargetDF(settleDate, EUR3M_curve.dates, EUR3M_curve.zeroRates, exerciseDate);
    pseudoFull = [pseudoAtExpiry; pseudoDiscounts];

    quarterlyFwdRates = (pseudoFull(1:end-1) ./ pseudoFull(2:end) - 1) ./ yearFracs;

    if fixingFrequency == "semiannual"
        fixingRates = quarterlyFwdRates;
        fixingRates(2:2:end) = quarterlyFwdRates(1:2:end-1);
    else
        fixingRates = quarterlyFwdRates;
    end

    % Amortized forward annuity and forward swap rate.
    % COMMENT: N_alpha in the formula I am pretty sure is the first notional
    % available (as Locatelli actually told us I believe during the call, but
    % also as suggested by notation explanation in the PDF file)
    amortizedNotional = remainingNotional ./ remainingNotional(1);
    annuityFwd = sum(yearFracs .* amortizedNotional .* fwdDiscounts);

    floatLegFwdValue = sum(fwdDiscounts .* yearFracs .* amortizedNotional .* fixingRates);
    forwardSwapRate = floatLegFwdValue / annuityFwd;

    %% Bachelier closed-form.
    w = 2 * double(isPayer) - 1;        % +1 payer, -1 receiver
    stdDev = normalVol * sqrt(TTM);

    if stdDev <= eps
        intrinsic = max(w * (forwardSwapRate - strike), 0);
        price = optionDiscount * annuityFwd * intrinsic;
    else
        d = (forwardSwapRate - strike) / stdDev;
        phi = exp(-0.5 * d^2) / sqrt(2*pi);
        Nwd = 0.5 * erfc(-(w * d) / sqrt(2));   % N(w*d)
        price = optionDiscount * annuityFwd * (w * (forwardSwapRate - strike) * Nwd + stdDev * phi);
    end

    details = struct();
    details.exerciseDate = exerciseDate;
    details.remainingNotional = remainingNotional;
    details.yearFracs = yearFracs;
    details.optionDiscount = optionDiscount;
    details.annuityFwd = annuityFwd;
    details.forwardSwapRate = forwardSwapRate;
    details.strike = strike;
    details.normalVol = normalVol;
    details.stdDev = stdDev;
end