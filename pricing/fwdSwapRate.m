function S = fwdSwapRate(refDate, OISzeroRates, EURzeroRates, OISdates, EURdates, expiry, tenoryears)

% build fixedleg payments
exerciseDate = add_target_months(refDate, 12 * expiry, 'modifiedfollow');
endDate = add_target_months(refDate, 12 * tenoryears, 'modifiedfollow');

fixedPaymentDates = makeSchedule(exerciseDate, endDate, 12, 'modifiedfollow');
floatingPaymentDates = makeSchedule(exerciseDate, endDate, 3, 'modifiedfollow');

fixedTenorsFracs = yearfrac(fixedPaymentDates(1:end-1), fixedPaymentDates(2:end), 2);
floatingTenorsFracs = yearfrac(floatingPaymentDates(1:end-1), floatingPaymentDates(2:end), 2);

discounts_yearly = getTargetDF(refDate, OISdates, OISzeroRates, fixedPaymentDates);
discounts_quarterly = getTargetDF(refDate, OISdates, OISzeroRates, floatingPaymentDates);
pseudoDiscounts = getTargetDF(refDate, EURdates, EURzeroRates, floatingPaymentDates);

fwdPseudoDiscounts = (pseudoDiscounts(1:end-1) ./ pseudoDiscounts(2:end) - 1) ./ floatingTenorsFracs;
fwdDiscounts_yearly = (discounts_yearly(1:end-1) ./ discounts_yearly(2:end) - 1) ./ fixedTenorsFracs;
fwdDiscounts_quarterly = (discounts_quarterly(1:end-1) ./ discounts_quarterly(2:end) - 1) ./ floatingTenorsFracs;

betas = fwdDiscounts_quarterly/fwdPseudoDiscounts;

B_alphaprime = discounts_quarterly(1:end-1) ./ discounts_quarterly(1);
BPV = sum(fixedTenorsFracs .* fwdDiscounts_yearly);

singleCurveTerm = 1 - discounts_yearly(end) / discounts_yearly(1);
multiCurveTerm = sum((betas - 1) .* B_alphaprime);
Num = singleCurveTerm + multiCurveTerm;

S = Num / BPV;

end
