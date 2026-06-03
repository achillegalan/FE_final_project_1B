function printCVATable(yearLabel, swapRiskFree, cdsSpreads, hazardNames, ...
    CVA_mat, CVA_det_mat, CVA_stoch_mat, NPV_mat)

%PRINTCVATABLE Prints a formatted CVA results table.
%
% INPUTS:
%   yearLabel       - String/char label identifying the valuation year/date.
%   swapRiskFree    - Risk-free MtM of the swap, in EUR.
%   cdsSpreads      - Vector of CDS spreads in decimal form.
%                     Example: 300 bps = 0.03.
%   hazardNames     - Vector/cell/string array with names of hazard-rate methods.
%   CVA_mat         - Matrix of total CVA values.
%                     Rows correspond to CDS spreads, columns to hazard modes.
%   CVA_det_mat     - Matrix of deterministic CVA components.
%   CVA_stoch_mat   - Matrix of stochastic CVA components.
%   NPV_mat         - Matrix of swap NPVs after CVA adjustment.


nCDS = numel(cdsSpreads);
nModes = numel(hazardNames);

fprintf('\nQuarterly MtM (risk-free) %s: %.2f EUR\n', yearLabel, swapRiskFree);

for m = 1:nModes
    fprintf('\n --- HAZARD-RATE METHOD: %s ---\n', hazardNames(m));
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
