function [swapPrice, fixedPrice, floatingPrice] = AmmortizedSwapPricer(paymentDates, ...
    curveDates, pseudocurveDates, ammortizedNotional,zeroRates, pseudozeroRates, fixedRate, settleDate)

%COMMENT: Thanks to God the payment dates for both legs are the same ;)

% Computing yearfracs tenors
allDates = [settleDate; paymentDates];
yearfracs = yearfrac(allDates(1:end-1), allDates(2:end), 2); %Act/360 (look annex)

% Get right (pseudo)Discounts
discounts = getTargetDF(settleDate, curveDates, zeroRates, paymentDates);
pseudodiscounts = getTargetDF(settleDate, pseudocurveDates, pseudozeroRates, paymentDates);

% Fixed Leg Price
fixedCashFlows = yearfracs .* fixedRate .* ammortizedNotional;
fixedPrice = dot(fixedCashFlows, discounts);

% Floating Leg Price

%COMMENT: i will comment better in the docstring, but this filtering of
%pseudodiscounts comes from the annex
%(RMK: Reset Dates: 2 BD prior to each semiannually calculation start date)
% ==> "semiannualy" fixing is the reason
% BUT ASK TO LOCATELLI

%COMMENT: rememeber that MATLAB handles this perfectly using end, even if
%the last element is not, for example, in an odd index
%(same for even indices)

% Get fwd pseudoscounts from the spot interpolated ones
pseudodiscountsFull = [1; pseudodiscounts];
pseudoFwdRates = (pseudodiscountsFull(1:end-1) ./ pseudodiscountsFull(2:end) - 1) ./ yearfracs;
floatingLegfwdRates = pseudoFwdRates(1:2:end);

yearfracsEvenTenors = yearfracs(2:2:end);
ammortizedNotionalEven = ammortizedNotional(2:2:end);
discountsEvenTenors = discounts(2:2:end);

yearfracsOddTenors = yearfracs(1:2:end);
ammortizedNotionalOdd = ammortizedNotional(1:2:end);
discountsOddTenors = discounts(1:2:end);


floatingPrice = dot(discountsOddTenors .* floatingLegfwdRates .* ...
                yearfracsOddTenors, ammortizedNotionalOdd) ...
                + dot(discountsEvenTenors .* floatingLegfwdRates .* ...
                yearfracsEvenTenors, ammortizedNotionalEven);

%COMMENT: abs values since the sign depends on the POV of the contract
%we are interested in the "absolute" price
swapPrice = abs(floatingPrice - fixedPrice);

end



