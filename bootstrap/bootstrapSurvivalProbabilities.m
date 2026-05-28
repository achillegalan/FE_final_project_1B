function [survivalProbabilities, hazardRates, cdsDates] = ...
    bootstrapSurvivalProbabilities(OIS_curve, cdsDates, cdsSpreads, LGD)
%BOOTSTRAPSURVIVALPROBABILITIES Bootstrap Q(0,T) from CDS spreads.
%
% INPUTS:
%   OIS_curve  : OIS curve struct with fields settlementDate, dates, zeroRates.
%   cdsDates   : Quarterly CDS payment dates (datetime vector).
%   cdsSpreads : CDS spreads in decimal form (e.g. 300 bp = 0.03).
%                Can be scalar (flat across all dates) or one value per date.
%   LGD        : Loss-given-default in decimal form (e.g. 0.40).
%
% OUTPUTS:
%   survivalProbabilities : Bootstrapped Q(0,T_i) at each cds date.
%   hazardRates           : Bucket hazard rates corresponding to each interval.
%   cdsDates              : Echo of input cdsDates, returned as column vector.

settleDate = OIS_curve.settlementDate;
cdsDates = cdsDates(:);
N = numel(cdsDates); 

if isscalar(cdsSpreads)
    cdsSpreads = repmat(cdsSpreads, N, 1);  % Expand scalar spreads to match the number of dates
end
cdsSpreads = cdsSpreads(:);

% Precompute everything that does not change across the loop
allDates = [settleDate; cdsDates];          % T_0, T_1, ..., T_N

% Element-wise year fraction computations
accrualFracs = yearfrac(allDates(1:end-1), cdsDates, 2);   % ACT/360 for premium leg
bucketLengths = yearfrac(allDates(1:end-1), cdsDates, 2);  % ACT/360 to match curve rules
discounts = getTargetDF(settleDate, OIS_curve.dates, OIS_curve.zeroRates, cdsDates);

% Bootstrap Survival Probabilities
survivalProbabilities = zeros(N, 1);
hazardRates = zeros(N, 1);

for n = 1:N
    % Known survival: Q(T_0)=1, Q(T_1), ..., Q(T_{n-1})
    knownSurvival = [1; survivalProbabilities(1:n-1)];
    
    % Slices up to and including the current tenor
    payFracs = accrualFracs(1:n);
    payDisc = discounts(1:n);
    dt = bucketLengths(n);
    prevSurv = knownSurvival(end);   % Q(T_{n-1})
    s = cdsSpreads(min(n, end));
    
    objective = @(h) cdsObjective(h, s, LGD, payFracs, payDisc, ...
        knownSurvival, prevSurv, dt);
    
    % Root-finding bounds to [0, 50] 
    hazardRates(n) = fzero(objective, [0, 50]); 
    survivalProbabilities(n) = prevSurv * exp(-hazardRates(n) * dt);
end

end

% -------------------------------------------------------------------------
function value = cdsObjective(h, spread, LGD, accrualFracs, discounts, ...
    knownSurvival, prevSurv, dt)
% Residual for the nth-bucket calibration equation (premium - protection).

% Trial Q(T_n):
Q_n = prevSurv * exp(-h * dt);

survivalEnd = [knownSurvival(2:end); Q_n];   % Q(T_1), ..., Q(T_n)
survivalStart = knownSurvival;                  % Q(T_0), ..., Q(T_{n-1})

% Premium Leg MTM component
premiumLeg = spread * sum(accrualFracs .* discounts .* survivalEnd);

% Protection Leg MTM component (assuming default payments at the end of quarterly intervals)
protectionLeg = LGD * sum(discounts .* (survivalStart - survivalEnd));

% Root-finder searches for the point where Protection PV = Premium PV
value = premiumLeg - protectionLeg; 
end
