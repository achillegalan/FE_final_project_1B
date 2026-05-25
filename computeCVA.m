function [CVA, survProbs] = computeCVA( ...
     OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, TTMs, Notional, ...
     isPayer, fixingFrequency,cdsSpreads,LGD)

% Bootstrapping the survival probabilities from CDS market data (Vectorized
% as possible)
survProbs = bootstrapSurvivalProbabilities(OIS_curve, paymentDates, cdsSpreads, LGD);
CVAsurvProbs = survProbs(1:end-1) - survProbs(2:end);

% Computing the Swaptions in CVA
% COMMENT: not suggested vectorization! it is likely that trying to
% vectorize over a for loop will not win the trade off with not having to
% write a function which is a pain in the ass
swaptionPrices = zeros(numel(TTMs), 1);

for i = 1:numel(TTMs)
    swaptionPrices(i) = bachelierPSSwaptionPricer( ...
        OIS_curve, EUR3M_curve, paymentDates, strike, normalVol, ...
        TTMs(i), Notional, isPayer, fixingFrequency);
end

CVA = LGD * sum(CVAsurvProbs .* swaptionPrices);

end