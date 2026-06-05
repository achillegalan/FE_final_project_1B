function [CVA_mat, CVA_det_mat, CVA_stoch_mat, NPV_mat] = runCVASection( ...
    swapData, OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
    isPayer, fixingFrequency, cdsSpreads, LGD, knownFixing, hazardModes, swapRiskFree)

%RUNCVASECTION Runs CVA computations for multiple CDS spreads and hazard modes 
% and prints the results.
%
% INPUTS:
%   swapData        - Table/struct with PayDate, AccrualStart, AccrualEnd, Notional.
%   OIS_Boot        - Bootstrapped OIS discounting curve.
%   EUR3M_Boot      - Bootstrapped Euribor 3M projection curve.
%   settlementDate  - Valuation date.
%   strike          - Fixed swap rate K.
%   normalVol       - Swaption normal volatility data.
%   isPayer         - Logical flag: true for payer exposure, false for receiver.
%   fixingFrequency - String flag: 'quarterly' or 'semiannual'.
%   cdsSpreads      - Vector of CDS spreads in decimal form.
%                     Example: 300 bps = 0.03.
%   LGD             - Loss Given Default parameter.
%   knownFixing     - Optional struct with fixingDate and resetRate.
%   hazardModes     - Vector/cell/string array with hazard-rate method names.
%   swapRiskFree    - Risk-free swap MtM, in EUR.
%
% OUTPUTS:
%   CVA_mat         - Matrix of total CVA values.
%                     Rows correspond to CDS spreads, columns to hazard modes.
%   CVA_det_mat     - Matrix of deterministic CVA components.
%   CVA_stoch_mat   - Matrix of stochastic CVA components.
%   NPV_mat         - Matrix of swap NPVs after CVA adjustment:
%                     NPV = swapRiskFree - CVA.

nCDS = numel(cdsSpreads);
nModes = numel(hazardModes);

CVA_mat       = zeros(nCDS, nModes);
CVA_det_mat   = zeros(nCDS, nModes);
CVA_stoch_mat = zeros(nCDS, nModes);
NPV_mat       = zeros(nCDS, nModes);

for m = 1:nModes
    [CVA_cell, ~, CVA_det_cell, CVA_stoch_cell] = arrayfun(@(s) computeCVA( ...
        swapData, OIS_Boot, EUR3M_Boot, settlementDate, strike, normalVol, ...
        isPayer, fixingFrequency, s, LGD, knownFixing, hazardModes(m)), ...
        cdsSpreads, 'UniformOutput', false);

    CVA_mat(:, m)       = [CVA_cell{:}]';
    CVA_det_mat(:, m)   = [CVA_det_cell{:}]';
    CVA_stoch_mat(:, m) = [CVA_stoch_cell{:}]';
    NPV_mat(:, m)       = swapRiskFree - CVA_mat(:, m);
end


%% Print of the table
fprintf('\n%s MtM (risk-free): %.2f EUR\n', char(fixingFrequency), swapRiskFree);

for m = 1:nModes
    fprintf('\n --- HAZARD-RATE METHOD: %s ---\n', hazardModes(m));
    fprintf('%-10s | %-14s | %-14s | %-14s | %-18s\n', ...
        'CDS (bps)', 'CVA [EUR]', 'CVA_det [EUR]', 'CVA_stoch [EUR]', 'Swap NPV with CVA');
    fprintf('%s\n', repmat('-', 1, 84));

    for k = 1:nCDS
        fprintf('%-10d | %14.2f | %14.2f | %14.2f | %18.2f\n', ...
            cdsSpreads(k)*1e4, CVA_mat(k,m), CVA_det_mat(k,m), ...
            CVA_stoch_mat(k,m), NPV_mat(k,m));
    end
end
end
